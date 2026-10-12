class_name BaseParams
extends RefCounted

## 通用参数契约实体基类 (BaseParams)。
##
## [b]设计目标与核心原理：[/b]
## 1. [b]消除冗余样板代码[/b]：在场景路由（Scene Params）、弹窗配置（Popup Params）、组件装配（Component Params）中，
##    传统方式需为每个数据结构手写重复的 from_dict / to_dict。本基类基于 GDScript 原生反射机制自动完成双向映射；
## 2. [b]零侵入与类型安全[/b]：通过 [constant PROPERTY_USAGE_SCRIPT_VARIABLE] 精准过滤开发者自定义变量，
##    不污染 Godot 引擎底层的 RefCounted/Object 原生属性；
## 3. [b]全类型鲁棒适配[/b]：
##    - 标量类型宽容度转换（防 JSON 序列化引起的 string/int/float/bool 类型漂移）；
##    - 强类型数组（Array[Type]）与 Packed 数组安全转换（防止非定型数组赋值被底层静默拒绝）；
##    - 嵌套 BaseParams 子实体自动递归解析与导出；
##    - 自定义 Resource 业务实体（如 AssetEntry / UserProfile）自动触发 encode / decode；
##    - 内存引用对象（Texture2D / ShaderMaterial / Resource）无损透传持有。

#region Lifecycle
## 构造函数：支持直接传入 Dictionary 快速实例化并自动完成数据填充
func _init(dict: Dictionary = {}) -> void:
	if not dict.is_empty():
		from_dict(dict)
#endregion


#region Public API
## 从 Dictionary 数据源填充自身属性（反序列化流水线）
## 
## [b]算法逻辑：[/b]
## 1. 判空快速短路；
## 2. 遍历本对象全部属性列表 [method Object.get_property_list]；
## 3. 通过 [_is_custom_script_var] 仅筛选开发者脚本中声明的成员变量；
## 4. 若输入字典中存在该键，调用 [_deserialize_value] 执行分层类型适配并写回字段。
func from_dict(data: Dictionary) -> void:
	if data == null or data.is_empty():
		return

	for prop in get_property_list():
		if _is_custom_script_var(prop) and data.has(prop.name):
			var current_val: Variant = get(prop.name)
			var incoming_val: Variant = data[prop.name]
			set(prop.name, _deserialize_value(current_val, incoming_val))


## 导出当前全部自定义成员变量为 Dictionary（序列化流水线）
##
## [b]算法逻辑：[/b]
## 1. 反射提取所有脚本自定义变量名；
## 2. 调用 [_serialize_value] 将字段值（包含嵌套的 BaseParams 与 Resource 业务实体）递归转换为纯 Dictionary/Array 结构；
## 3. 输出纯净无污染的标准 Dictionary。
func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for prop in get_property_list():
		if _is_custom_script_var(prop):
			result[prop.name] = _serialize_value(get(prop.name))
	return result
#endregion


#region Internal Helpers
## 判定属性是否为开发者在脚本中自定义声明的成员变量
##
## [b]位运算原理：[/b]
## 在 Godot 引擎中，每个属性元数据字典都包含 [code]usage[/code] 位掩码。
## [constant PROPERTY_USAGE_SCRIPT_VARIABLE] (数值 8192) 是仅赋予脚本中显式 [code]var[/code] 变量的标志位。
## 通过按位与 [code]&[/code] 运算，可以毫秒级精准过滤掉引擎内置属性（如 script, resource_path, Reference 等）。
static func _is_custom_script_var(prop: Dictionary) -> bool:
	var usage: int = prop.get("usage", 0)
	return (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0


## 单字段反序列化与分层类型适配流水线
##
## [b]类型适配策略（优先级从高到低）：[/b]
## 1. [b]嵌套 BaseParams[/b]：若当前字段为 BaseParams 且输入为 Dictionary，触发多级递归填充；
## 2. [b]自定义 Resource 业务实体[/b]：若字段为具备 encode() 契约的实体，优先调用实体的静态 decode() 方法或走 ResourceCodecUtils 还原；
## 3. [b]强类型数组与 PackedArray 适配[/b]：
##    - Godot 4 中，字典字面量解析出的数组是非定型 Array[Variant]，直接赋值给 Array[String] 等定型数组会被引擎拒绝导致数据丢失；
##    - 此处利用 [method Array.duplicate] 复制原定型数组的类型元信息，并通过 [method Array.assign] 自动安全转型后整体赋回；
##    - 针对 PackedArray 类型（String/Int32/Float32/ByteArray），显式构造对应 Packed 数组；
## 4. [b]基础标量宽容度转换[/b]：
##    - 兼容外部 JSON 接口或弱类型传入（如 "10086" -> 10086, 123 -> "123", "3.14" -> 3.14, 1 -> true）；
## 5. [b]兜底透传[/b]：
##    - 引擎结构体（Vector2/3, Color, Rect2）、已实例化的对象引用、Texture2D 资源及 Dictionary 键值对直接赋值。
static func _deserialize_value(current_val: Variant, incoming_val: Variant) -> Variant:
	# 1. 嵌套 BaseParams 递归填充
	if current_val is BaseParams and incoming_val is Dictionary:
		current_val.from_dict(incoming_val)
		return current_val

	# 2. 自定义 Resource 业务实体 (如 AssetEntry 等自带 encode/decode 的实体)
	if current_val is Resource and current_val.has_method("encode") and incoming_val is Dictionary:
		var script_obj: Script = current_val.get_script() as Script
		if script_obj != null and script_obj.has_script_method("decode"):
			return script_obj.call("decode", incoming_val)
		var script_path: String = script_obj.resource_path if script_obj != null else ""
		return ResourceCodecUtils.decode(incoming_val, {"": script_path})

	# 3. 强类型 Array 与 PackedArray 适配（避免非定型数组赋值被引擎底层静默拦截）
	if current_val is Array and incoming_val is Array:
		var typed_arr: Array = current_val.duplicate()
		typed_arr.clear()
		typed_arr.assign(incoming_val)
		return typed_arr
	if current_val is PackedStringArray and incoming_val is Array:
		return PackedStringArray(incoming_val)
	if current_val is PackedInt32Array and incoming_val is Array:
		return PackedInt32Array(incoming_val)
	if current_val is PackedFloat32Array and incoming_val is Array:
		return PackedFloat32Array(incoming_val)
	if current_val is PackedByteArray and incoming_val is Array:
		return PackedByteArray(incoming_val)

	# 4. 基础标量类型宽容转换（防 JSON 弱类型漂移）
	if current_val is int and (incoming_val is float or incoming_val is String):
		return int(incoming_val)
	if current_val is float and (incoming_val is int or incoming_val is String):
		return float(incoming_val)
	if current_val is bool and not (incoming_val is bool):
		return bool(incoming_val)
	if current_val is String and incoming_val != null and not (incoming_val is String):
		return str(incoming_val)

	# 5. 默认直接返回原始值 (引擎结构体、Resource/Texture 引用、Dictionary 键值对等)
	return incoming_val


## 单字段递归序列化处理
##
## [b]序列化规则：[/b]
## - BaseParams 子实体：递归调用其 to_dict()；
## - 自定义 Resource 业务实体：调用其内置的 encode() 转为标准 Dictionary；
## - Array 列表容器：遍历内部元素，递归对其中的每个子对象执行序列化转换；
## - 其余原生类型：直接返回原值。
static func _serialize_value(val: Variant) -> Variant:
	if val is BaseParams:
		return val.to_dict()
	if val is Resource and val.has_method("encode"):
		return val.encode()
	if val is Array:
		var arr: Array = []
		for item in val:
			arr.append(_serialize_value(item))
		return arr
	return val
#endregion
