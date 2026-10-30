class_name SpineStageConfig
extends RefCounted

## 2.5D「3D 场景 + Spine 2D 骨骼角色（方案 B）」原型静态配置表。[br]
##
## [b]核心职责：[/b][br]
## 1. 定义主角 3 把可热切武器皮肤（[code]weapon/*[/code]）与攻击距离、伤害参数；[br]
## 2. 定义主角 3 套可热切披风/头饰套装皮肤（[code]outfit/*[/code]）与移速倍率；[br]
## 3. 定义 3D 庭院物理走位、跳跃重力与双光影预设常量。

#region Enums & Constants
enum LightingMode {
	DUSK_COURTYARD = 0,
	MOONLIGHT_TORCH = 1,
}

const HERO_SPINE_DATA_PATH: String = "res://src/test/spine_stage/assets/spines/spn_spine_stage_hero_data.tres"
const DUMMY_SPINE_DATA_PATH: String = "res://src/test/spine_stage/assets/spines/spn_spine_stage_dummy_data.tres"

const BASE_MOVE_SPEED: float = 5.4
const JUMP_VELOCITY: float = 7.8
const GRAVITY: float = 21.5
const ATTACK_LUNGE_SPEED: float = 2.6

const ARENA_LIMIT_X: float = 6.8
const ARENA_LIMIT_Z: float = 4.6

const PLAYER_SPAWN_POS: Vector3 = Vector3(-1.1, 0.0, 1.15)
const DUMMY_LEFT_POS: Vector3 = Vector3(-2.85, 0.0, -0.85)
const DUMMY_RIGHT_POS: Vector3 = Vector3(2.35, 0.0, 0.45)

const WEAPON_SKINS: Array[String] = [
	"weapon/sword",
	"weapon/scythe",
	"weapon/hammer",
]

const WEAPON_NAMES: Array[String] = [
	"圣银骑士剑",
	"猩红死神镰",
	"雷霆符文锤",
]

const WEAPON_SUBTITLES: Array[String] = [
	"均衡连斩 · ATK 115",
	"大弧横扫 · ATK 150",
	"重击震退 · ATK 190",
]

const WEAPON_DAMAGES: Array[int] = [115, 150, 190]
const WEAPON_REACHES: Array[float] = [2.35, 2.75, 2.25]
const WEAPON_ACCENTS: Array[Color] = [
	Color("#38BDF8"),
	Color("#F87171"),
	Color("#FBBF24"),
]

const OUTFIT_SKINS: Array[String] = [
	"outfit/ranger",
	"outfit/royal",
	"outfit/abyss",
]

const OUTFIT_NAMES: Array[String] = [
	"翡翠游侠装",
	"暗金铁卫铠",
	"深渊狂猎甲",
]

const OUTFIT_SUBTITLES: Array[String] = [
	"轻盈羽帽 · 移速 +12%",
	"王室金冠 · 标准均衡",
	"狂猎骨角 · 移速 +6%",
]

const OUTFIT_SPEED_MULTS: Array[float] = [1.12, 1.00, 1.06]
const OUTFIT_ACCENTS: Array[Color] = [
	Color("#34D399"),
	Color("#FBBF24"),
	Color("#A78BFA"),
]

const LIGHTING_NAMES: Array[String] = [
	"黄昏斜阳 + 火盆补光",
	"幽蓝月夜 + 火把长影",
]
#endregion


#region Public Lookup Helpers
## 获取归一化后的武器槽位索引。
static func clamp_weapon_index(idx: int) -> int:
	var count: int = WEAPON_SKINS.size()
	return posmod(idx, count)


## 获取归一化后的服饰套装索引。
static func clamp_outfit_index(idx: int) -> int:
	var count: int = OUTFIT_SKINS.size()
	return posmod(idx, count)


## 获取指定武器槽位对应的 Spine 皮肤名。
static func get_weapon_skin(idx: int) -> String:
	return WEAPON_SKINS[clamp_weapon_index(idx)]


## 获取指定服饰套装对应的 Spine 皮肤名。
static func get_outfit_skin(idx: int) -> String:
	return OUTFIT_SKINS[clamp_outfit_index(idx)]
#endregion
