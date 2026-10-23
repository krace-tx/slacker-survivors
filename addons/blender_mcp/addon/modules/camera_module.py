"""相机模块 (Camera Module)：相机创建、朝向、设为活动相机。"""
from __future__ import annotations

try:
    import bpy
    import mathutils
except ImportError:
    bpy = None  # type: ignore[assignment]
    mathutils = None  # type: ignore[assignment]

from .base_module import BaseModule, CommandRegistry, RpcError


class CameraModule(BaseModule):

    def register_commands(self, registry: CommandRegistry) -> None:
        registry.register_command(
            "camera.create",
            "Create a camera object.",
            {
                "name": {"type": "string", "default": "Camera", "description": "Camera name"},
                "location": {"type": "vec3", "default": [0.0, 0.0, 0.0], "description": "[x, y, z] position"},
                "rotation": {"type": "vec3", "default": [0.0, 0.0, 0.0], "description": "[rx, ry, rz] radians"},
                "lens": {"type": "float", "default": 50.0, "description": "Focal length in mm (PERSP)"},
                "type": {"type": "string", "default": "PERSP", "enum": ["PERSP", "ORTHO", "PANO"],
                         "description": "Projection type"},
                "ortho_scale": {"type": "float", "description": "Orthographic scale (ORTHO)"},
                "look_at": {"type": "vec3", "description": "Optional [x, y, z] target to aim at"},
                "set_active": {"type": "bool", "default": False, "description": "Make it the scene camera"},
            },
            self._create,
        )

        registry.register_command(
            "camera.look_at",
            "Rotate a camera (or any object) so its -Z axis points at a target position.",
            {
                "camera_name": {"type": "string", "required": True, "description": "Camera object name"},
                "target": {"type": "vec3", "required": True, "description": "[x, y, z] target position"},
            },
            self._look_at,
        )

        registry.register_command(
            "camera.set_active",
            "Set the scene's active (render) camera.",
            {"camera_name": {"type": "string", "required": True, "description": "Camera object name"}},
            self._set_active,
        )

    # ── handlers ───────────────────────────────────────────────

    def _create(self, p: dict) -> dict:
        cam_data = bpy.data.cameras.new(name=p["name"])
        cam_data.type = p["type"]
        cam_data.lens = p["lens"]
        if "ortho_scale" in p:
            cam_data.ortho_scale = p["ortho_scale"]

        cam = self.ctx.link_object(bpy.data.objects.new(name=p["name"], object_data=cam_data))
        cam.location = p["location"]
        cam.rotation_euler = p["rotation"]
        if "look_at" in p:
            self._aim(cam, p["look_at"])
        if p["set_active"]:
            self.ctx.scene.camera = cam
        return self._info(cam)

    def _look_at(self, p: dict) -> dict:
        cam = self.ctx.get_object(p["camera_name"])
        self._aim(cam, p["target"])
        return {"camera": cam.name, "target": p["target"], "rotation": self.ctx.vec(cam.rotation_euler)}

    def _set_active(self, p: dict) -> dict:
        cam = self.ctx.require_type(self.ctx.get_object(p["camera_name"]), "CAMERA")
        self.ctx.scene.camera = cam
        return {"active_camera": cam.name}

    # ── 内部 ───────────────────────────────────────────────────

    def _aim(self, obj: bpy.types.Object, target: list[float]) -> None:
        # 刚设置的 location 需刷新依赖图后才会反映到 matrix_world（父子层级下必须用世界坐标）
        self.ctx.view_layer.update()
        direction = mathutils.Vector(target) - obj.matrix_world.translation
        if direction.length < 1e-6:
            raise RpcError.invalid_params("Target coincides with the camera position")
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    def _info(self, cam: bpy.types.Object) -> dict:
        return {
            "name": cam.name,
            "type": cam.data.type,
            "lens": cam.data.lens,
            "location": self.ctx.vec(cam.location),
            "rotation": self.ctx.vec(cam.rotation_euler),
            "is_active": self.ctx.scene.camera == cam,
        }
