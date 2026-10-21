"""命令分发器。

提供 @command 装饰器用于注册 bpy 命令处理函数，
以及 CommandDispatcher 类用于按 JSON-RPC method 名称
查找并调用对应的 handler。

设计要点：
  - 装饰器仅做注册，不额外包装函数，保持零开销。
  - 分发器在初始化时触发 handlers 包的导入，
    从而自动完成所有 @command 的注册。
"""
from __future__ import annotations

from typing import Any, Callable

from blender_mcp.shared.errors import BlenderMCPError, ErrorCode

# ── 全局命令注册表 ─────────────────────────────────────────────
# key: 点分方法名 (如 "mesh.add_primitive")
# value: 对应的处理函数
_command_registry: dict[str, Callable[..., Any]] = {}


def command(method_name: str) -> Callable:
    """将函数注册为 JSON-RPC 命令处理器的装饰器。

    Usage::

        @command("mesh.add_primitive")
        def add_primitive(type: str = "cube", ...) -> dict:
            ...

    Args:
        method_name: 点分命名空间方法名，如 ``"scene.list_objects"``。

    Returns:
        原始函数（不做包装，零运行时开销）。
    """
    def decorator(func: Callable) -> Callable:
        _command_registry[method_name] = func
        return func                         # 直接返回原函数，不做多余包装
    return decorator


class CommandDispatcher:
    """JSON-RPC 命令分发器。

    在构造时自动导入 ``handlers`` 包以触发所有 ``@command`` 装饰器的注册。
    运行时根据 ``method`` 字符串从注册表中查找并调用对应函数。
    """

    def __init__(self) -> None:
        # 导入 handlers 包会触发其 __init__.py 中的子模块导入，
        # 进而执行每个 handler 文件顶层的 @command 装饰器。
        from . import handlers  # noqa: F401

    def dispatch(self, method: str, params: dict) -> Any:
        """查找并调用指定方法的处理函数。

        Args:
            method: 点分方法名，如 ``'mesh.add_primitive'``。
            params: 从 JSON-RPC 请求中解析出的参数字典。

        Returns:
            处理函数的返回值（将被 JSON 序列化后发回客户端）。

        Raises:
            BlenderMCPError: 方法未注册 (HANDLER_NOT_FOUND) 或参数不匹配 (INVALID_PARAMS)。
        """
        handler = _command_registry.get(method)
        if handler is None:
            raise BlenderMCPError(
                ErrorCode.HANDLER_NOT_FOUND,
                f"Unknown method: '{method}'. "
                f"Available: {sorted(_command_registry.keys())}",
            )
        try:
            return handler(**params)
        except BlenderMCPError:
            raise                           # 已经是规范错误，直接上抛
        except TypeError as exc:
            raise BlenderMCPError(
                ErrorCode.INVALID_PARAMS,
                f"Invalid params for '{method}': {exc}",
            ) from exc
