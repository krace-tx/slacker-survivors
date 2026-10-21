"""命令请求 / 响应类型与命名空间常量。

MCP 服务器与 Blender Addon 之间的所有 TCP 通信均使用以换行符分隔的
JSON-RPC 2.0 消息。本模块中的 dataclass 负责双向序列化。
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from typing import Any


class Namespace:
    """命令命名空间常量。

    每个命名空间对应一组相关的 Blender 操作。方法名由命名空间与操作名
    组合而成，例如 ``"mesh.add_primitive"``。
    """

    SCENE: str = "scene"
    MESH: str = "mesh"
    MODIFIER: str = "modifier"
    MATERIAL: str = "material"
    ARMATURE: str = "armature"
    ANIMATION: str = "animation"
    CAMERA: str = "camera"
    RENDER: str = "render"
    EXPORT: str = "export"
    SYSTEM: str = "system"  # 用于 ping、info 等


@dataclass
class CommandRequest:
    """发送到 Blender Addon 的 JSON-RPC 2.0 请求。

    Attributes:
        method: 完整方法名（例如 ``"mesh.add_primitive"``）。
        params: 转发给处理器的任意关键字参数。
        id: 唯一关联标识符；省略时自动生成。
    """

    method: str
    params: dict = field(default_factory=dict)
    id: str = field(default_factory=lambda: str(uuid.uuid4()))

    def to_json(self) -> str:
        """序列化为 JSON-RPC 2.0 请求字符串。"""
        return json.dumps({
            "jsonrpc": "2.0",
            "id": self.id,
            "method": self.method,
            "params": self.params,
        })

    @classmethod
    def from_json(cls, data: str) -> CommandRequest:
        """从 JSON-RPC 2.0 请求字符串反序列化。"""
        obj = json.loads(data)
        return cls(
            method=obj["method"],
            params=obj.get("params", {}),
            id=obj.get("id", str(uuid.uuid4())),
        )


@dataclass
class CommandResponse:
    """从 Blender Addon 接收的 JSON-RPC 2.0 响应。

    ``result`` 和 ``error`` 应恰好设置其中之一。请使用便捷构造方法
    :meth:`success` 和 :meth:`failure` 来保证此约束。

    Attributes:
        id: 与发起请求匹配的关联标识符。
        result: 成功时处理器的返回值。
        error: 失败时的 JSON-RPC 错误对象。
    """

    id: str
    result: Any = None
    error: dict | None = None

    @property
    def is_success(self) -> bool:
        """当响应携带结果（无错误）时返回 ``True``。"""
        return self.error is None

    def to_json(self) -> str:
        """序列化为 JSON-RPC 2.0 响应字符串。"""
        resp: dict[str, Any] = {"jsonrpc": "2.0", "id": self.id}
        if self.error:
            resp["error"] = self.error
        else:
            resp["result"] = self.result
        return json.dumps(resp)

    @classmethod
    def from_json(cls, data: str) -> CommandResponse:
        """从 JSON-RPC 2.0 响应字符串反序列化。"""
        obj = json.loads(data)
        return cls(
            id=obj["id"],
            result=obj.get("result"),
            error=obj.get("error"),
        )

    @classmethod
    def success(cls, id: str, result: Any) -> CommandResponse:
        """创建一个携带 *result* 的成功响应。"""
        return cls(id=id, result=result)

    @classmethod
    def failure(
        cls,
        id: str,
        code: int,
        message: str,
        data: dict | None = None,
    ) -> CommandResponse:
        """创建一个包含给定 *code* 和 *message* 的错误响应。"""
        error: dict[str, Any] = {"code": code, "message": message}
        if data:
            error["data"] = data
        return cls(id=id, error=error)
