"""指令模块基类 (Base Command Module)。

对齐 Godot MCP ``modules/base_module.gd``：模块只关注业务逻辑，
通过 ``BlenderContext`` 访问 Blender 状态，完全解耦网络传输层。

编写约定：
  1. 在 ``register_commands`` 中通过 ``registry.register_command`` 声明指令，
     参数 Schema 是默认值的唯一事实来源。
  2. handler 签名统一为 ``handler(self, p: dict) -> dict``，``p`` 已完成校验与默认值回填。
  3. 失败时 ``raise RpcError.xxx(...)``；寻址类错误交给 ``ctx.get_*`` 自动抛出。
  4. 只读查询注册时传 ``undoable=False``，避免污染撤销栈。
"""
from __future__ import annotations

from ..blender_context import BlenderContext
from ..registry.command_registry import CommandRegistry
from ..rpc.rpc_error import RpcError

__all__ = ["BaseModule", "BlenderContext", "CommandRegistry", "RpcError"]


class BaseModule:
    """所有指令模块的基类。"""

    def __init__(self, ctx: BlenderContext) -> None:
        self.ctx = ctx

    def register_commands(self, registry: CommandRegistry) -> None:
        """子类重写以注册领域指令。"""
        raise NotImplementedError
