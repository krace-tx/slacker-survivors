"""编辑器与协议自省 MCP Resources：运行环境状态与 ``rpc.discover`` 指令清单。

对齐 Godot MCP ``server/src/resources/editor_resources.ts``。
"""
from __future__ import annotations

from ...shared.protocol import METHOD_DISCOVER
from ..utils import fetch_json
from ._group import ResourceGroup

editor_resources = ResourceGroup("editor")


@editor_resources.resource(
    "blender://editor/state",
    name="Blender Editor State",
    description="Blender runtime info: version, open .blend file, unsaved changes, available render engines.",
)
async def editor_state_resource() -> str:
    return await fetch_json("system.info")


@editor_resources.resource(
    "blender://rpc/commands",
    name="Blender RPC Command Schemas",
    description="All registered Addon RPC commands and their JSON Schemas via rpc.discover.",
)
async def rpc_commands_resource() -> str:
    return await fetch_json(METHOD_DISCOVER)
