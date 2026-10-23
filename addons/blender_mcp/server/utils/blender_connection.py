"""Blender Addon 连接管理 (Blender Connection)。

对齐 Godot MCP ``server/src/utils/godot_connection.ts``：
单例异步 TCP 客户端，负责连接 / 自动重连、请求-响应关联、超时与错误归一化。

协议：换行符分隔的 JSON-RPC 2.0（见 ``blender_mcp.shared.protocol``）。
"""
from __future__ import annotations

import asyncio
import itertools
import sys
from typing import Any

from mcp.server.mcpserver.exceptions import ToolError

from ...shared.constants import BRIDGE_TIMEOUT, CONNECT_TIMEOUT, DEFAULT_HOST, DEFAULT_PORT
from ...shared.protocol import ErrorCode, decode_message, encode_message, make_request

# 单条响应最大长度（StreamReader 默认 64KB，场景对象列表可能超出）
_STREAM_LIMIT = 16 * 1024 * 1024

_START_HINT = (
    "Make sure Blender is running and the MCP addon server is started "
    "(3D Viewport > N panel > MCP > Start Server)."
)


def log(message: str) -> None:
    """stdio 传输下 stdout 被 MCP 协议占用，日志一律写 stderr。"""
    print(f"[Blender MCP] {message}", file=sys.stderr, flush=True)


class BlenderError(ToolError):
    """Blender 返回的 JSON-RPC 错误（继承 ToolError 以向 AI 客户端透传完整错误信息）。"""

    def __init__(self, code: int, message: str, data: Any = None) -> None:
        self.code = code
        self.message = message
        self.data = data
        try:
            label = ErrorCode(code).name
        except ValueError:
            label = str(code)
        detail = f"Blender error [{label}]: {message}"
        if isinstance(data, dict) and data.get("available"):
            detail += f" (available: {data['available']})"
        super().__init__(detail)


class BlenderConnection:
    """与 Blender Addon 通信的异步 TCP 客户端。

    - 请求串行化：Blender 主线程逐条处理指令，客户端以锁保证读写配对。
    - 自动重连：首次调用或连接失效时自动建立连接；若复用的旧连接已失效
      （例如 Blender 端重启了服务），自动重连并重试一次。
    """

    def __init__(self, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT,
                 timeout: float = BRIDGE_TIMEOUT) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._lock = asyncio.Lock()
        self._ids = itertools.count(1)

    @property
    def is_connected(self) -> bool:
        return self._writer is not None and not self._writer.is_closing()

    async def connect(self) -> None:
        if self.is_connected:
            return
        try:
            self._reader, self._writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port, limit=_STREAM_LIMIT),
                timeout=CONNECT_TIMEOUT,
            )
        except (OSError, asyncio.TimeoutError) as exc:
            self._reader = self._writer = None
            raise ConnectionError(f"Cannot connect to Blender at {self.host}:{self.port} ({exc}). {_START_HINT}") from exc
        log(f"Connected to Blender at {self.host}:{self.port}")

    async def disconnect(self) -> None:
        writer, self._reader, self._writer = self._writer, None, None
        if writer is not None:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:  # noqa: BLE001
                pass

    async def send_command(self, method: str, params: dict[str, Any] | None = None,
                           timeout: float | None = None) -> Any:
        """发送一条指令并等待结果。

        Raises:
            ConnectionError: 无法连接或连接中断。
            TimeoutError: 超时未响应。
            BlenderError: Blender 返回了 JSON-RPC 错误。
        """
        async with self._lock:
            reused = self.is_connected
            await self.connect()
            try:
                return await self._roundtrip(method, params or {}, timeout or self.timeout)
            except _StaleConnection:
                await self.disconnect()
                if not reused:
                    raise ConnectionError(f"Blender closed the connection. {_START_HINT}") from None
                log("Stale connection detected, reconnecting...")
                await self.connect()
                try:
                    return await self._roundtrip(method, params or {}, timeout or self.timeout)
                except _StaleConnection:
                    await self.disconnect()
                    raise ConnectionError(f"Lost connection to Blender. {_START_HINT}") from None

    async def _roundtrip(self, method: str, params: dict[str, Any], timeout: float) -> Any:
        assert self._reader is not None and self._writer is not None
        request_id = next(self._ids)
        try:
            self._writer.write(encode_message(make_request(request_id, method, params)))
            await self._writer.drain()
        except (ConnectionError, OSError) as exc:
            raise _StaleConnection() from exc

        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        while True:
            remaining = deadline - loop.time()
            try:
                line = await asyncio.wait_for(self._reader.readline(), timeout=max(remaining, 0.01))
            except asyncio.TimeoutError:
                # 迟到的响应会与后续请求错位，直接断开以重置会话
                await self.disconnect()
                raise TimeoutError(f"Blender did not respond to '{method}' within {timeout:.0f}s") from None
            except (ConnectionError, OSError) as exc:
                raise _StaleConnection() from exc

            if not line:
                raise _StaleConnection()

            try:
                response = decode_message(line)
            except ValueError:
                log(f"Ignoring malformed response: {line[:200]!r}")
                continue
            if not isinstance(response, dict) or response.get("id") != request_id:
                continue  # 丢弃与当前请求无关的报文

            if "error" in response:
                err = response["error"] or {}
                raise BlenderError(err.get("code", ErrorCode.INTERNAL_ERROR),
                                   err.get("message", "Unknown error"), err.get("data"))
            return response.get("result", {})


class _StaleConnection(Exception):
    """内部信号：连接在请求发出 / 等待期间失效。"""


# ── 单例 ───────────────────────────────────────────────────────

_instance: BlenderConnection | None = None


def configure_connection(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT,
                         timeout: float = BRIDGE_TIMEOUT) -> BlenderConnection:
    """（重新）配置单例连接参数，应在服务启动时调用一次。"""
    global _instance
    _instance = BlenderConnection(host, port, timeout)
    return _instance


def get_blender_connection() -> BlenderConnection:
    """获取单例连接（未配置时使用默认参数）。"""
    global _instance
    if _instance is None:
        _instance = BlenderConnection()
    return _instance
