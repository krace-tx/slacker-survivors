class_name ResourceCodecUtils
extends RefCounted

## 自定义 Resource 与 Dictionary 的编解码。[br]
##
## Storage 只搬运 Dictionary；调度层先走本工具，再交给 [StorageService]。[br]
## 引擎内置类型 ↔ 二进制用 [FileCodecUtils]，不经过这里。[br]
##
## 自定义 Resource 子类会自动还原：只要对象是 [method encode] 产出的
##（会把脚本路径写进 [constant SCRIPT_PATH_KEY]），或由实体传入 [param script_paths]
##（属性键 → 脚本路径，根对象用空字符串）。


#region Constants

const SCRIPT_PATH_KEY := "_script_path" ## 字典里记下 Resource 脚本路径的保留键。

const DEFAULT_SKIP_NAMES: Array[String] = [
	"resource_local_to_scene",
	"resource_name",
	"resource_path",
	"script",
] ## 内置 Resource 属性，永不参与序列化。

#endregion


#region Public API

## 把 [param resource] 中需要落盘的属性编成 Dictionary。[br]
## 嵌套的 Resource、Array、Dictionary 会递归处理。[br]
## [param extra_skip_names] 仅本次调用额外跳过的属性名。[br]
## [param include_script_path] 是否附加 _script_path 字段，默认为 false（保持纯净 JSON）。
static func encode(
		resource: Resource,
		extra_skip_names: Array[String] = [],
		include_script_path: bool = false
	) -> Dictionary:
	if resource == null:
		return {}

	var encoded := {}

	if include_script_path:
		var script_path := _get_script_path(resource)
		if not script_path.is_empty():
			encoded[SCRIPT_PATH_KEY] = script_path

	var skip_names := _build_skip_names(extra_skip_names)
	for property in resource.get_property_list():
		if not _is_serializable_property(property, skip_names):
			continue
		encoded[property.name] = _encode_value(resource.get(property.name), extra_skip_names, include_script_path)

	return encoded


## 把 [param encoded] 解成 Resource（已知时用正确子类）。[br]
## [param script_paths] 由实体配置：属性键 → 脚本路径，优先于字典内嵌的路径；根对象用空字符串。[br]
## [param property_key] 标明当前还原的是哪个属性；根调用留空。[br]
## [param class_name_hint] 没有显式或内嵌脚本路径时的实例化类名（类型化数组 / 对象属性用）。
static func decode(
		encoded: Dictionary,
		script_paths: Dictionary = {},
		property_key: String = "",
		class_name_hint: String = ""
	) -> Resource:
	var script_path: String = script_paths.get(property_key, "")
	if script_path.is_empty():
		script_path = str(encoded.get(SCRIPT_PATH_KEY, ""))

	var resource := _instantiate_resource(script_path, class_name_hint)
	_decode_into(resource, encoded, script_paths)
	return resource


## 深拷贝一个自定义 [Resource] 实例。[br]
## 通过编码再解码，创建一份结构与数据完全独立的新实体实例。[br]
## [param resource]：要克隆的目标实体；为 null 时返回 null。[br]
## [param script_paths]：自定义实体属性键与脚本路径的映射字典（可选）。
static func clone(
		resource: Resource,
		script_paths: Dictionary = {}
	) -> Resource:
	if resource == null:
		return null
	var encoded := encode(resource, [], false)
	return decode(encoded, script_paths)


#endregion


#region Encode

## 递归展开 [param value] 里的 Resource / Array / Dictionary；其余类型原样返回。
static func _encode_value(value: Variant, extra_skip_names: Array[String] = [], include_script_path: bool = false) -> Variant:
	if value == null:
		return null
	if value is Resource:
		return encode(value, extra_skip_names, include_script_path)
	if value is Array:
		return value.map(func(item): return _encode_value(item, extra_skip_names, include_script_path))
	if value is Dictionary:
		var encoded := {}
		for key in value:
			encoded[key] = _encode_value(value[key], extra_skip_names, include_script_path)
		return encoded
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	return value

#endregion


#region Decode

## 把 [param encoded] 中适用的项写到 [param resource] 上，必要时递归进嵌套 Resource 和 Array。
static func _decode_into(resource: Resource, encoded: Dictionary, script_paths: Dictionary) -> void:
	for property_name in encoded:
		if property_name == SCRIPT_PATH_KEY:
			continue
		if _find_property_info(resource, property_name).is_empty():
			continue

		var prop_type := _get_property_type(resource, property_name)
		var value = encoded[property_name]

		if prop_type == TYPE_VECTOR2:
			resource.set(property_name, _decode_vector2(value))
		elif prop_type == TYPE_VECTOR2I:
			resource.set(property_name, _decode_vector2i(value))
		elif value is Dictionary:
			_decode_dict_value(resource, property_name, value, script_paths)
		elif value is Array and prop_type == TYPE_ARRAY:
			resource.set(property_name, _decode_array(resource, property_name, value, script_paths))
		else:
			resource.set(property_name, value)


static func _decode_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		var x = value.get("x", value.get("width", value.get("w", 0.0)))
		var y = value.get("y", value.get("height", value.get("h", 0.0)))
		return Vector2(float(x), float(y))
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is String:
		var cleaned := (value as String).trim_prefix("(").trim_suffix(")").trim_prefix("Vector2(").trim_suffix(")")
		var parts := cleaned.split(",")
		if parts.size() >= 2:
			return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
	return Vector2.ZERO


static func _decode_vector2i(value: Variant) -> Vector2i:
	var v := _decode_vector2(value)
	return Vector2i(int(v.x), int(v.y))


static func _decode_dict_value(resource: Resource, property_name: String, value: Dictionary, script_paths: Dictionary) -> void:
	var current: Variant = resource.get(property_name)
	if current is Resource:
		# 属性上已有 Resource 实例（例如内联默认值），就地填充，不替换。
		_decode_into(current, value, script_paths)
		return

	if _should_treat_as_resource(resource, property_name, value, script_paths):
		var class_name_hint := _get_object_class_name(resource, property_name)
		resource.set(property_name, decode(value, script_paths, property_name, class_name_hint))
	else:
		resource.set(property_name, value)


static func _should_treat_as_resource(resource: Resource, property_name: String, value: Dictionary, script_paths: Dictionary) -> bool:
	if _get_property_type(resource, property_name) == TYPE_OBJECT:
		return true
	if script_paths.has(property_name):
		return true
	# 字典自身带了来源脚本，即可视为 Resource，不看目标属性类型是否宽松。
	return value.has(SCRIPT_PATH_KEY)


static func _decode_array(resource: Resource, property_name: String, values: Array, script_paths: Dictionary) -> Array:
	var element_class_name := _get_array_element_class_name(resource, property_name)
	var elements_are_resources := script_paths.has(property_name) or not element_class_name.is_empty()

	var items: Array = []
	for item in values:
		if item is Dictionary and (elements_are_resources or item.has(SCRIPT_PATH_KEY)):
			items.append(decode(item, script_paths, property_name, element_class_name))
		else:
			items.append(item)

	return _build_typed_array(element_class_name, items)

#endregion


#region Instantiation

static func _instantiate_resource(script_path: String, class_name_hint: String = "") -> Resource:
	var resolved_path := script_path
	if resolved_path.is_empty():
		resolved_path = _find_script_path_for_class(class_name_hint)

	if not resolved_path.is_empty() and ResourceLoader.exists(resolved_path):
		var script := load(resolved_path)
		if script is Script:
			var instance = script.new()
			if instance is Resource:
				return instance

	# 引擎内置 Resource 子类（如 GradientTexture2D）在 ClassDB 中，可无脚本路径直接实例化。
	if not class_name_hint.is_empty() and ClassDB.class_exists(class_name_hint) \
			and ClassDB.can_instantiate(class_name_hint):
		var instance = ClassDB.instantiate(class_name_hint)
		if instance is Resource:
			return instance

	return Resource.new()


static func _find_script_path_for_class(class_name_hint: String) -> String:
	if class_name_hint.is_empty():
		return ""
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == class_name_hint:
			return entry.get("path", "")
	return ""


static func _get_script_path(resource: Resource) -> String:
	var script: Variant = resource.get_script()
	if script is Script:
		return script.resource_path
	return ""

#endregion


#region Reflection

static func _find_property_info(object: Object, property_name: String) -> Dictionary:
	for property in object.get_property_list():
		if property.name == property_name:
			return property
	return {}


static func _get_property_type(object: Object, property_name: String) -> int:
	return _find_property_info(object, property_name).get("type", TYPE_NIL)


## 返回普通 Object/Resource 类型属性（非数组）的可读类名；不是则返回空字符串。[br]
## 这类属性的 [code]hint_string[/code] 本身就是类名。
static func _get_object_class_name(object: Object, property_name: String) -> String:
	var info := _find_property_info(object, property_name)
	if info.get("type", TYPE_NIL) != TYPE_OBJECT:
		return ""
	return str(info.get("hint_string", ""))


## 返回类型化数组属性的元素类型/类名（如 [code]int[/code]、[code]String[/code]、Resource 子类名）。[br]
## [param property_name] 不是类型化数组时返回空字符串。
static func _get_array_element_class_name(object: Object, property_name: String) -> String:
	var info := _find_property_info(object, property_name)
	if info.is_empty():
		return ""
	var hint: int = info.get("hint", PROPERTY_HINT_NONE)
	if hint != PROPERTY_HINT_ARRAY_TYPE and hint != PROPERTY_HINT_TYPE_STRING:
		return ""

	# Godot 类型化数组 hint 形如 "{elem_type}[/{elem_hint}]:{elem_hint_string}"，
	# 例如 "1:bool"、"4:String"、"24/17:MyResource"；可读名取第一个 ":" 之后。
	var hint_string := str(info.get("hint_string", ""))
	var colon_index := hint_string.find(":")
	return hint_string if colon_index == -1 else hint_string.substr(colon_index + 1)


static func _build_skip_names(extra_skip_names: Array[String]) -> Array[String]:
	var skip_names := DEFAULT_SKIP_NAMES.duplicate()
	for skip_name in extra_skip_names:
		if skip_name not in skip_names:
			skip_names.append(skip_name)
	return skip_names


static func _is_serializable_property(property: Dictionary, skip_names: Array[String]) -> bool:
	if not (property.usage & PROPERTY_USAGE_STORAGE):
		return false
	return property.name not in skip_names

#endregion


#region Typed array

static func _build_typed_array(element_class_name: String, items: Array) -> Array:
	if element_class_name.is_empty():
		return items

	var typed_array := _create_empty_typed_array(element_class_name)
	for item in items:
		typed_array.append(item)
	return typed_array


static func _create_empty_typed_array(element_class_name: String) -> Array:
	match element_class_name:
		"String":
			return Array([], TYPE_STRING, "", null)
		"int":
			return Array([], TYPE_INT, "", null)
		"float":
			return Array([], TYPE_FLOAT, "", null)
		"bool":
			return Array([], TYPE_BOOL, "", null)
		_:
			var script_path := _find_script_path_for_class(element_class_name)
			if not script_path.is_empty() and ResourceLoader.exists(script_path):
				var script := load(script_path) as Script
				if script != null:
					return Array([], TYPE_OBJECT, script.get_instance_base_type(), script)
			return Array([], TYPE_OBJECT, element_class_name, null)

#endregion
