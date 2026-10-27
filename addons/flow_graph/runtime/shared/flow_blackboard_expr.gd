@tool
class_name FlowBlackboardExpr
extends RefCounted

## 共享轻量布尔表达式编译求值器与黑板 Schema 类型转换器（Shared Blackboard Expression & Schema Engine）。[br]
##
## [b]核心职责：[/b][br]
## 1. 为 `StateMachine` 与 `BTTree` 提供统一的 `blackboard_schema` 默认值注入与运行期热改安全转型；[br]
## 2. 支持 `||`、`&&`、括号分组、`!` 前缀取反及 `<= / >= / != / == / < / >` 比较求值；[br]
## 3. 内置纯值类型（`Array` 元组）有界静态表达式 AST 缓存：首帧解析一次，后续同屏百怪每帧零字符串切片、零 `ObjectDB` 实例分配且退出时零 `RefCounted` 静态驻留泄漏；[br]
## 4. 未注册且不在黑板中的未知条件键，无论是否带 `!` 前缀，一律安全返回 `false`，杜绝草稿条件误触发转换。

#region Constants & Pure Value-Type AST Cache
const _CMP_OPS: Array[String] = ["<=", ">=", "!=", "==", "<", ">"]
const _MAX_EXPR_CACHE: int = 512

# 纯值类型 AST 元组节点编码（零 Object/RefCounted 实例，杜绝 Godot 退出期静态字典持有 Script 资源告警）：
# - [0, const_bool]
# - [1, ident_sn, negated_bool]
# - [2, child_tuple]
# - [3, children_tuples_array]  (OR)
# - [4, children_tuples_array]  (AND)
# - [5, cmp_op_str, lhs_kind, lhs_val_or_sn, lhs_raw, lhs_neg, rhs_kind, rhs_val_or_sn, rhs_raw, rhs_neg]
const _NK_CONST: int = 0
const _NK_IDENT: int = 1
const _NK_NOT: int = 2
const _NK_OR: int = 3
const _NK_AND: int = 4
const _NK_CMP: int = 5

const _OK_LITERAL: int = 0
const _OK_BB_OR_NULL: int = 1
const _OK_BB_OR_STR: int = 2

static var _expr_cache: Dictionary = {} ## {String: Array}
#endregion


#region Schema Defaults & Safe Type Coercion
## 清空表达式编译缓存。
static func clear_cache() -> void:
	_expr_cache.clear()


## 按 Schema 定义（`{"key": String, "type": String, "default": Variant}`）向黑板注入缺失键的默认值。
static func apply_schema_defaults(schema: Array, bb: BTBlackboard) -> void:
	if bb == null or schema.is_empty():
		return
	for item: Variant in schema:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item as Dictionary
		var key_str: String = str(entry.get("key", "")).strip_edges()
		if key_str.is_empty():
			continue
		var key_sn: StringName = StringName(key_str)
		if not bb.has_key(key_sn):
			var type_hint: String = str(entry.get("type", ""))
			var raw_default: Variant = entry.get("default", null)
			bb.set_var(key_sn, coerce_value(raw_default, type_hint))


## 将字符串或原始值安全转换为目标类型（供实时黑板热改、Schema 默认值与字面量解析共用）。
static func coerce_value(raw: Variant, type_hint: String = "") -> Variant:
	var hint: String = type_hint.strip_edges().to_lower()
	match hint:
		"bool":
			if raw is bool:
				return bool(raw)
			if raw is int or raw is float:
				return float(raw) != 0.0
			var sb: String = str(raw).strip_edges().to_lower()
			return sb in ["true", "1", "yes", "on"]
		"int":
			if raw is int:
				return int(raw)
			if raw is float:
				return int(float(raw))
			if raw is bool:
				return 1 if bool(raw) else 0
			var si: String = str(raw).strip_edges()
			if si.is_valid_int():
				return int(si)
			if si.is_valid_float():
				return int(float(si))
			return 0
		"float":
			if raw is float or raw is int:
				return float(raw)
			if raw is bool:
				return 1.0 if bool(raw) else 0.0
			var sf: String = str(raw).strip_edges()
			return float(sf) if sf.is_valid_float() else 0.0
		"string", "str":
			return "" if raw == null else str(raw)
		_:
			return _infer_literal(raw)
#endregion


#region Boolean Expression Evaluation
## 求值布尔条件表达式（支持 `||`、`&&`、括号、`<= >= != == < >` 比较与 `!cond` 取反）。
static func eval_expr(
	expr: String,
	cond_lookup: Callable = Callable(),
	bb: BTBlackboard = null,
	fsm_ctx: Object = null
) -> bool:
	if expr.is_empty():
		return false
	var ast: Variant = _expr_cache.get(expr, null)
	if ast == null:
		if _expr_cache.size() >= _MAX_EXPR_CACHE:
			_expr_cache.clear()
		var compiled: Array = _compile_expr(expr)
		_expr_cache[expr] = compiled
		return _eval_compiled(compiled, cond_lookup, bb, fsm_ctx)
	return _eval_compiled(ast as Array, cond_lookup, bb, fsm_ctx)


## 兼容别名：等价于 [method eval_expr]。
static func eval_condition_expr(
	expr: String,
	cond_lookup: Callable = Callable(),
	bb: BTBlackboard = null,
	fsm_ctx: Object = null
) -> bool:
	return eval_expr(expr, cond_lookup, bb, fsm_ctx)
#endregion


#region Pure Value-Type AST Compilation & Fast Evaluation
static func _compile_expr(raw_expr: String) -> Array:
	var trimmed: String = _strip_outer_parens(raw_expr.strip_edges())
	if trimmed.is_empty():
		return [_NK_CONST, false]

	var or_parts: PackedStringArray = _split_top_level(trimmed, "||")
	if or_parts.size() > 1:
		var or_children: Array = []
		for part: String in or_parts:
			or_children.append(_compile_expr(part))
		return [_NK_OR, or_children]

	var and_parts: PackedStringArray = _split_top_level(trimmed, "&&")
	if and_parts.size() > 1:
		var and_children: Array = []
		for part: String in and_parts:
			and_children.append(_compile_expr(part))
		return [_NK_AND, and_children]

	return _compile_atomic(trimmed)


static func _compile_atomic(clause: String) -> Array:
	var text: String = _strip_outer_parens(clause.strip_edges())
	if text.is_empty():
		return [_NK_CONST, false]

	for op: String in _CMP_OPS:
		var op_pos: int = _find_top_level_op(text, op)
		if op_pos > 0:
			var lhs_str: String = text.substr(0, op_pos).strip_edges()
			var rhs_str: String = text.substr(op_pos + op.length()).strip_edges()
			var lhs_op: Array = _compile_operand(lhs_str, true)
			var rhs_op: Array = _compile_operand(rhs_str, false)
			return [
				_NK_CMP, op,
				lhs_op[0], lhs_op[1], lhs_op[2], lhs_op[3],
				rhs_op[0], rhs_op[1], rhs_op[2], rhs_op[3],
			]

	var negated: bool = false
	while text.begins_with("!"):
		negated = not negated
		text = text.substr(1).strip_edges()

	if text.is_empty():
		return [_NK_CONST, false]

	if text.begins_with("(") and text.ends_with(")"):
		var inner: String = _strip_outer_parens(text)
		if inner != text:
			var inner_node: Array = _compile_expr(inner)
			if not negated:
				return inner_node
			var ik: int = int(inner_node[0])
			if ik == _NK_CONST:
				return [_NK_CONST, not bool(inner_node[1])]
			if ik == _NK_IDENT:
				return [_NK_IDENT, inner_node[1] as StringName, not bool(inner_node[2])]
			if ik == _NK_NOT:
				return inner_node[1] as Array
			return [_NK_NOT, inner_node]

	var lower: String = text.to_lower()
	if lower == "true":
		return [_NK_CONST, not negated]
	if lower == "false":
		return [_NK_CONST, negated]

	return [_NK_IDENT, StringName(text), negated]


static func _compile_operand(token: String, is_lhs: bool) -> Array:
	var cur: String = token.strip_edges()
	var neg: bool = false
	while cur.begins_with("!"):
		neg = not neg
		cur = cur.substr(1).strip_edges()

	if _is_quoted(cur) or cur.is_valid_int() or cur.is_valid_float() or cur.to_lower() in ["true", "false", "null"]:
		var lit: Variant = _infer_literal(cur)
		if neg and lit is bool:
			lit = not bool(lit)
		return [_OK_LITERAL, lit, "", neg]

	var kind: int = _OK_BB_OR_NULL if is_lhs else _OK_BB_OR_STR
	return [kind, StringName(cur), token.strip_edges(), neg]


static func _eval_compiled(
	node: Array,
	cond_lookup: Callable,
	bb: BTBlackboard,
	fsm_ctx: Object
) -> bool:
	var nk: int = int(node[0])
	match nk:
		_NK_CONST:
			return bool(node[1])
		_NK_OR:
			var or_arr: Array = node[1] as Array
			for ch_v: Variant in or_arr:
				if _eval_compiled(ch_v as Array, cond_lookup, bb, fsm_ctx):
					return true
			return false
		_NK_AND:
			var and_arr: Array = node[1] as Array
			for ch_v: Variant in and_arr:
				if not _eval_compiled(ch_v as Array, cond_lookup, bb, fsm_ctx):
					return false
			return true
		_NK_NOT:
			return not _eval_compiled(node[1] as Array, cond_lookup, bb, fsm_ctx)
		_NK_CMP:
			var lv: Variant = _resolve_operand(int(node[2]), node[3], str(node[4]), bool(node[5]), bb)
			var rv: Variant = _resolve_operand(int(node[6]), node[7], str(node[8]), bool(node[9]), bb)
			return compare_values(lv, str(node[1]), rv)
		_NK_IDENT:
			var ident_sn: StringName = node[1] as StringName
			var neg: bool = bool(node[2])
			if cond_lookup.is_valid():
				var looked_up: Variant = cond_lookup.call(ident_sn)
				if looked_up is Callable:
					var cb: Callable = looked_up as Callable
					if cb.is_valid():
						var cb_res: bool = bool(cb.call(fsm_ctx)) if (fsm_ctx != null and cb.get_argument_count() >= 1) else bool(cb.call())
						return (not cb_res) if neg else cb_res
			if bb != null and bb.has_key(ident_sn):
				var bb_res: bool = bool(bb.get_var(ident_sn, false))
				return (not bb_res) if neg else bb_res
			# 关键安全规则：既不在 cond_lookup 也不在 bb 中的未知条件键，无论是否带 `!` 一律返回 false
			return false
	return false


static func _resolve_operand(
	kind: int,
	val_or_sn: Variant,
	raw_token: String,
	negated: bool,
	bb: BTBlackboard
) -> Variant:
	if kind == _OK_LITERAL:
		return val_or_sn
	var key_sn: StringName = val_or_sn as StringName
	if bb != null and bb.has_key(key_sn):
		var val: Variant = bb.get_var(key_sn, null)
		if negated:
			return not bool(val)
		return val
	if kind == _OK_BB_OR_NULL:
		return null
	return null if negated else raw_token
#endregion


#region Comparison & Lexing Helpers
## 通用安全值比较（兼容 int/float 跨数值比较、String/StringName 相等比较，对不可比类型安全返回 `false`）。
static func compare_values(lhs: Variant, op: String, rhs: Variant) -> bool:
	if lhs == null or rhs == null:
		if op == "==":
			return lhs == null and rhs == null
		if op == "!=":
			return not (lhs == null and rhs == null)
		return false

	if (lhs is int or lhs is float) and (rhs is int or rhs is float):
		var lf: float = float(lhs)
		var rf: float = float(rhs)
		match op:
			"==": return is_equal_approx(lf, rf)
			"!=": return not is_equal_approx(lf, rf)
			"<":  return lf < rf
			"<=": return lf <= rf
			">":  return lf > rf
			">=": return lf >= rf
			_:    return false

	if (lhs is String or lhs is StringName) and (rhs is String or rhs is StringName):
		var ls: String = String(lhs)
		var rs: String = String(rhs)
		match op:
			"==": return ls == rs
			"!=": return ls != rs
			"<":  return ls < rs
			"<=": return ls <= rs
			">":  return ls > rs
			">=": return ls >= rs
			_:    return false

	match op:
		"==":
			return typeof(lhs) == typeof(rhs) and lhs == rhs
		"!=":
			return typeof(lhs) != typeof(rhs) or lhs != rhs
		"<", "<=", ">", ">=":
			if not _is_numeric_like(lhs) or not _is_numeric_like(rhs):
				return false
			var lnum: float = _to_numeric(lhs)
			var rnum: float = _to_numeric(rhs)
			match op:
				"<":  return lnum < rnum
				"<=": return lnum <= rnum
				">":  return lnum > rnum
				">=": return lnum >= rnum
	return false


static func _is_numeric_like(v: Variant) -> bool:
	if v is int or v is float or v is bool:
		return true
	if v is String or v is StringName:
		return String(v).strip_edges().is_valid_float()
	return false


static func _to_numeric(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if bool(v) else 0.0
	return float(String(v).strip_edges())


static func _infer_literal(raw: Variant) -> Variant:
	if raw == null or raw is bool or raw is int or raw is float:
		return raw
	if raw is String or raw is StringName:
		var st: String = str(raw).strip_edges()
		if _is_quoted(st):
			return st.substr(1, st.length() - 2)
		var sl: String = st.to_lower()
		if sl == "true":
			return true
		if sl == "false":
			return false
		if sl == "null":
			return null
		if st.is_valid_int():
			return int(st)
		if st.is_valid_float():
			return float(st)
		return st
	return raw


static func _is_quoted(s: String) -> bool:
	if s.length() < 2:
		return false
	return (s.begins_with("\"") and s.ends_with("\"")) or (s.begins_with("'") and s.ends_with("'"))


static func _strip_outer_parens(s: String) -> String:
	var cur: String = s.strip_edges()
	while cur.length() >= 2 and cur.begins_with("(") and cur.ends_with(")"):
		var depth: int = 0
		var quote_ch: String = ""
		var escaped: bool = false
		var wraps_all: bool = true
		for i: int in range(cur.length()):
			var ch: String = cur[i]
			if not quote_ch.is_empty():
				if escaped:
					escaped = false
				elif ch == "\\":
					escaped = true
				elif ch == quote_ch:
					quote_ch = ""
				continue
			if ch == "\"" or ch == "'":
				quote_ch = ch
			elif ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
				if depth == 0 and i < cur.length() - 1:
					wraps_all = false
					break
		if not wraps_all or depth != 0:
			break
		cur = cur.substr(1, cur.length() - 2).strip_edges()
	return cur


static func _split_top_level(s: String, sep: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var depth: int = 0
	var quote_ch: String = ""
	var escaped: bool = false
	var start: int = 0
	var sep_len: int = sep.length()
	var i: int = 0
	while i < s.length():
		var ch: String = s[i]
		if not quote_ch.is_empty():
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote_ch:
				quote_ch = ""
			i += 1
			continue
		if ch == "\"" or ch == "'":
			quote_ch = ch
		elif ch == "(":
			depth += 1
		elif ch == ")":
			depth = maxi(0, depth - 1)
		elif depth == 0 and i + sep_len <= s.length() and s.substr(i, sep_len) == sep:
			out.append(s.substr(start, i - start).strip_edges())
			i += sep_len
			start = i
			continue
		i += 1
	out.append(s.substr(start).strip_edges())
	return out


static func _find_top_level_op(s: String, op: String) -> int:
	var depth: int = 0
	var quote_ch: String = ""
	var escaped: bool = false
	var op_len: int = op.length()
	for i: int in range(s.length() - op_len + 1):
		var ch: String = s[i]
		if not quote_ch.is_empty():
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote_ch:
				quote_ch = ""
			continue
		if ch == "\"" or ch == "'":
			quote_ch = ch
		elif ch == "(":
			depth += 1
		elif ch == ")":
			depth = maxi(0, depth - 1)
		elif depth == 0 and s.substr(i, op_len) == op:
			# 防止单字符 `<` / `>` 误匹配 `<=` / `>=`
			if op_len == 1 and i + 1 < s.length() and s[i + 1] == "=":
				continue
			return i
	return -1
#endregion
