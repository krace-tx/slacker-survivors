"""Blender 内嵌 TCP Socket 服务器。

运行在 Blender 主进程内部，通过 ``bpy.app.timers`` 注册一个
周期性定时器来轮询非阻塞 TCP Socket，实现与外部 MCP Server
进程之间的 JSON-RPC 2.0 通信。

设计约束：
  - Blender 的 Python 运行时是单线程的，所有 bpy 操作
    必须发生在主线程上。因此不能使用 threading/asyncio，
    只能使用 ``bpy.app.timers`` 做协作式非阻塞 IO。
  - 一次只接受一个客户端连接（MCP Server 进程）。
"""
from __future__ import annotations

import json
import socket
import traceback
from typing import Any

import bpy

from blender_mcp.shared.constants import (
    BUFFER_SIZE,
    DEFAULT_HOST,
    DEFAULT_PORT,
    POLL_INTERVAL,
)
from blender_mcp.shared.errors import BlenderMCPError

from .dispatcher import CommandDispatcher


# ── JSON-RPC 2.0 标准错误码 ───────────────────────────────────
_PARSE_ERROR = -32700
_INTERNAL_ERROR = -32000


class AddonSocketServer:
    """非阻塞 TCP 服务器，通过 Blender 定时器驱动。

    生命周期:
        1. ``start()`` → 创建 socket、绑定端口、注册定时器
        2. 定时器每 ``POLL_INTERVAL`` 秒触发一次 ``_poll()``
        3. ``_poll()`` 中接受连接、读取数据、处理命令
        4. ``stop()`` → 关闭连接、注销定时器
    """

    def __init__(
        self,
        host: str = DEFAULT_HOST,
        port: int = DEFAULT_PORT,
    ) -> None:
        self._host = host
        self._port = port
        self._server_socket: socket.socket | None = None
        self._client_socket: socket.socket | None = None
        self._buffer: str = ""
        self._is_running: bool = False
        self._dispatcher = CommandDispatcher()

    # ── 公共属性 ───────────────────────────────────────────────

    @property
    def is_running(self) -> bool:
        """服务器是否正在运行。"""
        return self._is_running

    @property
    def client_connected(self) -> bool:
        """是否有客户端已连接。"""
        return self._client_socket is not None

    # ── 生命周期方法 ───────────────────────────────────────────

    def start(self) -> None:
        """启动 TCP 服务器并注册 Blender 定时器。"""
        self._server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server_socket.bind((self._host, self._port))
        self._server_socket.listen(1)
        self._server_socket.setblocking(False)
        self._is_running = True
        bpy.app.timers.register(
            self._poll,
            first_interval=POLL_INTERVAL,
            persistent=True,
        )
        print(f"[MCP] Server listening on {self._host}:{self._port}")

    def stop(self) -> None:
        """停止服务器并释放所有资源。"""
        self._is_running = False
        self._close_client()
        if self._server_socket:
            try:
                self._server_socket.close()
            except OSError:
                pass
            self._server_socket = None
        print("[MCP] Server stopped")

    # ── 定时器回调 ─────────────────────────────────────────────

    def _poll(self) -> float | None:
        """定时器回调：接受连接并处理消息。

        Returns:
            下次轮询的间隔秒数，返回 None 则注销定时器。
        """
        if not self._is_running:
            return None

        self._try_accept()
        self._try_recv()

        return POLL_INTERVAL

    def _try_accept(self) -> None:
        """尝试接受新的客户端连接（非阻塞）。"""
        if not self._server_socket or self._client_socket:
            return
        try:
            self._client_socket, addr = self._server_socket.accept()
            self._client_socket.setblocking(False)
            self._buffer = ""
            print(f"[MCP] Client connected from {addr}")
        except BlockingIOError:
            pass  # 没有待接受的连接，正常跳过
        except OSError as exc:
            print(f"[MCP] Accept error: {exc}")

    def _try_recv(self) -> None:
        """尝试从客户端读取数据（非阻塞）。"""
        if not self._client_socket:
            return
        try:
            data = self._client_socket.recv(BUFFER_SIZE)
            if data:
                self._buffer += data.decode("utf-8")
                self._process_buffer()
            else:
                # 收到空数据表示客户端主动断开
                print("[MCP] Client disconnected")
                self._close_client()
        except BlockingIOError:
            pass  # 暂无数据可读，正常跳过
        except ConnectionResetError:
            print("[MCP] Client connection reset")
            self._close_client()
        except OSError as exc:
            print(f"[MCP] Read error: {exc}")
            traceback.print_exc()

    # ── 消息处理 ───────────────────────────────────────────────

    def _process_buffer(self) -> None:
        """从缓冲区中解析并处理所有完整的 JSON 消息。

        消息以换行符 ``\\n`` 分隔（Newline-Delimited JSON）。
        """
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
                response = self._handle_request(request)
                if response is not None:     # notification 无需响应
                    self._send_response(response)
            except json.JSONDecodeError as exc:
                print(f"[MCP] Invalid JSON: {exc}")
                self._send_response({
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": _PARSE_ERROR, "message": "Parse error"},
                })

    def _handle_request(self, request: dict) -> dict[str, Any] | None:
        """处理单条 JSON-RPC 请求。

        - 若请求无 ``id``，视为 notification，不返回响应。
        - ``system.ping`` 由服务器内部直接处理。
        - 其余命令交由 dispatcher 分发到对应 handler。
        - 每次命令执行前自动 undo_push，支持撤销。
        """
        method: str = request.get("method", "")
        params: dict = request.get("params", {})
        req_id = request.get("id")

        # notification（无 id）不需要响应
        if req_id is None:
            return None

        # 内置命令：心跳检测
        if method == "system.ping":
            return self._make_success(req_id, {
                "status": "pong",
                "blender_version": ".".join(str(v) for v in bpy.app.version),
            })

        # 业务命令：推入 undo 栈后分发
        try:
            bpy.ops.ed.undo_push(message=f"MCP: {method}")
            result = self._dispatcher.dispatch(method, params)
            return self._make_success(req_id, result)
        except BlenderMCPError as exc:
            return self._make_error(req_id, int(exc.code), exc.message, exc.data)
        except Exception as exc:
            traceback.print_exc()
            return self._make_error(req_id, _INTERNAL_ERROR, str(exc))

    # ── 响应构造与发送 ─────────────────────────────────────────

    @staticmethod
    def _make_success(req_id: str, result: Any) -> dict:
        """构造 JSON-RPC 成功响应。"""
        return {"jsonrpc": "2.0", "id": req_id, "result": result}

    @staticmethod
    def _make_error(
        req_id: str,
        code: int,
        message: str,
        data: dict | None = None,
    ) -> dict:
        """构造 JSON-RPC 错误响应。"""
        error: dict = {"code": code, "message": message}
        if data:
            error["data"] = data
        return {"jsonrpc": "2.0", "id": req_id, "error": error}

    def _send_response(self, response: dict) -> None:
        """将 JSON 响应发送给客户端。"""
        if not self._client_socket:
            return
        try:
            payload = json.dumps(response) + "\n"
            self._client_socket.sendall(payload.encode("utf-8"))
        except OSError as exc:
            print(f"[MCP] Send error: {exc}")
            self._close_client()

    # ── 内部工具 ───────────────────────────────────────────────

    def _close_client(self) -> None:
        """安全关闭客户端连接。"""
        if self._client_socket:
            try:
                self._client_socket.close()
            except OSError:
                pass
            self._client_socket = None
            self._buffer = ""
