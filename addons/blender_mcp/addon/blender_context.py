"""Blender 上下文代理 (Blender Context)。

对齐 Godot MCP ``editor/editor_context.gd``：统一隔离 ``bpy.context`` /
``bpy.data`` / ``bpy.ops`` 的访问细节，为所有指令模块提供：

  - 数据块寻址：``get_object`` / ``get_material`` / ``require_type`` ……
    查找失败统一抛出语义化 ``RpcError``，模块内无需重复判空。
  - 撤销支持：``push_undo``，由 Dispatcher 在写操作成功后自动调用。
  - 算子上下文：``ops_context()`` 为 ``bpy.ops`` 提供合法的 window / area，
    解决在 ``bpy.app.timers`` 回调中调用算子时 “context is incorrect” 的问题。
  - 序列化：``object_info`` / ``vec`` 等，将 bpy 类型转换为可 JSON 化的数据。
"""
from __future__ import annotations

import contextlib
import os
from typing import Any, Iterable, Iterator

try:
    import bpy
except ImportError:
    bpy = None  # type: ignore[assignment]

from .rpc.rpc_error import RpcError

_PRECISION = 4

# 渲染引擎别名：Blender 4.2~4.x 为 BLENDER_EEVEE_NEXT，其余版本为 BLENDER_EEVEE
_ENGINE_ALIASES: dict[str, tuple[str, ...]] = {
    "EEVEE": ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"),
    "BLENDER_EEVEE": ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"),
    "BLENDER_EEVEE_NEXT": ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"),
    "CYCLES": ("CYCLES",),
    "WORKBENCH": ("BLENDER_WORKBENCH",),
    "BLENDER_WORKBENCH": ("BLENDER_WORKBENCH",),
}

_IMAGE_FORMATS: dict[str, str] = {
    ".png": "PNG", ".jpg": "JPEG", ".jpeg": "JPEG", ".bmp": "BMP",
    ".tif": "TIFF", ".tiff": "TIFF", ".exr": "OPEN_EXR", ".hdr": "HDR",
    ".webp": "WEBP",
}


class BlenderContext:
    """所有指令模块共享的 Blender 访问代理。"""

    # ── 基础上下文 ─────────────────────────────────────────────

    @property
    def scene(self) -> bpy.types.Scene:
        return bpy.context.scene

    @property
    def view_layer(self) -> bpy.types.ViewLayer:
        return bpy.context.view_layer

    @property
    def collection(self) -> bpy.types.Collection:
        """新建对象默认链接到的集合（活动集合，回退到场景根集合）。"""
        return bpy.context.collection or self.scene.collection

    @property
    def active_object(self) -> bpy.types.Object | None:
        return self.view_layer.objects.active

    @staticmethod
    def blender_version() -> str:
        return ".".join(str(v) for v in bpy.app.version)

    # ── 数据块寻址 ─────────────────────────────────────────────

    def get_object(self, name: str) -> bpy.types.Object:
        obj = bpy.data.objects.get(name)
        if obj is None:
            raise RpcError.not_found(f"Object '{name}' not found", {"object": name})
        return obj

    def get_objects(self, names: Iterable[str]) -> list[bpy.types.Object]:
        """批量寻址；任一不存在时一次性报告全部缺失项。"""
        names = list(names)
        missing = [n for n in names if n not in bpy.data.objects]
        if missing:
            raise RpcError.not_found(f"Objects not found: {missing}", {"objects": missing})
        return [bpy.data.objects[n] for n in names]

    def require_type(self, obj: bpy.types.Object, obj_type: str) -> bpy.types.Object:
        if obj.type != obj_type:
            raise RpcError.invalid_state(
                f"Object '{obj.name}' is not a {obj_type} (type: {obj.type})",
                {"object": obj.name, "expected_type": obj_type, "actual_type": obj.type},
            )
        return obj

    def get_material(self, name: str) -> bpy.types.Material:
        mat = bpy.data.materials.get(name)
        if mat is None:
            raise RpcError.not_found(f"Material '{name}' not found", {"material": name})
        return mat

    def get_modifier(self, obj: bpy.types.Object, name: str) -> bpy.types.Modifier:
        mod = obj.modifiers.get(name)
        if mod is None:
            raise RpcError.not_found(
                f"Modifier '{name}' not found on '{obj.name}'",
                {"object": obj.name, "modifier": name, "available": [m.name for m in obj.modifiers]},
            )
        return mod

    def require_material_slots(self, obj: bpy.types.Object) -> None:
        if obj.data is None or not hasattr(obj.data, "materials"):
            raise RpcError.invalid_state(
                f"Object '{obj.name}' (type: {obj.type}) cannot hold materials",
                {"object": obj.name, "actual_type": obj.type},
            )

    # ── 对象生命周期 ───────────────────────────────────────────

    def link_object(self, obj: bpy.types.Object) -> bpy.types.Object:
        self.collection.objects.link(obj)
        return obj

    @staticmethod
    def rename(obj: bpy.types.Object, new_name: str) -> None:
        """重命名对象，并同步重命名其独占的数据块（网格 / 相机 / 灯光）。"""
        obj.name = new_name
        if obj.data is not None and getattr(obj.data, "users", 0) <= 1:
            obj.data.name = new_name

    @staticmethod
    def remove_object(obj: bpy.types.Object) -> None:
        """直接通过 ``bpy.data`` 删除，无需算子上下文与选择状态。"""
        bpy.data.objects.remove(obj, do_unlink=True)

    # ── 选择状态 ───────────────────────────────────────────────

    def deselect_all(self) -> None:
        for obj in self.view_layer.objects:
            obj.select_set(False)

    def select(self, objects: Iterable[bpy.types.Object], active: bpy.types.Object | None = None,
               replace: bool = True) -> None:
        if replace:
            self.deselect_all()
        for obj in objects:
            obj.select_set(True)
        if active is not None:
            self.view_layer.objects.active = active

    # ── 算子上下文与模式 ───────────────────────────────────────

    @staticmethod
    def find_area(area_type: str = "VIEW_3D") -> tuple[Any, Any, Any] | None:
        """在所有窗口中查找指定类型的区域，返回 ``(window, area, region)``。"""
        wm = bpy.context.window_manager
        for window in wm.windows if wm else []:
            for area in window.screen.areas:
                if area.type == area_type:
                    region = next((r for r in area.regions if r.type == "WINDOW"), None)
                    if region is not None:
                        return window, area, region
        return None

    @contextlib.contextmanager
    def ops_context(self, require_view3d: bool = False, **extra: Any) -> Iterator[None]:
        """为 ``bpy.ops`` 提供合法的 window / screen / area / region 上下文。

        Args:
            require_view3d: 为 ``True`` 时若找不到 3D 视口则抛出 ``INVALID_STATE``。
            **extra: 额外的上下文覆盖项（如 ``active_object=obj``）。
        """
        found = self.find_area("VIEW_3D")
        if found is None:
            if require_view3d:
                raise RpcError.invalid_state("No 3D viewport found (is Blender running in background mode?)")
            with bpy.context.temp_override(**extra) if extra else contextlib.nullcontext():
                yield
            return
        window, area, region = found
        with bpy.context.temp_override(window=window, screen=window.screen, area=area, region=region, **extra):
            yield

    def ensure_object_mode(self) -> None:
        """对象级算子（join / delete / modifier_apply）要求处于 OBJECT 模式。"""
        active = self.active_object
        if active is not None and active.mode != "OBJECT":
            with self.ops_context(active_object=active):
                bpy.ops.object.mode_set(mode="OBJECT")

    # ── 撤销 ───────────────────────────────────────────────────

    def push_undo(self, message: str) -> None:
        """在写操作完成后推入一条撤销记录，使其可被 Ctrl+Z 回退。"""
        with self.ops_context():
            bpy.ops.ed.undo_push(message=message)

    # ── 渲染辅助 ───────────────────────────────────────────────

    def resolve_render_engine(self, name: str) -> str:
        """将引擎名（含别名，如 ``EEVEE``）解析为当前 Blender 版本支持的标识。"""
        available = [item.identifier for item in
                     self.scene.render.bl_rna.properties["engine"].enum_items]
        key = name.upper()
        for candidate in _ENGINE_ALIASES.get(key, (key,)):
            if candidate in available:
                return candidate
        raise RpcError.invalid_params(
            f"Unknown render engine '{name}'", {"engine": name, "available": available}
        )

    @staticmethod
    def image_format_for(path: str) -> str:
        return _IMAGE_FORMATS.get(os.path.splitext(path)[1].lower(), "PNG")

    @staticmethod
    def prepare_output_path(path: str) -> str:
        """校验输出路径为绝对路径并确保父目录存在。"""
        if not path or not os.path.isabs(path):
            raise RpcError.invalid_params(f"output_path must be an absolute path, got {path!r}")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        return path

    @staticmethod
    def file_info(path: str) -> dict[str, Any]:
        exists = os.path.exists(path)
        return {
            "output_path": path,
            "exists": exists,
            "file_size_kb": round(os.path.getsize(path) / 1024, 1) if exists else 0,
        }

    # ── 序列化 ─────────────────────────────────────────────────

    @staticmethod
    def vec(values: Iterable[float], precision: int = _PRECISION) -> list[float]:
        return [round(float(v), precision) for v in values]

    def object_info(self, obj: bpy.types.Object, detailed: bool = False) -> dict[str, Any]:
        """对象摘要：名称、类型、变换；MESH 附带拓扑统计。"""
        info: dict[str, Any] = {
            "name": obj.name,
            "type": obj.type,
            "location": self.vec(obj.location),
            "rotation": self.vec(obj.rotation_euler),
            "scale": self.vec(obj.scale),
        }
        if obj.type == "MESH" and obj.data is not None:
            mesh = obj.data
            info["vertex_count"] = len(mesh.vertices)
            info["edge_count"] = len(mesh.edges)
            info["face_count"] = len(mesh.polygons)
        if detailed:
            info["visible"] = obj.visible_get()
            info["parent"] = obj.parent.name if obj.parent else None
            info["dimensions"] = self.vec(obj.dimensions)
            if obj.data is not None and hasattr(obj.data, "materials"):
                info["materials"] = [m.name for m in obj.data.materials if m is not None]
            info["modifiers"] = [m.name for m in obj.modifiers]
        return info

    @staticmethod
    def principled_bsdf(mat: bpy.types.Material) -> Any | None:
        if not mat.use_nodes or mat.node_tree is None:
            return None
        return next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)

    @staticmethod
    def rgba(color: list[float]) -> tuple[float, float, float, float]:
        return tuple(color) if len(color) == 4 else (*color[:3], 1.0)  # type: ignore[return-value]
