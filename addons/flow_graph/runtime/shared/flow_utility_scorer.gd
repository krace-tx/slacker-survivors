@tool
class_name FlowUtilityScorer
extends RefCounted

## 享元效用评分与响应曲线计算引擎（Stateless Utility AI Scorer & Response Curve Engine）。[br]
##
## [b]核心职责：[/b][br]
## 1. 提供零分配区间归一化 [method normalize_range] 与 6 种标准归一化响应曲线 [method apply_curve]（始终满足 $f(0)=0, f(1)=1$）；[br]
## 2. 支持单轴「黑板键值曲线映射 (`bb_key`)」、「宿主效用算子 (`utility_key`)」以及多考量因子乘积补偿（`considerations` / IAUS Makeup Factor）；[br]
## 3. 支持编译期预归一化规格字典 [method compile_spec]（预拘留 `StringName` 与曲线名，热路径零字符串分配），并提供紧凑规则摘要 [method summarize_spec]。

#region 曲线常量定义
const CURVE_LINEAR: String = "linear"
const CURVE_QUAD: String = "quad"
const CURVE_CUBIC: String = "cubic"
const CURVE_SQRT: String = "sqrt"
const CURVE_SMOOTHSTEP: String = "smoothstep"
const CURVE_LOGISTIC: String = "logistic"

const CURVES: PackedStringArray = [
	CURVE_LINEAR,
	CURVE_QUAD,
	CURVE_CUBIC,
	CURVE_SQRT,
	CURVE_SMOOTHSTEP,
	CURVE_LOGISTIC,
]

const _LOGISTIC_STEEPNESS: float = 10.0
# f(x) = 1 / (1 + exp(-10 * (x - 0.5))): s0 = 1 / (1 + exp(5)), s1 = 1 / (1 + exp(-5))
const _LOGISTIC_S0: float = 0.0066928509242848554
const _LOGISTIC_INV_SPAN: float = 1.0135673098126023
#endregion


#region 归一化与响应曲线纯数学函数
## 将原始传感器数值线性映射至 `[0.0, 1.0]`，并在曲线变换前按 `invert` 执行紧迫度翻转。
static func normalize_range(
	raw_val: float,
	min_val: float = 0.0,
	max_val: float = 1.0,
	invert: bool = false
) -> float:
	var t: float = 0.0
	var span: float = max_val - min_val
	if is_zero_approx(span):
		t = 1.0 if raw_val >= max_val else 0.0
	else:
		t = clampf((raw_val - min_val) / span, 0.0, 1.0)
	return (1.0 - t) if invert else t


## 对 `[0.0, 1.0]` 归一化输入施加响应曲线，输出严格限制在 `[0.0, 1.0]` 且端点精确对齐 `0` 与 `1`。
static func apply_curve(t: float, curve_name: String = CURVE_LINEAR) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	match curve_name:
		CURVE_LINEAR, "":
			return x
		CURVE_QUAD:
			return x * x
		CURVE_CUBIC:
			return x * x * x
		CURVE_SQRT:
			return sqrt(x)
		CURVE_SMOOTHSTEP:
			return x * x * (3.0 - 2.0 * x)
		CURVE_LOGISTIC:
			var sx: float = 1.0 / (1.0 + exp(-_LOGISTIC_STEEPNESS * (x - 0.5)))
			return clampf((sx - _LOGISTIC_S0) * _LOGISTIC_INV_SPAN, 0.0, 1.0)
		_:
			var norm_name: String = curve_name.strip_edges().to_lower()
			if norm_name != curve_name and norm_name in CURVES:
				return apply_curve(x, norm_name)
			return x
#endregion


#region 预编译规格与单分支/多轴效用求值
## 预编译效用规格字典（由 `BTUtilitySelector` 在构建期调用一次，预拘留 `StringName` 与小写曲线名，避免热路径每帧字符串分配）。
static func compile_spec(spec: Dictionary) -> Dictionary:
	var s: Dictionary = unwrap_spec(spec)
	var out: Dictionary = {
		"weight": maxf(0.0, float(s.get("weight", 1.0))),
		"curve": str(s.get("curve", CURVE_LINEAR)).strip_edges().to_lower(),
		"invert": bool(s.get("invert", false)),
		"min_val": float(s.get("min_val", 0.0)),
		"max_val": float(s.get("max_val", 1.0)),
		"default_val": float(s.get("default_val", 0.0)),
		"base_score": clampf(float(s.get("base_score", 0.5)), 0.0, 1.0),
		"compensate": bool(s.get("compensate", true)),
	}
	var u_str: String = str(s.get("utility_key", "")).strip_edges()
	var bb_str: String = str(s.get("bb_key", "")).strip_edges()
	out["_u_sn"] = StringName(u_str) if not u_str.is_empty() else &""
	out["_bb_sn"] = StringName(bb_str) if not bb_str.is_empty() else &""
	var raw_cons: Variant = s.get("considerations", null)
	if raw_cons is Array and not (raw_cons as Array).is_empty():
		var comp_cons: Array[Dictionary] = []
		for item: Variant in raw_cons as Array:
			if item is Dictionary:
				comp_cons.append(compile_spec(item as Dictionary))
		out["considerations"] = comp_cons
	return out


## 计算单个子分支效用得分（非负浮点数：`归一化曲线值 [0..1] * weight`）。
static func evaluate(
	spec: Dictionary,
	bb: BTBlackboard = null,
	eval_ctx: Object = null,
	utility_lookup: Callable = Callable()
) -> float:
	var s: Dictionary = unwrap_spec(spec)
	var weight: float = maxf(0.0, float(s.get("weight", 1.0)))
	if weight <= 0.0:
		return 0.0

	var raw_cons: Variant = s.get("considerations", null)
	if raw_cons is Array and not (raw_cons as Array).is_empty():
		var cons_arr: Array = raw_cons as Array
		var valid_cnt: int = 0
		var combined: float = 1.0
		var compensate: bool = bool(s.get("compensate", true))
		for item: Variant in cons_arr:
			if item is Dictionary:
				valid_cnt += 1
				var axis_score: float = _evaluate_single_axis(item as Dictionary, bb, eval_ctx, utility_lookup)
				if axis_score <= 0.0:
					return 0.0
				combined *= axis_score
		if valid_cnt > 1 and compensate and combined > 0.0 and combined < 1.0:
			var mod_factor: float = 1.0 - (1.0 / float(valid_cnt))
			var make_up: float = (1.0 - combined) * mod_factor
			combined = combined + (make_up * combined)
		return clampf(combined, 0.0, 1.0) * weight

	return _evaluate_single_axis(s, bb, eval_ctx, utility_lookup) * weight


## 提取标准效用规格字典（兼容外层包装 `{"utility": {...}}` 与扁平键值字典）。
static func unwrap_spec(spec: Dictionary) -> Dictionary:
	if spec.has("utility") and spec["utility"] is Dictionary:
		return spec["utility"] as Dictionary
	return spec


static func _evaluate_single_axis(
	s: Dictionary,
	bb: BTBlackboard,
	eval_ctx: Object,
	utility_lookup: Callable
) -> float:
	var curve_name: String = str(s.get("curve", CURVE_LINEAR))
	var invert: bool = bool(s.get("invert", false))
	var u_sn: StringName = s.get("_u_sn", &"") as StringName if s.has("_u_sn") else StringName(str(s.get("utility_key", "")).strip_edges())

	if not u_sn.is_empty():
		if not utility_lookup.is_valid():
			return 0.0
		var cb_var: Variant = utility_lookup.call(u_sn)
		if not (cb_var is Callable) or not (cb_var as Callable).is_valid():
			return 0.0
		var cb: Callable = cb_var as Callable
		var res_v: Variant = cb.call(eval_ctx) if (eval_ctx != null and cb.get_argument_count() >= 1) else cb.call()
		var raw_u: float = 0.0
		if res_v is bool:
			raw_u = 1.0 if bool(res_v) else 0.0
		elif res_v is float or res_v is int:
			raw_u = clampf(float(res_v), 0.0, 1.0)
		var norm_u: float = (1.0 - raw_u) if invert else raw_u
		return apply_curve(norm_u, curve_name)

	var bb_sn: StringName = s.get("_bb_sn", &"") as StringName if s.has("_bb_sn") else StringName(str(s.get("bb_key", "")).strip_edges())
	if not bb_sn.is_empty():
		var raw_val: float = float(s.get("default_val", 0.0))
		if bb != null and bb.has_key(bb_sn):
			var v: Variant = bb.get_var(bb_sn)
			if v is float or v is int:
				raw_val = float(v)
			elif v is bool:
				raw_val = 1.0 if bool(v) else 0.0
			elif (v is String or v is StringName) and String(v).strip_edges().is_valid_float():
				raw_val = float(String(v).strip_edges())
		var min_v: float = float(s.get("min_val", 0.0))
		var max_v: float = float(s.get("max_val", 1.0))
		var norm_t: float = normalize_range(raw_val, min_v, max_v, invert)
		return apply_curve(norm_t, curve_name)

	return clampf(float(s.get("base_score", 0.5)), 0.0, 1.0)
#endregion


#region 可读摘要格式化
## 生成紧凑无符号污染的单行效用规则摘要（供画布边标签与检视器胶囊使用）。
static func summarize_spec(spec: Dictionary) -> String:
	var s: Dictionary = unwrap_spec(spec)
	var u_key: String = str(s.get("utility_key", "")).strip_edges()
	var bb_key: String = str(s.get("bb_key", "")).strip_edges()
	var curve_s: String = str(s.get("curve", CURVE_LINEAR)).strip_edges().to_lower()
	var invert: bool = bool(s.get("invert", false))
	var weight: float = maxf(0.0, float(s.get("weight", 1.0)))

	var parts := PackedStringArray()
	if not u_key.is_empty():
		parts.append(("!%s" % u_key) if invert else u_key)
	elif not bb_key.is_empty():
		var min_v: float = float(s.get("min_val", 0.0))
		var max_v: float = float(s.get("max_val", 1.0))
		var prefix: String = "!" if invert else ""
		if is_equal_approx(min_v, 0.0) and is_equal_approx(max_v, 1.0):
			parts.append("%s%s" % [prefix, bb_key])
		else:
			parts.append("%s%s [%s..%s]" % [prefix, bb_key, _fmt_num(min_v), _fmt_num(max_v)])
	elif s.has("considerations") and s["considerations"] is Array:
		parts.append("%d axes" % (s["considerations"] as Array).size())
	else:
		var base_sc: float = clampf(float(s.get("base_score", 0.5)), 0.0, 1.0)
		parts.append("base=%.2f" % base_sc)

	if not curve_s.is_empty() and curve_s != CURVE_LINEAR:
		parts.append(curve_s)
	if not is_equal_approx(weight, 1.0):
		parts.append("x%.2f" % weight)
	return " · ".join(parts)


static func _fmt_num(v: float) -> String:
	var r: float = roundf(v)
	if is_equal_approx(v, r):
		return "%d" % int(r)
	return "%.2f" % v
#endregion
