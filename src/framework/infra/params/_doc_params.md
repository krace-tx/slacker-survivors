# Params (参数契约基类)

## 核心

提供场景路由、弹窗传参、组件装配等数据契约实体的通用基类。
通过 GDScript 原生属性反射自动完成 Dictionary 与强类型对象间的双向映射，消除所有重复手写的 `from_dict` / `to_dict` 样板代码。

---

## 细节

- **零样板声明**：业务子类仅需 `extends BaseParams` 并声明强类型变量与默认值，无需重写序列化方法。
- **自动反射遍历**：内部通过 `get_property_list()` 配合 `PROPERTY_USAGE_SCRIPT_VARIABLE` 精准过滤，仅处理开发者自定义声明的字段，不污染原生底层属性。
- **全类型适配**：
  - **基础标量**：`int / float / bool / String` 宽容度类型转换与空值安全。
  - **强类型与 Packed 数组**：`Array[String]`、`Array[int]`、`PackedByteArray` 等自动转换与类型保持。
  - **复合容器**：`Array`、`Dictionary`、`Vector2/3`、`Color`、`Rect2` 原生引擎结构体直接映射。
  - **嵌套 BaseParams**：多级嵌套子对象自动递归 `from_dict` 填充与递归 `to_dict` 导出。
  - **自定义 Resource 业务实体**：对包含 `encode()`/`decode()` 的实体（如 `AssetEntry`、`UserProfile`）自动解码与序列化。
  - **内存 Resource 引用**：`Texture2D`、`ShaderMaterial`、`Resource` 引用实例安全传递。
- **构造即解析**：构造函数 `_init(dict: Dictionary = {})` 支持直接传入 Dictionary 完成快速实例化。

```text
src/framework/infra/params/
├── _doc_params.md            # 本模块说明文档
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
