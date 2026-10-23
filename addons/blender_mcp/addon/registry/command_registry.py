"""指令统一注册表 (Command Registry)。

对齐 Godot MCP ``registry/command_registry.gd``：集中管理系统内暴露的所有
可调指令规范，支持别名（兼容旧方法名），并提供自省发现能力 (``rpc.discover``)。
"""
from __future__ import annotations

from typing import Any

from .command_spec import CommandSpec, Handler


class CommandRegistry:
    """指令注册表。"""

    def __init__(self) -> None:
        self._specs: dict[str, CommandSpec] = {}
        self._primary_names: list[str] = []   # 主方法名，避免 discover 中出现别名重复
        self._aliases: dict[str, str] = {}    # alias -> primary

    def register(self, spec: CommandSpec) -> CommandSpec:
        if spec.name in self._specs and spec.name not in self._aliases:
            print(f"[MCP Registry] Warning: command '{spec.name}' is re-registered")
        self._specs[spec.name] = spec
        if spec.name not in self._primary_names:
            self._primary_names.append(spec.name)
        return spec

    def register_command(
        self,
        name: str,
        description: str,
        parameters: dict[str, dict[str, Any]],
        handler: Handler,
        undoable: bool = True,
    ) -> CommandSpec:
        """便捷注册：直接以字段构造 CommandSpec 并注册。"""
        return self.register(CommandSpec(name, description, parameters, handler, undoable))

    def register_alias(self, alias_name: str, target_command_name: str) -> None:
        """为已注册指令声明别名（用于兼容历史方法名）。"""
        spec = self._specs.get(target_command_name)
        if spec is None:
            raise KeyError(f"Cannot alias '{alias_name}': target '{target_command_name}' is not registered")
        self._specs[alias_name] = spec
        self._aliases[alias_name] = target_command_name

    def find(self, name: str) -> CommandSpec | None:
        return self._specs.get(name)

    def has_command(self, name: str) -> bool:
        return name in self._specs

    def primary_names(self) -> list[str]:
        return list(self._primary_names)

    def discover(self) -> list[dict[str, Any]]:
        """``rpc.discover`` 实现：返回全部主指令的 Schema 清单（附带别名）。"""
        out: list[dict[str, Any]] = []
        for name in self._primary_names:
            schema = self._specs[name].to_schema()
            aliases = [a for a, target in self._aliases.items() if target == name]
            if aliases:
                schema["aliases"] = aliases
            out.append(schema)
        return out
