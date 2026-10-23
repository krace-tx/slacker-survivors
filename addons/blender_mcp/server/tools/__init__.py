"""MCP Tool 注册包。

每个领域文件声明一个 ``ToolGroup``，在此集中汇总。新增领域时只需
在 ``ALL_TOOL_GROUPS`` 中追加即可被入口自动装配。
"""
from __future__ import annotations

from ._group import ToolGroup
from .environment_tools import camera_tools, light_tools
from .material_tools import material_tools
from .modeling_tools import modeling_tools
from .modifier_tools import modifier_tools
from .render_tools import render_tools
from .scene_tools import scene_tools
from .system_tools import system_tools

ALL_TOOL_GROUPS: tuple[ToolGroup, ...] = (
    system_tools,
    scene_tools,
    modeling_tools,
    modifier_tools,
    material_tools,
    camera_tools,
    light_tools,
    render_tools,
)

__all__ = ["ALL_TOOL_GROUPS", "ToolGroup"]
