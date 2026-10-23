"""指令模块包。

每个模块继承 ``BaseModule`` 并在 ``register_commands`` 中声明自己的领域指令。
新增模块时只需在 ``ALL_MODULES`` 中追加即可被编排器自动装配。
"""
from __future__ import annotations

from .camera_module import CameraModule
from .light_module import LightModule
from .material_module import MaterialModule
from .mesh_module import MeshModule
from .modifier_module import ModifierModule
from .object_module import ObjectModule
from .render_module import RenderModule
from .scene_module import SceneModule
from .system_module import SystemModule

ALL_MODULES = (
    SystemModule,
    SceneModule,
    ObjectModule,
    MeshModule,
    ModifierModule,
    MaterialModule,
    CameraModule,
    LightModule,
    RenderModule,
)

__all__ = ["ALL_MODULES"]
