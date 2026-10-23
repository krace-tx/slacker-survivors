"""系统级 Tools：连通性检测与运行环境信息。"""
from __future__ import annotations

from ..utils import call, get_blender_connection
from ._group import ToolGroup

system_tools = ToolGroup("system")


@system_tools.tool(read_only=True)
async def blender_ping() -> str:
    """Check if Blender is running and the MCP addon server is reachable."""
    try:
        result = await get_blender_connection().send_command("system.ping")
    except Exception as exc:  # noqa: BLE001 — ping 需要把失败原因作为正常文本返回
        return f"❌ Cannot reach Blender: {exc}"
    return f"✅ Blender is connected! Version: {result.get('blender_version', 'unknown')}"


@system_tools.tool(read_only=True)
async def blender_info() -> str:
    """Get Blender runtime info: version, open .blend file path, unsaved state, available render engines."""
    return await call("Blender Info", "system.info")
