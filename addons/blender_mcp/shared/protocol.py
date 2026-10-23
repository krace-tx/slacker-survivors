"""双端共享的通信协议定义 (Wire Protocol)。

MCP Server 进程与 Blender Addon 之间使用 **换行符分隔的 JSON-RPC 2.0**
(Newline-Delimited JSON) 通信。本模块是协议的唯一事实来源：

- ``ErrorCode``：错误码枚举（与 Godot MCP ``rpc_error.gd`` 对齐）。
- ``encode_message`` / ``decode_message``：报文帧编解码。
- ``make_request`` / ``make_result`` / ``make_error``：标准报文构造。

注意：本模块会同时被 Blender 内置 Python (3.10+) 与外部 MCP 进程导入，
因此只能依赖标准库。
"""
from __future__ import annotations

import json
from enum import IntEnum
from typing import Any

JSONRPC_VERSION: str = "2.0"
FRAME_DELIMITER: bytes = b"\n"
ENCODING: str = "utf-8"

# 内置保留方法名
METHOD_DISCOVER: str = "rpc.discover"
METHOD_PING: str = "system.ping"


class ErrorCode(IntEnum):
    """JSON-RPC 2.0 错误码。

    -32700 ~ -32600 为规范保留码；-32001 起为业务自定义码。
    """

    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

    NOT_FOUND = -32001          # 对象 / 材质 / 修改器等目标不存在
    EXECUTION_ERROR = -32002    # bpy 执行失败
    INVALID_STATE = -32003      # 目标类型或编辑器状态不满足要求（如非 MESH、无 3D 视口）


# ── 报文帧编解码 ───────────────────────────────────────────────


def encode_message(payload: dict[str, Any]) -> bytes:
    """将报文字典编码为单行 NDJSON 字节串（自带结尾换行符）。"""
    return json.dumps(payload, ensure_ascii=False, default=_json_fallback).encode(ENCODING) + FRAME_DELIMITER


def decode_message(line: bytes | str) -> Any:
    """解码单行 NDJSON 报文。解析失败时抛出 ``ValueError``。"""
    if isinstance(line, bytes):
        line = line.decode(ENCODING)
    return json.loads(line)


def _json_fallback(value: Any) -> Any:
    """兜底序列化：mathutils.Vector / Color / Euler 等可迭代对象转 list。"""
    try:
        return [round(v, 6) if isinstance(v, float) else v for v in value]
    except TypeError:
        return str(value)


# ── 报文构造 ───────────────────────────────────────────────────


def make_request(request_id: Any, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    """构造 JSON-RPC 请求报文。"""
    return {"jsonrpc": JSONRPC_VERSION, "id": request_id, "method": method, "params": params or {}}


def make_result(request_id: Any, result: Any) -> dict[str, Any]:
    """构造 JSON-RPC 成功响应报文。"""
    return {"jsonrpc": JSONRPC_VERSION, "id": request_id, "result": {} if result is None else result}


def make_error(request_id: Any, code: int, message: str, data: Any = None) -> dict[str, Any]:
    """构造 JSON-RPC 错误响应报文。"""
    error: dict[str, Any] = {"code": int(code), "message": message}
    if data is not None:
        error["data"] = data
    return {"jsonrpc": JSONRPC_VERSION, "id": request_id, "error": error}
