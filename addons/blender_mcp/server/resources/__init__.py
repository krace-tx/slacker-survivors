"""MCP Resource 注册包。

对齐 Godot MCP ``server/src/resources/``：汇总场景与编辑器状态资源。
"""
from __future__ import annotations

from ._group import ResourceGroup
from .editor_resources import editor_resources
from .scene_resources import scene_resources

ALL_RESOURCE_GROUPS: tuple[ResourceGroup, ...] = (
    scene_resources,
    editor_resources,
)

__all__ = ["ALL_RESOURCE_GROUPS", "ResourceGroup"]
