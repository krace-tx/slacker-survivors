"""Blender MCP 主服务编排器 (Service Orchestrator)。

对齐 Godot MCP ``mcp_server.gd``：负责装配

    TcpTransport (网络)  ─┐
    BlenderContext (bpy) ─┼─▶ RPCDispatcher ─▶ CommandRegistry ◀─ Modules
    CommandRegistry      ─┘

并通过 ``bpy.app.timers`` 驱动传输层轮询。本类自身不包含任何业务逻辑。
"""
from __future__ import annotations

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from ..shared.constants import DEFAULT_HOST, DEFAULT_PORT, MAX_MESSAGES_PER_POLL, POLL_INTERVAL
from ..shared.protocol import encode_message
from .blender_context import BlenderContext
from .modules import ALL_MODULES
from .registry.command_registry import CommandRegistry
from .rpc.rpc_dispatcher import RPCDispatcher
from .transport.tcp_transport import TcpTransport


class MCPService:
    """MCP 服务生命周期管理。"""

    def __init__(self) -> None:
        self.context = BlenderContext()
        self.registry = CommandRegistry()
        self.transport = TcpTransport()
        self.dispatcher = RPCDispatcher(self.registry, undo_pusher=self.context.push_undo)

        # 装配各自治业务模块
        self.modules = [module_cls(self.context) for module_cls in ALL_MODULES]
        for module in self.modules:
            module.register_commands(self.registry)

        # 连接传输层回调
        self.transport.on_message = self._on_message_received
        # 缓存绑定方法：每次访问 self._tick 都会生成新对象，timers.is_registered 需要同一引用
        self._tick_fn = self._tick

    # ── 生命周期 ───────────────────────────────────────────────

    @property
    def is_running(self) -> bool:
        return self.transport.is_active

    @property
    def client_count(self) -> int:
        return self.transport.client_count

    @property
    def port(self) -> int:
        return self.transport.port

    def start(self, port: int = DEFAULT_PORT, host: str = DEFAULT_HOST) -> None:
        """启动监听。端口被占用等错误以 ``OSError`` 抛出，由 UI 层报告。"""
        print("\n=== BLENDER MCP INITIALIZING (MODULAR ARCHITECTURE) ===")
        self.transport.start(port, host)
        if not bpy.app.timers.is_registered(self._tick_fn):
            bpy.app.timers.register(self._tick_fn, first_interval=POLL_INTERVAL, persistent=True)
        print(f"=== BLENDER MCP READY: {len(self.registry.primary_names())} commands ===\n")

    def stop(self) -> None:
        if bpy.app.timers.is_registered(self._tick_fn):
            bpy.app.timers.unregister(self._tick_fn)
        self.transport.stop()
        print("=== BLENDER MCP SHUTDOWN ===")

    # ── 驱动 ───────────────────────────────────────────────────

    def _tick(self) -> float | None:
        if not self.transport.is_active:
            return None  # 注销定时器
        try:
            self.transport.poll(max_messages=MAX_MESSAGES_PER_POLL)
        except Exception as exc:  # noqa: BLE001 — 定时器内异常会导致其被永久注销，必须兜底
            print(f"[MCP Service] Poll error: {exc}")
        return POLL_INTERVAL

    def _on_message_received(self, client_id: int, text: str) -> None:
        response = self.dispatcher.dispatch(text)
        if response is not None:
            self.transport.send_text(client_id, encode_message(response))
