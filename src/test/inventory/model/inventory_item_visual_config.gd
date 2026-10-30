class_name InventoryItemVisualConfig
extends RefCounted

## 测试演练场物品视觉表现与静态规格聚合配置（`src/test/inventory/model/`）。[br]
##
## [b]设计职责：[/b][br]
## 将业务层的展示名称、稀有度色板、程序化矢量图标枚举与基建层的最小拓扑规格（[ItemSpec]）绑定，
## 验证基建层 [ItemSpec] 在不侵入任何 UI 字段的前提下如何与上层表现表无缝协作。


#region Enums

## 程序化几何矢量图标绘制类型枚举。
enum IconKind {
	COIN = 0,        ## 金币徽章
	GEM = 1,         ## 切面星晶
	SWORD = 2,       ## 精铁长剑
	RUNE_SWORD = 3,  ## 符文魔剑
	AXE = 4,         ## 双刃战斧
	SHIELD = 5,      ## 苍穹鸢盾
	RING = 6,        ## 红曜指环
	TOTEM = 7,       ## 镇魂石碑（不可旋转）
	POTION = 8,      ## 生命秘药
	ORE = 9,         ## 寒铁矿簇
	MARK_WEAPON = 10,## 空槽底纹：主手
	MARK_SHIELD = 11,## 空槽底纹：副手
	MARK_RING = 12,  ## 空槽底纹：饰品
}

## 物品稀有度品阶枚举。
enum Rarity {
	COMMON = 0,
	UNCOMMON = 1,
	RARE = 2,
	EPIC = 3,
	LEGENDARY = 4,
}

#endregion


#region Properties

## 物品配置唯一标识（对齐 [member ItemSpec.item_id]）。
var item_id: StringName = &""

## 极简展示名称（2~4 字）。
var display_name: String = ""

## 极简分类短签（如 [code]"主手"[/code]、[code]"消耗"[/code]）。
var category_label: String = ""

## 稀有度等级（[enum Rarity]）。
var rarity: int = Rarity.COMMON

## 程序化矢量图标类型（[enum IconKind]）。
var icon_kind: int = IconKind.COIN

## 主题高亮色（用于稀有度顶栏、图标主色与检视标签）。
var accent_color: Color = Color(0.58, 0.64, 0.72, 1.0)

## 默认简短属性词条文案（当 [member ItemStack.meta] 无覆盖值时展示）。
var default_stat: String = ""

## 关联的底层容器拓扑规格描述符。
var spec: ItemSpec = null

#endregion


#region Factories & Formatting

## 构造单条物品视觉与规格配置项。
static func create(
	p_item_id: StringName,
	p_name: String,
	p_category: String,
	p_rarity: int,
	p_icon_kind: int,
	p_stat: String,
	p_spec: ItemSpec
) -> InventoryItemVisualConfig:
	var cfg := InventoryItemVisualConfig.new()
	cfg.item_id = p_item_id
	cfg.display_name = p_name
	cfg.category_label = p_category
	cfg.rarity = p_rarity
	cfg.icon_kind = p_icon_kind
	cfg.accent_color = get_rarity_color(p_rarity)
	cfg.default_stat = p_stat
	cfg.spec = p_spec
	return cfg


## 根据稀有度枚举返回低饱和高质感的珠宝色值。
static func get_rarity_color(p_rarity: int) -> Color:
	match p_rarity:
		Rarity.UNCOMMON:
			return Color(0.20, 0.83, 0.60, 1.0)
		Rarity.RARE:
			return Color(0.22, 0.74, 0.97, 1.0)
		Rarity.EPIC:
			return Color(0.66, 0.54, 0.98, 1.0)
		Rarity.LEGENDARY:
			return Color(0.98, 0.75, 0.15, 1.0)
		_:
			return Color(0.60, 0.67, 0.77, 1.0)


## 返回稀有度对应的双字品阶短名。
static func get_rarity_label(p_rarity: int) -> String:
	match p_rarity:
		Rarity.UNCOMMON:
			return "精良"
		Rarity.RARE:
			return "稀有"
		Rarity.EPIC:
			return "史诗"
		Rarity.LEGENDARY:
			return "传说"
		_:
			return "普通"


## 构建测试演练场全量物品图鉴字典（`StringName -> InventoryItemVisualConfig`）。
static func build_catalog() -> Dictionary:
	var entries: Array[InventoryItemVisualConfig] = [
		create(
			&"gold", "金币", "货币", Rarity.LEGENDARY, IconKind.COIN, "通用货币",
			ItemSpec.create(&"gold", 999999, [&"currency"], Vector2i.ONE, false, 100)
		),
		create(
			&"gem", "星晶", "货币", Rarity.EPIC, IconKind.GEM, "高阶晶石",
			ItemSpec.create(&"gem", 99999, [&"currency"], Vector2i.ONE, false, 99)
		),
		create(
			&"sword_rune", "符文长剑", "主手", Rarity.EPIC, IconKind.RUNE_SWORD, "ATK +42",
			ItemSpec.create(&"sword_rune", 1, [&"equip", &"weapon"], Vector2i(1, 3), true, 96)
		),
		create(
			&"axe_battle", "裂地战斧", "主手", Rarity.RARE, IconKind.AXE, "ATK +32",
			ItemSpec.create(&"axe_battle", 1, [&"equip", &"weapon"], Vector2i(2, 3), true, 92)
		),
		create(
			&"sword_iron", "精铁长剑", "主手", Rarity.UNCOMMON, IconKind.SWORD, "ATK +18",
			ItemSpec.create(&"sword_iron", 1, [&"equip", &"weapon"], Vector2i(1, 3), true, 88)
		),
		create(
			&"shield_kite", "苍穹鸢盾", "副手", Rarity.RARE, IconKind.SHIELD, "DEF +24",
			ItemSpec.create(&"shield_kite", 1, [&"equip", &"shield"], Vector2i(2, 2), true, 84)
		),
		create(
			&"ring_ruby", "红曜指环", "饰品", Rarity.RARE, IconKind.RING, "CRIT +8%",
			ItemSpec.create(&"ring_ruby", 1, [&"equip", &"ring"], Vector2i.ONE, false, 80)
		),
		create(
			&"totem_fixed", "镇魂石碑", "遗物", Rarity.EPIC, IconKind.TOTEM, "RES +15 · 禁旋",
			ItemSpec.create(&"totem_fixed", 1, [&"relic"], Vector2i(1, 2), false, 72)
		),
		create(
			&"potion_hp", "生命秘药", "消耗", Rarity.UNCOMMON, IconKind.POTION, "HP +120",
			ItemSpec.create(&"potion_hp", 10, [&"consumable"], Vector2i.ONE, false, 50)
		),
		create(
			&"ore_iron", "寒铁矿", "材料", Rarity.COMMON, IconKind.ORE, "锻造素材",
			ItemSpec.create(&"ore_iron", 10, [&"material"], Vector2i.ONE, false, 30)
		),
		create(
			&"quest_letter", "密令信函", "任务", Rarity.LEGENDARY, IconKind.TOTEM, "剧情锁定",
			ItemSpec.create(&"quest_letter", 1, [&"quest"], Vector2i.ONE, false, 10)
		),
	]

	var catalog: Dictionary = {}
	for item_cfg: InventoryItemVisualConfig in entries:
		catalog[item_cfg.item_id] = item_cfg
	return catalog


## 从视觉图鉴提取供 [method ItemSpec.resolver_from_dict] 使用的纯规格字典。
static func extract_spec_map(catalog: Dictionary) -> Dictionary:
	var spec_map: Dictionary = {}
	for raw_key: Variant in catalog:
		var cfg: InventoryItemVisualConfig = catalog.get(raw_key, null) as InventoryItemVisualConfig
		if cfg != null and cfg.spec != null:
			spec_map[cfg.item_id] = cfg.spec
	return spec_map


## 结合运行时 [param stack] 的动态 [member ItemStack.meta] 生成极简属性短签。
func format_stat_line(stack: ItemStack) -> String:
	if stack == null:
		return default_stat
	var parts: PackedStringArray = []
	if stack.meta.has("atk"):
		parts.append("ATK +%d" % int(stack.meta.get("atk", 0)))
	elif stack.meta.has("def"):
		parts.append("DEF +%d" % int(stack.meta.get("def", 0)))
	elif stack.meta.has("crit"):
		parts.append("CRIT +%d%%" % int(stack.meta.get("crit", 0)))
	elif not default_stat.is_empty():
		parts.append(default_stat)

	if bool(stack.meta.get("bound", false)):
		parts.append("绑定")
	if bool(stack.meta.get("crafted", false)):
		parts.append("精铸")
	return " · ".join(parts)

#endregion
