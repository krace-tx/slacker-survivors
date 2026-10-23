"""专职网络传输层 (TCP Transport)。

对齐 Godot MCP ``transport/ws_transport.gd``：只负责 TCP 监听、连接管理、
NDJSON 报文帧的拆包与发送，不感知任何业务语义。

设计约束：
  - Blender 的 Python 运行时是单线程的，所有 bpy 操作必须在主线程执行，
    因此传输层不使用 threading / asyncio，而是由编排器在 ``bpy.app.timers``
    中周期性调用 ``poll()`` 做协作式非阻塞 IO。
  - 严格绑定 127.0.0.1 本地回环地址。
  - 支持多客户端并存：当 AI 客户端重启 MCP Server 而旧连接尚未释放时，
    新进程仍可立即连上，不会被“僵尸连接”占位阻塞。
"""
from __future__ import annotations

import socket
from typing import Callable

from ...shared.constants import BUFFER_SIZE, DEFAULT_HOST, DEFAULT_PORT, SEND_TIMEOUT
from ...shared.protocol import ENCODING, FRAME_DELIMITER

MessageCallback = Callable[[int, str], None]
ClientCallback = Callable[[int], None]


class _ClientPeer:
    """单个客户端连接及其接收缓冲区。"""

    __slots__ = ("id", "sock", "address", "buffer")

    def __init__(self, client_id: int, sock: socket.socket, address: tuple) -> None:
        self.id = client_id
        self.sock = sock
        self.address = address
        self.buffer = bytearray()


class TcpTransport:
    """非阻塞 NDJSON-over-TCP 传输层。

    回调（均在 ``poll()`` 调用栈内同步触发）：
        - ``on_message(client_id, text)``：收到一条完整报文。
        - ``on_client_connected(client_id)`` / ``on_client_disconnected(client_id)``。
    """

    def __init__(self) -> None:
        self.on_message: MessageCallback | None = None
        self.on_client_connected: ClientCallback | None = None
        self.on_client_disconnected: ClientCallback | None = None

        self._server: socket.socket | None = None
        self._clients: dict[int, _ClientPeer] = {}
        self._next_client_id: int = 1
        self.host: str = DEFAULT_HOST
        self.port: int = DEFAULT_PORT

    # ── 生命周期 ───────────────────────────────────────────────

    def start(self, port: int = DEFAULT_PORT, host: str = DEFAULT_HOST) -> None:
        """开始监听。失败时抛出 ``OSError``（如端口被占用）。"""
        if self._server is not None:
            return
        self.host, self.port = host, port
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            # Windows 下 SO_REUSEADDR 允许多进程抢占同一端口，改用独占语义
            if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
                server.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            else:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind((host, port))
            server.listen(4)
            server.setblocking(False)
        except OSError:
            server.close()
            raise
        self._server = server
        print(f"[MCP Transport] Listening on tcp://{host}:{port}")

    def stop(self) -> None:
        for client_id in list(self._clients):
            self._drop(client_id, notify=False)
        if self._server is not None:
            try:
                self._server.close()
            except OSError:
                pass
            self._server = None
            print("[MCP Transport] Server stopped.")

    @property
    def is_active(self) -> bool:
        return self._server is not None

    @property
    def client_count(self) -> int:
        return len(self._clients)

    # ── 轮询 ───────────────────────────────────────────────────

    def poll(self, max_messages: int = 0) -> None:
        """接受新连接并读取所有客户端数据。

        Args:
            max_messages: 本次最多派发的报文数（0 表示不限）。超出部分留在
                缓冲区中，下次 ``poll()`` 继续处理，避免单帧卡死 UI。
        """
        if self._server is None:
            return
        self._accept_pending()

        dispatched = 0
        for client_id in list(self._clients):
            client = self._clients.get(client_id)
            if client is None:
                continue
            if not self._read_available(client):
                continue
            while FRAME_DELIMITER in client.buffer:
                if max_messages and dispatched >= max_messages:
                    return
                line, _, rest = bytes(client.buffer).partition(FRAME_DELIMITER)
                client.buffer = bytearray(rest)
                text = line.decode(ENCODING, errors="replace").strip()
                if not text:
                    continue
                dispatched += 1
                if self.on_message is not None:
                    self.on_message(client_id, text)
                if client_id not in self._clients:  # 回调中连接已被关闭
                    break

    def send_text(self, client_id: int, payload: bytes | str) -> bool:
        """向指定客户端发送一条完整报文（调用方负责附带帧分隔符）。"""
        client = self._clients.get(client_id)
        if client is None:
            return False
        data = payload.encode(ENCODING) if isinstance(payload, str) else payload
        try:
            # 非阻塞 socket 的 sendall 在大报文时可能抛 BlockingIOError，临时切换为带超时阻塞
            client.sock.settimeout(SEND_TIMEOUT)
            client.sock.sendall(data)
            return True
        except OSError as exc:
            print(f"[MCP Transport Client {client_id}] Send error: {exc}")
            self._drop(client_id)
            return False
        finally:
            if client_id in self._clients:
                client.sock.setblocking(False)

    # ── 内部 ───────────────────────────────────────────────────

    def _accept_pending(self) -> None:
        assert self._server is not None
        while True:
            try:
                sock, address = self._server.accept()
            except (BlockingIOError, InterruptedError):
                return
            except OSError as exc:
                print(f"[MCP Transport] Accept error: {exc}")
                return
            sock.setblocking(False)
            client_id = self._next_client_id
            self._next_client_id += 1
            self._clients[client_id] = _ClientPeer(client_id, sock, address)
            print(f"[MCP Transport Client {client_id}] Connected from {address[0]}:{address[1]}")
            if self.on_client_connected is not None:
                self.on_client_connected(client_id)

    def _read_available(self, client: _ClientPeer) -> bool:
        """读空内核缓冲区。返回连接是否仍然存活。"""
        while True:
            try:
                chunk = client.sock.recv(BUFFER_SIZE)
            except (BlockingIOError, InterruptedError):
                return True
            except OSError as exc:
                print(f"[MCP Transport Client {client.id}] Read error: {exc}")
                self._drop(client.id)
                return False
            if not chunk:
                print(f"[MCP Transport Client {client.id}] Disconnected")
                self._drop(client.id)
                return False
            client.buffer.extend(chunk)

    def _drop(self, client_id: int, notify: bool = True) -> None:
        client = self._clients.pop(client_id, None)
        if client is None:
            return
        try:
            client.sock.close()
        except OSError:
            pass
        if notify and self.on_client_disconnected is not None:
            self.on_client_disconnected(client_id)
