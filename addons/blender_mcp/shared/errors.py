"""Blender MCP 项目的错误码与异常类型。"""

from enum import IntEnum


class ErrorCode(IntEnum):
    """Blender MCP 操作的 JSON-RPC 风格错误码。

    使用 JSON-RPC 2.0 规范中为实现自定义服务器错误保留的
    -32000 至 -32099 范围。
    """

    OBJECT_NOT_FOUND = -32001
    NAME_CONFLICT = -32002
    INVALID_MODE = -32003
    EXPORT_FAILED = -32004
    CONNECTION_LOST = -32005
    INVALID_PARAMS = -32006
    HANDLER_NOT_FOUND = -32007
    BPY_ERROR = -32008


class BlenderMCPError(Exception):
    """可序列化为 JSON-RPC 错误对象的结构化异常。

    Attributes:
        code: 表示故障类别的 ``ErrorCode`` 枚举值。
        message: 人类可读的错误描述信息。
        data: 可选的附加上下文字典（例如未找到的对象名称）。
    """

    def __init__(self, code: ErrorCode, message: str, data: dict | None = None) -> None:
        self.code = code
        self.message = message
        self.data = data or {}
        super().__init__(message)

    def to_dict(self) -> dict:
        """返回兼容 JSON-RPC 2.0 的错误对象。"""
        result: dict = {"code": int(self.code), "message": self.message}
        if self.data:
            result["data"] = self.data
        return result
