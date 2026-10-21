# Params (参数契约基类)

## 核心

提供场景路由、弹窗传参、组件装配等数据契约实体的通用基类。
通过 GDScript 原生属性反射自动完成 Dictionary 与强类型对象间的双向映射，消除所有重复手写的 `from_dict` / `to_dict` 样板代码。

---

## 细节

- **零样板声明**：业务子类仅需 `extends BaseParams` 并声明强类型变量与默认值，无需重写序列化方法。
- **预编译 Schema 缓存（O(1) 零反射开销）**：每个派生类全生命周期仅扫描 1 次 `get_property_list()`，将公开脚本变量（自动忽略 `_` 前缀的内部私有变量）预编译为静态描述符表，消除高频实例化时的跨界反射损耗。
- **全栈递归模具推导**：
  - **基础标量与结构体**：`int / float / bool / String / StringName` 防漂移转换；`Vector2/3`、`Color`、`Rect2`、`Packed*Array` 既支持内存原值映射，也支持从 JSON 字典/数组/字符串宽容还原。
  - **强类型嵌套容器**：利用 Godot 4.7 原生容器自省（`Array.get_typed_script()`、`Dictionary.get_typed_value_script()`），全自动递归映射 `Array[SubParams]`、`Dictionary[String, SubParams]` 等任意深度组合。
  - **嵌套 BaseParams 与自定义 Resource**：单字段子对象（含初始值为 `null` 的静态类型属性）及多态子类（按需最小信息熵标记 `_type`）自动递归填充与导出。
  - **原生引擎资源引用透传**：`Texture2D`、`ShaderMaterial`、`AudioStream` 等无脚本原生资源引用在内存传参时无损透传持有。
- **构造即解析与原生深拷贝**：构造函数 `_init(dict: Dictionary = {})` 支持传入 Dictionary 快速实例化；内置 `clone()` 提供免字典中转的高速内存深拷贝。

```text
src/framework/infra/param/
├── _doc_param.md             # 本模块说明文档
└── base_params.gd            # 参数契约实体基类 (自动反射序列化/反序列化)
```

---

## 样例

```gdscript
# 1. 声明数据契约类（仅需定义字段与默认值）
class Params extends BaseParams:
	var level_id: int = 1
	var theme_title: String = "Classic Movies"
	var is_unlocked: bool = false
	var tags: Array[String] = []
	var texture: Texture2D = null
	var entry: AssetEntry = AssetEntry.new()

# 2. 从 Dictionary 初始化实例（标量自动转换、数组自动定型、实体自动 decode）
var p := Params.new({
	"level_id": "5",
	"theme_title": "Wild Animals",
	"is_unlocked": 1,
	"tags": ["nature", "wild"],
	"entry": {
		"key": "level_5",
		"url": "https://cdn.jigsaw.com/lvl5.png"
	}
})

# 3. 访问强类型字段（享受 IDE 完整类型提示）
print(p.level_id)        # 5 (int)
print(p.entry.url)       # "https://cdn.jigsaw.com/lvl5.png"

# 4. 序列化为 Dictionary（嵌套实体自动递归 encode）
var dict: Dictionary = p.to_dict()

# 5. 在组件 setup 接口中一行兼容 Params 实例与 Dictionary
func setup(raw_params: Variant = {}) -> void:
	var params: Params = raw_params if raw_params is Params else Params.new(raw_params if raw_params is Dictionary else {})
```
