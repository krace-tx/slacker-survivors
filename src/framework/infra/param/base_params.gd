class_name BaseParams
extends RefCounted

## 通用参数契约与领域数据实体基类 (BaseParams)。[br]
##
## [b]核心设计（第一性原理）：[/b][br]
## 1. [b]预编译属性 Schema 缓存（O(1) 零反射开销）[/b]：每个派生类（含内部类 Inner Class）在全生命周期内仅解析 1 次
##    [method Object.get_property_list]，以 [code]Script.get_instance_id()[/code] 为 O(1) 整数键缓存静态描述符表；[br]
## 2. [b]全栈递归模具推导[/b]：利用属性静态类型与 Godot 4.7 容器原生自省（[method Array.get_typed_script]、
##    [method Dictionary.get_typed_value_script]），自顶向下直接传递 [Script] 引用，自动完成嵌套 [BaseParams]、
##    自定义 [Resource]、[code]Array[T][/code] 与 [code]Dictionary[K, V][/code] 的双向映射；[br]
## 3. [b]最小信息熵多态染色[/b]：静态类型一致时导出 100% 纯净 Dictionary；仅在发生多态子类赋值或存入弱类型容器时按需标记 [constant TYPE_KEY]；[br]
## 4. [b]全类型鲁棒宽容度适配与环路熔断[/b]：内置标量防漂移转换（含 [code]"false"/"0"[/code] 布尔安全解析）、引擎结构体多形态还原、
##    原生视觉/音频 [Resource] 内存引用无损透传，以及调用栈祖先环路检测（Cycle Detection）。


#region Constants & Static Caches

const TYPE_KEY := "_type" ## 多态子类或弱类型容器内记录全局类名的保留键。
const MAX_DEPTH := 32 ## 最大递归深度保护。

## 预编译属性 Schema 缓存：int (script_instance_id) -> { "fields": Array[Dictionary], "map": Dictionary }
static var _schema_cache: Dictionary = {}
## 全局类名 -> 脚本路径映射：StringName (class_name) -> String (res://...)
static var _class_path_cache: Dictionary = {}
## 脚本路径 -> 全局类名反向映射：String (res://...) -> StringName (class_name)
static var _path_class_cache: Dictionary = {}
## 已完成安全校验的脚本路径缓存：String (class_name or path) -> String (verified res:// path)
## 注意：仅缓存 String 路径而不强持有 Script 实例，杜绝退出时触发 Resource 残留告警。
static var _verified_path_cache: Dictionary = {}
static var _class_registry_ready: bool = false

#endregion


#region Lifecycle

## 构造函数：支持直接传入 [Dictionary] 快速实例化并自动完成强类型填充。
func _init(dict: Dictionary = {}) -> void:
	if dict != null and not dict.is_empty():
		from_dict(dict)

#endregion


#region Public API

## 从 [Dictionary] 数据源递归填充自身属性（支持流式链式调用，返回 [code]self[/code]）。
func from_dict(data: Dictionary) -> BaseParams:
	if data == null or data.is_empty():
		return self
	_decode_into_params(self, data, 0)
	return self


## 导出当前全部公开自定义成员变量为纯净 [Dictionary]。[br]
## [param json_friendly] 为 [code]true[/code] 时，将 [Vector2]、[Color]、[Rect2] 等引擎结构体也展开为纯 JSON 基础类型；
## 默认为 [code]false[/code]（嵌套实体与容器递归转为 Dictionary/Array，原生结构体与资源引用直接保留）。
func to_dict(json_friendly: bool = false) -> Dictionary:
	var ancestors: Array[int] = []
	return _encode_params(self, get_script() as Script, json_friendly, ancestors, 0)


## 原生内存深拷贝：基于预编译 Schema 直接在内存中递归复制整棵对象树（免除 Dictionary 中转开销）。
func clone() -> BaseParams:
	var ancestors: Array[int] = []
	return _clone_params(self, ancestors, 0)


## 清空静态 Schema 与类注册表缓存（供热重载或单测重置使用）。
static func clear_caches() -> void:
	_schema_cache.clear()
	_class_path_cache.clear()
	_path_class_cache.clear()
	_verified_path_cache.clear()
	_class_registry_ready = false

#endregion


#region Core Operator 1: Serialize (BaseParams -> Dictionary)

static func _encode_params(
	params: BaseParams,
	expected_script: Script,
	json_friendly: bool,
	ancestors: Array[int],
	depth: int
) -> Dictionary:
	if params == null or depth > MAX_DEPTH:
		return {}

	var inst_id := params.get_instance_id()
	if inst_id in ancestors:
		push_warning("BaseParams.to_dict: Circular reference detected on BaseParams (id=%d), breaking cycle." % inst_id)
		return {}

	ancestors.push_back(inst_id)

	var result: Dictionary = {}
	var actual_script: Script = params.get_script() as Script

	# 最小信息熵：仅当实际脚本与父属性静态声明脚本不一致（多态子类或弱类型容器）时写入 _type
	if actual_script != null and actual_script != expected_script:
		var tag := _get_type_tag_for_script(actual_script)
		if not tag.is_empty():
			result[TYPE_KEY] = String(tag)

	var schema := _get_schema(params)
	var fields: Array = schema["fields"]

	for field: Dictionary in fields:
		var prop_name: String = field["name"]
		var val: Variant = params.get(prop_name)
		var field_expected_script: Script = _resolve_script(field["class_name"]) if field["type"] == TYPE_OBJECT else null
		result[prop_name] = _serialize_value(val, field_expected_script, json_friendly, ancestors, depth + 1)

	ancestors.pop_back()
	return result


static func _serialize_value(
	val: Variant,
	expected_script: Script,
	json_friendly: bool,
	ancestors: Array[int],
	depth: int
) -> Variant:
	if val == null or depth > MAX_DEPTH:
		return null

	# 1. 嵌套 BaseParams 子实体
	if val is BaseParams:
		return _encode_params(val as BaseParams, expected_script, json_friendly, ancestors, depth)

	# 2. 自定义 Resource 业务实体 vs 引擎原生引用资源（如 Texture2D / ShaderMaterial）
	if val is Resource:
		if val.has_method("encode"):
			return val.encode()
		if val.get_script() != null:
			return ResourceCodecUtils.encode(val as Resource)
		# 原生无脚本 Resource（Texture2D / AudioStream / Material 等）直接无损透传内存引用
		return val

	# 3. Array 容器递归序列化
	if val is Array:
		var arr := val as Array
		var elem_script: Script = arr.get_typed_script()
		if elem_script == null and not arr.get_typed_class_name().is_empty():
			elem_script = _resolve_script(arr.get_typed_class_name())

		var out_arr: Array = []
		out_arr.resize(arr.size())
		for i in arr.size():
			out_arr[i] = _serialize_value(arr[i], elem_script, json_friendly, ancestors, depth + 1)
		return out_arr

	# 4. Dictionary 容器递归序列化
	if val is Dictionary:
		var dict := val as Dictionary
		var k_script: Script = dict.get_typed_key_script()
		var v_script: Script = dict.get_typed_value_script()
		if v_script == null and not dict.get_typed_value_class_name().is_empty():
			v_script = _resolve_script(dict.get_typed_value_class_name())

		var out_dict: Dictionary = {}
		for k in dict:
			var sk: Variant = _serialize_value(k, k_script, json_friendly, ancestors, depth + 1)
			var sv: Variant = _serialize_value(dict[k], v_script, json_friendly, ancestors, depth + 1)
			out_dict[sk] = sv
		return out_dict

	# 5. 可选 JSON 友好展开模式
	if json_friendly:
		return ResourceCodecUtils._encode_primitive(val)

	return val

#endregion


#region Core Operator 2: Deserialize (Dictionary + TypeMold -> BaseParams)

static func _decode_into_params(target: BaseParams, data: Dictionary, depth: int) -> void:
	if target == null or data.is_empty() or depth > MAX_DEPTH:
		return

	var schema := _get_schema(target)
	var field_map: Dictionary = schema["map"]

	for raw_key in data:
		var prop_name := str(raw_key)
		if prop_name == TYPE_KEY or not field_map.has(prop_name):
			continue

		var field: Dictionary = field_map[prop_name]
		var current_val: Variant = target.get(prop_name)
		var incoming_val: Variant = data[raw_key]
		var expected_script: Script = current_val.get_script() as Script if current_val is Object else null
		var decoded_val: Variant = _deserialize_value(
			current_val,
			incoming_val,
			field["type"],
			expected_script,
			field["class_name"],
			field,
			depth + 1
		)
		target.set(prop_name, decoded_val)


static func _deserialize_value(
	current_val: Variant,
	incoming_val: Variant,
	expected_type: int,
	expected_script: Script,
	expected_class: StringName,
	field_meta: Dictionary,
	depth: int
) -> Variant:
	if incoming_val == null or depth > MAX_DEPTH:
		return null

	# 1. 目标是 Object（嵌套 BaseParams、自定义 Resource 实体、或引擎资源引用）
	if expected_type == TYPE_OBJECT or current_val is BaseParams or current_val is Resource \
			or (incoming_val is Dictionary and (incoming_val as Dictionary).has(TYPE_KEY)):
		# 若传入的已经是目标对象实例（如直接透传了 Texture2D、SubParams 或 Resource 实例），直接采纳
		if incoming_val is BaseParams or incoming_val is Resource:
			return incoming_val

		if incoming_val is Dictionary:
			var in_dict := incoming_val as Dictionary

			# 1a. 当前字段已有 BaseParams 默认实例（且未发生多态子类冲突）：就地递归填充
			if current_val is BaseParams and not _has_conflicting_type_tag(in_dict, current_val as Object):
				_decode_into_params(current_val as BaseParams, in_dict, depth)
				return current_val

			# 1b. 当前字段已有自定义 Resource 默认实例（且未发生多态子类冲突）
			if current_val is Resource and (current_val.has_method("encode") or current_val.get_script() != null) \
					and not _has_conflicting_type_tag(in_dict, current_val as Object):
				var res_script: Script = current_val.get_script() as Script
				if res_script != null and res_script.has_script_method("decode"):
					return res_script.call("decode", in_dict)
				return ResourceCodecUtils.decode(in_dict, res_script)

			# 1c. 当前字段默认值为 null、容器元素或需按 _type 多态实例化
			var target_script := _resolve_target_script(expected_script, expected_class, in_dict)
			if target_script != null and target_script.can_instantiate():
				var base_type := target_script.get_instance_base_type()
				if base_type == &"Resource" or ClassDB.is_parent_class(base_type, &"Resource"):
					if target_script.has_script_method("decode"):
						return target_script.call("decode", in_dict)
					return ResourceCodecUtils.decode(in_dict, target_script)
				else:
					var inst: Variant = target_script.new()
					if inst is BaseParams:
						_decode_into_params(inst as BaseParams, in_dict, depth)
						return inst

		return incoming_val

	# 2. 强类型与嵌套 Array 适配（直接传递 elem_script，完美支持全局类与内部类 Inner Class）
	if expected_type == TYPE_ARRAY or current_val is Array:
		if not (incoming_val is Array):
			return current_val if current_val is Array else []

		var in_arr := incoming_val as Array
		var elem_type: int = TYPE_NIL
		var elem_class: StringName = &""
		var elem_script: Script = null

		if current_val is Array and (current_val as Array).is_typed():
			var tpl_arr := current_val as Array
			elem_type = tpl_arr.get_typed_builtin()
			elem_script = tpl_arr.get_typed_script()
			elem_class = _get_type_tag_for_script(elem_script) if elem_script != null else tpl_arr.get_typed_class_name()
		elif not field_meta.is_empty():
			elem_type = field_meta.get("elem_type", TYPE_NIL)
			elem_class = field_meta.get("elem_class", &"")
			if elem_type == TYPE_OBJECT and not elem_class.is_empty():
				elem_script = _resolve_script(elem_class)

		var decoded_items: Array = []
		decoded_items.resize(in_arr.size())
		for i in in_arr.size():
			decoded_items[i] = _deserialize_value(null, in_arr[i], elem_type, elem_script, elem_class, {}, depth + 1)

		if current_val is Array and (current_val as Array).is_typed():
			var typed_arr: Array = (current_val as Array).duplicate()
			typed_arr.clear()
			typed_arr.assign(decoded_items)
			return typed_arr

		# 后备构造：仅当 elem_type == TYPE_OBJECT 时才允许传 class_name 与 script
		if elem_type != TYPE_NIL:
			var base_cls: StringName = &""
			var script_arg: Script = null
			if elem_type == TYPE_OBJECT:
				base_cls = elem_script.get_instance_base_type() if elem_script != null else (elem_class if not elem_class.is_empty() else &"RefCounted")
				script_arg = elem_script
			var constructed := Array([], elem_type, base_cls, script_arg)
			constructed.assign(decoded_items)
			return constructed

		return decoded_items

	# 3. 强类型与嵌套 Dictionary 适配（支持 Dictionary[K, SubParams] / Dictionary[K, SubResource]）
	if expected_type == TYPE_DICTIONARY or current_val is Dictionary:
		if not (incoming_val is Dictionary):
			return current_val if current_val is Dictionary else {}

		var in_dict := incoming_val as Dictionary
		var k_type: int = TYPE_NIL
		var k_script: Script = null
		var k_class: StringName = &""
		var v_type: int = TYPE_NIL
		var v_script: Script = null
		var v_class: StringName = &""

		if current_val is Dictionary and (current_val as Dictionary).is_typed():
			var tpl_dict := current_val as Dictionary
			k_type = tpl_dict.get_typed_key_builtin()
			k_script = tpl_dict.get_typed_key_script()
			k_class = _get_type_tag_for_script(k_script) if k_script != null else tpl_dict.get_typed_key_class_name()

			v_type = tpl_dict.get_typed_value_builtin()
			v_script = tpl_dict.get_typed_value_script()
			v_class = _get_type_tag_for_script(v_script) if v_script != null else tpl_dict.get_typed_value_class_name()

		var decoded_dict: Dictionary = {}
		for rk in in_dict:
			var k: Variant = _deserialize_value(null, rk, k_type, k_script, k_class, {}, depth + 1)
			var v: Variant = _deserialize_value(null, in_dict[rk], v_type, v_script, v_class, {}, depth + 1)
			decoded_dict[k] = v

		if current_val is Dictionary and (current_val as Dictionary).is_typed():
			var typed_dict: Dictionary = (current_val as Dictionary).duplicate()
			typed_dict.clear()
			typed_dict.assign(decoded_dict)
			return typed_dict

		return decoded_dict

	# 4. 基础标量、PackedArray 与引擎结构体宽容度转换（复用 ResourceCodecUtils 原语解码器）
	var target_builtin_type: int = expected_type if expected_type != TYPE_NIL else typeof(current_val)
	if target_builtin_type != TYPE_NIL:
		return ResourceCodecUtils._decode_primitive(incoming_val, target_builtin_type)

	return incoming_val

#endregion


#region Core Operator 3: Direct Memory Clone

static func _clone_params(src: BaseParams, ancestors: Array[int], depth: int) -> BaseParams:
	if src == null or depth > MAX_DEPTH:
		return null

	var inst_id := src.get_instance_id()
	if inst_id in ancestors:
		push_warning("BaseParams.clone: Circular reference detected on BaseParams (id=%d), breaking cycle." % inst_id)
		return null

	ancestors.push_back(inst_id)

	var script: Script = src.get_script() as Script
	if script == null or not script.can_instantiate():
		ancestors.pop_back()
		return BaseParams.new()

	var dst := script.new() as BaseParams
	if dst == null:
		ancestors.pop_back()
		return BaseParams.new()

	var schema := _get_schema(src)
	var fields: Array = schema["fields"]
	for field: Dictionary in fields:
		var prop_name: String = field["name"]
		dst.set(prop_name, _clone_value(src.get(prop_name), ancestors, depth + 1))

	ancestors.pop_back()
	return dst


static func _clone_value(val: Variant, ancestors: Array[int], depth: int) -> Variant:
	if val == null or depth > MAX_DEPTH:
		return null
	if val is BaseParams:
		return _clone_params(val as BaseParams, ancestors, depth)
	if val is Resource:
		if val.get_script() != null or val.has_method("encode"):
			return ResourceCodecUtils.clone(val as Resource)
		return val
	if val is Array:
		var src_arr := val as Array
		var dst_arr: Array = src_arr.duplicate()
		dst_arr.clear()
		var items: Array = []
		items.resize(src_arr.size())
		for i in src_arr.size():
			items[i] = _clone_value(src_arr[i], ancestors, depth + 1)
		dst_arr.assign(items)
		return dst_arr
	if val is Dictionary:
		var src_dict := val as Dictionary
		var dst_dict: Dictionary = src_dict.duplicate()
		dst_dict.clear()
		var temp: Dictionary = {}
		for k in src_dict:
			temp[_clone_value(k, ancestors, depth + 1)] = _clone_value(src_dict[k], ancestors, depth + 1)
		dst_dict.assign(temp)
		return dst_dict
	return val

#endregion


#region Pre-compiled Schema & Safe Script Resolution

## 获取或构建指定 [BaseParams] 子类的预编译属性 Schema（全生命周期仅解析一次）。
static func _get_schema(params: BaseParams) -> Dictionary:
	var cache_key: Variant = _get_schema_cache_key(params)
	if _schema_cache.has(cache_key):
		return _schema_cache[cache_key]

	var fields: Array[Dictionary] = []
	var field_map: Dictionary = {}

	for prop: Dictionary in params.get_property_list():
		var usage: int = prop.get("usage", 0)
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name_str: String = prop.get("name", "")
		# 自动过滤 _ 开头的内部私有/缓存变量与保留键
		if name_str.is_empty() or name_str.begins_with("_"):
			continue

		var prop_type: int = prop.get("type", TYPE_NIL)
		var prop_class: StringName = &""
		var elem_type: int = TYPE_NIL
		var elem_class: StringName = &""

		if prop_type == TYPE_OBJECT:
			var cls_str := str(prop.get("class_name", ""))
			var hint_str := str(prop.get("hint_string", ""))
			prop_class = StringName(cls_str if not cls_str.is_empty() else hint_str)
		elif prop_type == TYPE_ARRAY:
			var hint: int = prop.get("hint", PROPERTY_HINT_NONE)
			if hint == PROPERTY_HINT_ARRAY_TYPE or hint == PROPERTY_HINT_TYPE_STRING:
				var hint_str := str(prop.get("hint_string", ""))
				var colon_idx := hint_str.find(":")
				if colon_idx != -1:
					var prefix := hint_str.substr(0, colon_idx)
					var slash_idx := prefix.find("/")
					elem_type = int(prefix.substr(0, slash_idx if slash_idx != -1 else prefix.length()))
					if elem_type == TYPE_OBJECT:
						elem_class = StringName(hint_str.substr(colon_idx + 1))

		var meta := {
			"name": name_str,
			"type": prop_type,
			"class_name": prop_class,
			"elem_type": elem_type,
			"elem_class": elem_class,
		}
		fields.append(meta)
		field_map[name_str] = meta

	var schema := {"fields": fields, "map": field_map}
	_schema_cache[cache_key] = schema
	return schema


static func _get_schema_cache_key(params: BaseParams) -> Variant:
	var script: Script = params.get_script() as Script
	if script != null:
		return script.get_instance_id()
	return &"BaseParams"


static func _resolve_target_script(expected_script: Script, expected_class: StringName, in_dict: Dictionary) -> Script:
	if in_dict.has(TYPE_KEY):
		var tag_script := _resolve_script(StringName(str(in_dict[TYPE_KEY])))
		if tag_script != null:
			return tag_script
	if expected_script != null:
		return expected_script
	if not expected_class.is_empty():
		return _resolve_script(expected_class)
	return null


static func _resolve_script(identifier: StringName) -> Script:
	if identifier.is_empty():
		return null
	var key := String(identifier)
	if _verified_path_cache.has(key):
		return ResourceLoader.load(_verified_path_cache[key]) as Script

	_ensure_class_registry()

	var path := ""
	if _class_path_cache.has(identifier):
		path = _class_path_cache[identifier]
	elif key.begins_with("res://") and not key.contains("..") and key.ends_with(".gd"):
		path = key

	if path.is_empty() or not ResourceLoader.exists(path):
		return null

	var loaded := ResourceLoader.load(path)
	if loaded is Script:
		var script := loaded as Script
		if script.can_instantiate():
			var base_type := script.get_instance_base_type()
			# 安全沙箱：仅允许实例化 RefCounted / Resource 派生类，严禁实例化 Node 或 SceneTree
			if base_type == &"RefCounted" or base_type == &"Resource" \
					or ClassDB.is_parent_class(base_type, &"RefCounted"):
				_verified_path_cache[key] = path
				return script

	return null


static func _ensure_class_registry() -> void:
	if _class_registry_ready:
		return
	_class_registry_ready = true
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls_name := StringName(entry.get("class", ""))
		var path := String(entry.get("path", ""))
		if not cls_name.is_empty() and not path.is_empty():
			_class_path_cache[cls_name] = path
			_path_class_cache[path] = cls_name


static func _get_type_tag_for_script(script: Script) -> StringName:
	if script == null:
		return &""
	var global_name := script.get_global_name()
	if not global_name.is_empty():
		return global_name
	_ensure_class_registry()
	var path := script.resource_path
	if _path_class_cache.has(path):
		return _path_class_cache[path]
	return StringName(path)


static func _has_conflicting_type_tag(dict: Dictionary, existing: Object) -> bool:
	if not dict.has(TYPE_KEY):
		return false
	var tag := StringName(str(dict[TYPE_KEY]))
	if tag.is_empty():
		return false
	var existing_script: Script = existing.get_script() as Script
	if existing_script == null:
		return true
	return tag != _get_type_tag_for_script(existing_script) and String(tag) != existing_script.resource_path

#endregion
