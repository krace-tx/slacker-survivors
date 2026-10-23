"""统一分发路由器 (RPC Dispatcher)。

对齐 Godot MCP ``rpc/rpc_dispatcher.gd``：
  - 解析输入报文，双模支持标准 JSON-RPC 2.0 及 Legacy 命令格式
    （``{"type": ..., "params": ..., "commandId": ...}``）。
  - 内置 ``rpc.discover`` 自省能力。
  - 参数自动校验与默认值回填、异常捕获、写操作自动推入 Undo 栈。
  - 与传输层解耦：``dispatch()`` 接收原始文本并返回响应字典（notification 返回 ``None``）。
"""
from __future__ import annotations

import traceback
from typing import Any, Callable

from ...shared.protocol import METHOD_DISCOVER, decode_message, make_result
from ..registry.command_registry import CommandRegistry
from .rpc_error import RpcError

UndoPusher = Callable[[str], None]


class RPCDispatcher:
    """JSON-RPC 2.0 / Legacy 双模分发器。

    Args:
        registry: 指令注册表。
        undo_pusher: 可选回调。``undoable`` 指令执行成功后以
            ``"MCP: <method>"`` 为名推入撤销记录。
    """

    def __init__(self, registry: CommandRegistry, undo_pusher: UndoPusher | None = None) -> None:
        self._registry = registry
        self._undo_pusher = undo_pusher

    def dispatch(self, text: str) -> dict[str, Any] | None:
        """处理一条原始报文，返回响应字典；notification 返回 ``None``。"""
        try:
            data = decode_message(text)
        except ValueError as exc:
            return RpcError.parse_error(f"Failed to parse JSON: {exc}").to_json_rpc(None)

        if not isinstance(data, dict):
            return RpcError.invalid_request("Payload must be a JSON object").to_json_rpc(None)

        # 1. 协议检测：标准 JSON-RPC 2.0
        if "method" in data:
            return self._handle_json_rpc(data)
        # 2. 协议检测：Legacy 指令格式 {"type": ..., "params": ..., "commandId": ...}
        if "type" in data:
            return self._handle_legacy(data)

        if "id" not in data:
            return None
        return RpcError.invalid_request("Missing 'method' or 'type' field").to_json_rpc(data.get("id"))

    # ── 协议分支 ───────────────────────────────────────────────

    def _handle_json_rpc(self, req: dict[str, Any]) -> dict[str, Any] | None:
        req_id = req.get("id")
        is_notification = "id" not in req
        method_name = req.get("method")

        if not isinstance(method_name, str) or not method_name:
            return None if is_notification else RpcError.invalid_request("Invalid 'method' field").to_json_rpc(req_id)

        try:
            result = self._execute(method_name, req.get("params", {}))
        except RpcError as err:
            return None if is_notification else err.to_json_rpc(req_id)

        return None if is_notification else make_result(req_id, result)

    def _handle_legacy(self, req: dict[str, Any]) -> dict[str, Any]:
        cmd_type = req.get("type", "")
        cmd_id = str(req.get("commandId", ""))

        if not isinstance(cmd_type, str) or not cmd_type:
            return RpcError.invalid_request("Invalid 'type' field").to_legacy(cmd_id)

        if cmd_type in ("discover", METHOD_DISCOVER):
            resp: dict[str, Any] = {
                "status": "success",
                "result": {"commands": self._registry.discover()},
            }
            if cmd_id:
                resp["commandId"] = cmd_id
            return resp

        try:
            result = self._execute(cmd_type, req.get("params", {}))
        except RpcError as err:
            return err.to_legacy(cmd_id)

        response: dict[str, Any] = {
            "status": "success",
            "result": result if result is not None else {},
        }
        if cmd_id:
            response["commandId"] = cmd_id
        return response

    # ── 内部执行流 ─────────────────────────────────────────────

    def _execute(self, method: str, raw_params: Any) -> Any:
        # 内置自省
        if method == METHOD_DISCOVER:
            return {"commands": self._registry.discover()}

        spec = self._registry.find(method)
        if spec is None:
            raise RpcError.method_not_found(method)

        if raw_params is None:
            raw_params = {}
        if not isinstance(raw_params, dict):
            raise RpcError.invalid_params("'params' must be a JSON object (by-name parameters)")

        params = spec.validate(raw_params)

        try:
            result = spec.handler(params)
        except RpcError:
            raise
        except Exception as exc:  # noqa: BLE001 — 任何 bpy 异常都需要回包而非击穿定时器
            traceback.print_exc()
            raise RpcError.execution_error(
                f"{spec.name} failed: {exc}",
                {"exception": type(exc).__name__},
            ) from exc

        # 兼容 Godot 风格：handler 也可以直接 return RpcError
        if isinstance(result, RpcError):
            raise result

        if spec.undoable and self._undo_pusher is not None:
            try:
                self._undo_pusher(f"MCP: {spec.name}")
            except Exception as exc:  # noqa: BLE001 — 撤销记录失败不应影响已成功的指令
                print(f"[MCP Dispatcher] undo_push failed for {spec.name}: {exc}")

        return result
