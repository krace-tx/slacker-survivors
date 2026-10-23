"""标准 JSON-RPC 2.0 错误封装模型 (RPC Error)。

对齐 Godot MCP ``rpc/rpc_error.gd``：通过语义化工厂方法构造错误，
由 Dispatcher 统一序列化为 JSON-RPC 2.0 或 Legacy 错误响应。

Python 中既支持以异常形式抛出（``raise RpcError.not_found(...)``），
也兼容 Godot 风格直接 ``return RpcError.not_found(...)``。
"""
from __future__ import annotations

from typing import Any

from ...shared.protocol import ErrorCode, make_error


class RpcError(Exception):
    """可序列化为 JSON-RPC 2.0 / Legacy 错误对象的结构化异常。"""

    Code = ErrorCode

    def __init__(self, code: int, message: str, data: Any = None) -> None:
        super().__init__(message)
        self.code = int(code)
        self.message = message
        self.data = data

    # ── 语义化工厂方法 ─────────────────────────────────────────

    @classmethod
    def parse_error(cls, detail: str = "Parse error") -> RpcError:
        return cls(ErrorCode.PARSE_ERROR, detail)

    @classmethod
    def invalid_request(cls, detail: str = "Invalid Request") -> RpcError:
        return cls(ErrorCode.INVALID_REQUEST, detail)

    @classmethod
    def method_not_found(cls, method_name: str) -> RpcError:
        return cls(ErrorCode.METHOD_NOT_FOUND, f"Method not found: {method_name}")

    @classmethod
    def invalid_params(cls, detail: str, data: Any = None) -> RpcError:
        return cls(ErrorCode.INVALID_PARAMS, detail, data)

    @classmethod
    def internal_error(cls, detail: str, data: Any = None) -> RpcError:
        return cls(ErrorCode.INTERNAL_ERROR, detail, data)

    @classmethod
    def not_found(cls, detail: str, data: Any = None) -> RpcError:
        return cls(ErrorCode.NOT_FOUND, detail, data)

    @classmethod
    def execution_error(cls, detail: str, data: Any = None) -> RpcError:
        return cls(ErrorCode.EXECUTION_ERROR, detail, data)

    @classmethod
    def invalid_state(cls, detail: str, data: Any = None) -> RpcError:
        return cls(ErrorCode.INVALID_STATE, detail, data)

    # ── 序列化 ─────────────────────────────────────────────────

    def to_dict(self) -> dict[str, Any]:
        out: dict[str, Any] = {"code": self.code, "message": self.message}
        if self.data is not None:
            out["data"] = self.data
        return out

    def to_json_rpc(self, request_id: Any) -> dict[str, Any]:
        return make_error(request_id, self.code, self.message, self.data)

    def to_legacy(self, command_id: str = "") -> dict[str, Any]:
        out: dict[str, Any] = {
            "status": "error",
            "code": self.code,
            "message": self.message,
        }
        if self.data is not None:
            out["data"] = self.data
        if command_id:
            out["commandId"] = command_id
        return out

    def __repr__(self) -> str:
        return f"RpcError(code={self.code}, message={self.message!r})"
