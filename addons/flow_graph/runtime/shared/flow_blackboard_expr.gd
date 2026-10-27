@tool
class_name FlowBlackboardExpr
extends RefCounted

## 共享轻量布尔表达式求值器与黑板 Schema 类型转换器（Shared Blackboard Expression & Schema Engine）。[br]
##
## [b]核心职责：[/b][br]
## 1. 为 `StateMachine` 与 `BTTree` 提供统一的 `blackboard_schema` 默认值注入与运行期热改安全转型；[br]
## 2. 支持 `||`、`&&`、括号分组、`!` 前缀取反及 `<= / >= / != / == / < / >` 比较求值；[br]
## 3. 未注册且不在黑板中的未知条件键，无论是否带 `!` 前缀，一律安全返回 `false`，杜绝草稿条件误触发转换。

#region Constants
const _CMP_OPS: Array[String] = ["<=", ">=", "!=", "==", "<", ">"]
#endregion


#region Schema Defaults & Safe Type Coercion
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
	var trimmed: String = _strip_outer_parens(expr.strip_edges())
	if trimmed.is_empty():
		return false

	var or_parts: PackedStringArray = _split_top_level(trimmed, "||")
	if or_parts.size() > 1:
		for part: String in or_parts:
			if eval_expr(part, cond_lookup, bb, fsm_ctx):
				return true
		return false

	var and_parts: PackedStringArray = _split_top_level(trimmed, "&&")
	if and_parts.size() > 1:
		for part: String in and_parts:
			if not eval_expr(part, cond_lookup, bb, fsm_ctx):
				return false
		return true

	return _eval_atomic(trimmed, cond_lookup, bb, fsm_ctx)


## 兼容别名：等价于 [method eval_expr]。
static func eval_condition_expr(
	expr: String,
	cond_lookup: Callable = Callable(),
	bb: BTBlackboard = null,
	fsm_ctx: Object = null
) -> bool:
	return eval_expr(expr, cond_lookup, bb, fsm_ctx)
#endregion


#region Internal Lexing & Comparison Helpers
static func _eval_atomic(
	clause: String,
	cond_lookup: Callable,
	bb: BTBlackboard,
	fsm_ctx: Object
) -> bool:
	var text: String = _strip_outer_parens(clause.strip_edges())
	if text.is_empty():
		return false

	# 检查比较运算符（引号与括号外）
	for op: String in _CMP_OPS:
		var op_pos: int = _find_top_level_op(text, op)
		if op_pos > 0:
			var lhs_str: String = text.substr(0, op_pos).strip_edges()
			var rhs_str: String = text.substr(op_pos + op.length()).strip_edges()
			var lhs_val: Variant = _resolve_lhs(lhs_str, bb)
			var rhs_val: Variant = _resolve_rhs(rhs_str, bb)
			return compare_values(lhs_val, op, rhs_val)

	# 标识符或字面量（支持前缀 `!` 取反）
	var negated: bool = false
	while text.begins_with("!"):
		negated = not negated
		text = text.substr(1).strip_edges()

	if text.is_empty():
		return false

	# 若 `!` 后紧跟括号子句（如 `!(a && b)` 或 `!(hp <= 0.3)`）
	if text.begins_with("(") and text.ends_with(")"):
		var inner: String = _strip_outer_parens(text)
		if inner != text:
			var is_compound: bool = (
				_split_top_level(inner, "||").size() > 1
				or _split_top_level(inner, "&&").size() > 1
			)
			if not is_compound:
				for op_chk: String in _CMP_OPS:
					if _find_top_level_op(inner, op_chk) > 0:
						is_compound = true
						break
			if is_compound:
				var group_res: bool = eval_expr(inner, cond_lookup, bb, fsm_ctx)
				return (not group_res) if negated else group_res
			text = inner

	var lower: String = text.to_lower()
	if lower == "true":
		return not negated
	if lower == "false":
		return negated

	var ident_sn: StringName = StringName(text)
	if cond_lookup.is_valid():
		var looked_up: Variant = cond_lookup.call(ident_sn)
		if looked_up is Callable:
			var cb: Callable = looked_up as Callable
			if cb.is_valid():
				var cb_res: bool = bool(cb.call(fsm_ctx)) if cb.get_argument_count() >= 1 else bool(cb.call())
				return (not cb_res) if negated else cb_res

	if bb != null and bb.has_key(ident_sn):
		var bb_res: bool = bool(bb.get_var(ident_sn, false))
		return (not bb_res) if negated else bb_res

	# 关键安全规则：既不在 cond_lookup 也不在 bb 中的未知条件键，无论是否带 `!` 一律返回 false
	return false


static func _resolve_lhs(token: String, bb: BTBlackboard) -> Variant:
	var key_sn: StringName = StringName(token)
	if bb != null and bb.has_key(key_sn):
		return bb.get_var(key_sn, null)
	if _is_quoted(token) or token.is_valid_int() or token.is_valid_float() or token.to_lower() in ["true", "false", "null"]:
		return _infer_literal(token)
	return null


static func _resolve_rhs(token: String, bb: BTBlackboard) -> Variant:
	if _is_quoted(token) or token.is_valid_int() or token.is_valid_float() or token.to_lower() in ["true", "false", "null"]:
		return _infer_literal(token)
	var key_sn: StringName = StringName(token)
	if bb != null and bb.has_key(key_sn):
		return bb.get_var(key_sn, null)
	return token


## 通用安全值比较（兼容 int/float 跨数值比较与 String/StringName 相等比较）。
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
		"==": return typeof(lhs) == typeof(rhs) and lhs == rhs
		"!=": return typeof(lhs) != typeof(rhs) or lhs != rhs
		"<":  return float(lhs) < float(rhs)
		"<=": return float(lhs) <= float(rhs)
		">":  return float(lhs) > float(rhs)
		">=": return float(lhs) >= float(rhs)
		_:    return false


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
		var wraps_all: bool = true
		for i: int in range(cur.length()):
			var ch: String = cur[i]
			if not quote_ch.is_empty():
				if ch == quote_ch:
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
	var start: int = 0
	var sep_len: int = sep.length()
	var i: int = 0
	while i < s.length():
		var ch: String = s[i]
		if not quote_ch.is_empty():
			if ch == quote_ch:
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
	var op_len: int = op.length()
	for i: int in range(s.length() - op_len + 1):
		var ch: String = s[i]
		if not quote_ch.is_empty():
			if ch == quote_ch:
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
