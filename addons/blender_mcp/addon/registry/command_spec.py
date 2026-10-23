"""指令元数据与入参契约描述 (Command Specification)。

对齐 Godot MCP ``registry/command_spec.gd``：包含指令唯一标识、文档描述、
参数 Schema、处理器 Callable，并负责参数校验、默认值回填与 JSON Schema 导出。

参数规则字典字段::

    {
        "type": "string" | "int" | "float" | "number" | "bool" | "array"
              | "object" | "vec3" | "color" | "any",
        "required": bool,          # 缺省 False
        "default": Any,            # 缺省时不回填
        "description": str,
        "enum": list,              # 可选，字符串类型大小写不敏感匹配
    }

扩展类型：
    - ``vec3``  ：长度为 3 的数字数组（位置 / 欧拉角 / 缩放 / 方向）。
    - ``color`` ：长度为 3 或 4 的 0~1 数字数组（RGB / RGBA）。
"""
from __future__ import annotations

from typing import Any, Callable

from ..rpc.rpc_error import RpcError

Handler = Callable[[dict], Any]


def _is_number(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _is_num_list(v: Any, sizes: tuple[int, ...]) -> bool:
    return isinstance(v, (list, tuple)) and len(v) in sizes and all(_is_number(x) for x in v)


_TYPE_CHECKERS: dict[str, Callable[[Any], bool]] = {
    "string": lambda v: isinstance(v, str),
    "int": lambda v: (isinstance(v, int) and not isinstance(v, bool))
    or (isinstance(v, float) and v.is_integer()),
    "float": _is_number,
    "number": _is_number,
    "bool": lambda v: isinstance(v, bool),
    "array": lambda v: isinstance(v, (list, tuple)),
    "object": lambda v: isinstance(v, dict),
    "vec3": lambda v: _is_num_list(v, (3,)),
    "color": lambda v: _is_num_list(v, (3, 4)),
    "any": lambda v: True,
}

_SCHEMA_TYPES: dict[str, dict[str, Any]] = {
    "string": {"type": "string"},
    "int": {"type": "integer"},
    "float": {"type": "number"},
    "number": {"type": "number"},
    "bool": {"type": "boolean"},
    "array": {"type": "array"},
    "object": {"type": "object"},
    "vec3": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3},
    "color": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 4},
    "any": {},
}


class CommandSpec:
    """单条指令的契约描述。

    Attributes:
        name: 点分命名空间方法名，如 ``"mesh.add_primitive"``。
        description: 人类 / AI 可读的指令说明。
        parameters: 参数名 → 规则字典。
        handler: 处理函数，签名 ``handler(params: dict) -> Any``。
        undoable: 是否为写操作。为 ``True`` 时 Dispatcher 会在执行成功后
            推入一条 Blender 撤销记录 (Ctrl+Z)。只读查询应设为 ``False``。
    """

    def __init__(
        self,
        name: str,
        description: str,
        parameters: dict[str, dict[str, Any]],
        handler: Handler,
        undoable: bool = True,
    ) -> None:
        self.name = name
        self.description = description
        self.parameters = parameters
        self.handler = handler
        self.undoable = undoable

    # ── 参数校验与默认值回填 ───────────────────────────────────

    def validate(self, raw_params: dict[str, Any]) -> dict[str, Any]:
        """校验入参并回填默认值。

        Returns:
            校验后的参数字典（宽松模式：Schema 之外的字段原样保留）。

        Raises:
            RpcError: ``INVALID_PARAMS``，缺少必填参数或类型 / 枚举不匹配。
        """
        validated: dict[str, Any] = {}

        for param_name, rule in self.parameters.items():
            expected = str(rule.get("type", "any")).lower()

            if param_name in raw_params and raw_params[param_name] is not None:
                val = raw_params[param_name]
                checker = _TYPE_CHECKERS.get(expected, _TYPE_CHECKERS["any"])
                if not checker(val):
                    raise RpcError.invalid_params(
                        f"Parameter '{param_name}' expects type '{expected}', "
                        f"got '{type(val).__name__}' ({val!r})",
                        {"parameter": param_name, "expected": expected},
                    )
                if expected == "int" and isinstance(val, float):
                    val = int(val)
                val = self._check_enum(param_name, rule, val)
                validated[param_name] = val
            elif rule.get("required", False):
                raise RpcError.invalid_params(
                    f"Missing required parameter: '{param_name}'",
                    {"parameter": param_name},
                )
            elif "default" in rule:
                default = rule["default"]
                # 可变默认值拷贝一份，防止 handler 修改污染 Schema
                validated[param_name] = list(default) if isinstance(default, list) else default

        # 宽松模式：保留 Schema 之外的额外参数（兼容旧客户端 / 透传字段）
        for key, val in raw_params.items():
            if key not in validated and key not in self.parameters:
                validated[key] = val

        return validated

    @staticmethod
    def _check_enum(param_name: str, rule: dict[str, Any], val: Any) -> Any:
        choices = rule.get("enum")
        if not choices:
            return val
        if isinstance(val, str):
            for choice in choices:
                if isinstance(choice, str) and choice.lower() == val.lower():
                    return choice  # 归一化为 Schema 中声明的大小写
        elif val in choices:
            return val
        raise RpcError.invalid_params(
            f"Parameter '{param_name}' must be one of {list(choices)}, got {val!r}",
            {"parameter": param_name, "allowed": list(choices)},
        )

    # ── 自省导出 ───────────────────────────────────────────────

    def to_schema(self) -> dict[str, Any]:
        """导出为标准 JSON Schema，用于 ``rpc.discover``。"""
        properties: dict[str, Any] = {}
        required: list[str] = []

        for param_name, rule in self.parameters.items():
            prop = dict(_SCHEMA_TYPES.get(str(rule.get("type", "any")).lower(), {}))
            prop["description"] = rule.get("description", param_name)
            if "default" in rule:
                prop["default"] = rule["default"]
            if rule.get("enum"):
                prop["enum"] = list(rule["enum"])
            properties[param_name] = prop
            if rule.get("required", False):
                required.append(param_name)

        params_schema: dict[str, Any] = {"type": "object", "properties": properties}
        if required:
            params_schema["required"] = required

        return {
            "name": self.name,
            "description": self.description,
            "undoable": self.undoable,
            "parameters": params_schema,
        }
