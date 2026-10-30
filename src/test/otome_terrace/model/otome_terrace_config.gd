class_name OtomeTerraceConfig
extends RefCounted

## 乙女向户外庭院「晴风湖畔 · 花树咖啡露台」静态配置与剧情台词表（纯数据层，无节点引用）。[br]
##
## [b]坐标契约（Blender `+Z Up` -> Godot `+Y Up`）：[/b][br]
## - 主角出生点：[code]Vector3(-1.15, 0.02, 1.15)[/code]（石板步道南侧）；[br]
## - 热点 0「樱树诗集长椅」：站立交互点 [code]Vector3(-2.12, 0.02, -0.22)[/code]，气泡锚点 [code]Vector3(-2.68, 1.52, -0.68)[/code]；[br]
## - 热点 1「露天手冲咖啡车」：站立交互点 [code]Vector3(0.55, 0.16, -2.15)[/code]（雪松木甲板 `y = 0.16`），气泡锚点 [code]Vector3(0.12, 1.98, -2.95)[/code]；[br]
## - 热点 2「湖畔喷泉栏杆」：站立交互点 [code]Vector3(2.12, 0.02, 0.32)[/code]，气泡锚点 [code]Vector3(3.15, 1.65, 0.28)[/code]。

#region Enums
enum WeatherMode {
	BREEZE_DAY = 0,
	SUNSET_LIGHTS = 1,
}

enum HotspotId {
	NONE = -1,
	BLOSSOM_BENCH = 0,
	COFFEE_CART = 1,
	LAKESIDE_FOUNTAIN = 2,
}
#endregion

#region Asset Paths & Spatial Constants
const STAGE_MODEL_PATH: String = "res://src/test/otome_terrace/assets/models/mdl_otome_terrace_stage.glb"
const HERO_SPINE_DATA_PATH: String = "res://src/test/otome_terrace/assets/spines/spn_otome_terrace_hero_data.tres"
const BUST_SPINE_DATA_PATH: String = "res://src/test/otome_terrace/assets/spines/spn_otome_terrace_bust_data.tres"
const ACTOR_STANDEE_SHADER_PATH: String = "res://src/test/otome_terrace/assets/shaders/shd_otome_actor_standee.gdshader"
const LAKE_SHADER_PATH: String = "res://src/test/otome_terrace/assets/shaders/shd_otome_terrace_lake.gdshader"
const RING_SHADER_PATH: String = "res://src/test/otome_terrace/assets/shaders/shd_otome_terrace_ring.gdshader"

const HERO_NAME: String = "陆星野"
const HERO_TITLE: String = "晴风湖畔 · 露天花树主理人"

const HERO_SPAWN_POS: Vector3 = Vector3(-1.15, 0.02, 1.15)
const WALK_SPEED: float = 2.85
const MOVE_ACCEL: float = 16.0
const GRAVITY: float = 22.0
const AUTO_WALK_STOP_DIST: float = 0.16
const HOTSPOT_TRIGGER_RADIUS: float = 1.48

const TERRACE_MIN_X: float = -4.85
const TERRACE_MAX_X: float = 4.85
const TERRACE_MIN_Z: float = -4.25
const TERRACE_MAX_Z: float = 3.85

const LAMPPOST_LIGHT_POSITIONS: Array[Vector3] = [
	Vector3(-4.55, 2.92, 0.95),
	Vector3(-1.42, 3.08, -3.28),
	Vector3(1.05, 3.08, -4.35),
	Vector3(3.36, 3.08, -2.18),
]
#endregion

#region Skin Tables
const OUTFIT_SKINS: Array[String] = [
	"outfit/cardigan",
	"outfit/barista",
	"outfit/trench",
]

const OUTFIT_NAMES: Array[String] = [
	"晨光粗针开衫",
	"可可咖啡围裙",
	"暮色迎风风衣",
]

const EXPR_SKINS: Array[String] = [
	"expr/gentle",
	"expr/happy",
	"expr/blush",
]

const EXPR_NAMES: Array[String] = [
	"温柔浅笑",
	"弯眼宠溺",
	"微怔脸红",
]

const BUST_EXPR_ANIMS: Array[String] = [
	"gentle_idle",
	"happy_talk",
	"shy_blush",
]

const PROP_SKINS: Array[String] = [
	"prop/none",
	"prop/coffee_cup",
	"prop/poetry_book",
	"prop/flower_sprig",
]

const WEATHER_NAMES: Array[String] = [
	"☀ 春昼晴风",
	"🌅 落日星灯",
]
#endregion

#region Hotspot Definitions & Romantic Dialogue Data
const HOTSPOT_TITLES: Array[String] = [
	"樱树诗集长椅",
	"露天手冲咖啡车",
	"湖畔喷泉栏杆",
]

const HOTSPOT_BUBBLE_TEXTS: Array[String] = [
	"[E] 樱下共读诗集",
	"[E] 品尝手冲拿铁",
	"[E] 凭栏共赏湖风",
]

const HOTSPOT_STAND_POSITIONS: Array[Vector3] = [
	Vector3(-2.12, 0.02, -0.22),
	Vector3(0.55, 0.16, -2.15),
	Vector3(2.12, 0.02, 0.32),
]

const HOTSPOT_BUBBLE_ANCHORS: Array[Vector3] = [
	Vector3(-2.55, 1.52, -0.58),
	Vector3(0.18, 1.98, -2.85),
	Vector3(2.38, 1.56, 0.26),
]

const HOTSPOT_RING_POSITIONS: Array[Vector3] = [
	Vector3(-2.12, 0.035, -0.22),
	Vector3(0.55, 0.178, -2.15),
	Vector3(2.12, 0.035, 0.32),
]

const HOTSPOT_ANIMS: Array[String] = [
	"interact_book",
	"interact_coffee",
	"interact_breeze",
]

const HOTSPOT_PROPS: Array[String] = [
	"prop/poetry_book",
	"prop/coffee_cup",
	"prop/flower_sprig",
]

const HOTSPOT_PREFERRED_OUTFITS: Array[int] = [
	0,
	1,
	2,
]

const HOTSPOT_OPENING_LINES: Array[String] = [
	"「花瓣刚好落在这一页十四行诗上……要不要靠过来一点，和我一起读完最后两行？」",
	"「刚萃好的桂花燕麦拿铁，温度不烫口。我特意给你留了第一缕香气，尝尝看？」",
	"「湖面起风了，今天的水光很温柔。站在这里吹风的时候，我刚刚正好在想你。」",
]

const HOTSPOT_CHOICE_A_LABELS: Array[String] = [
	"靠近他肩侧轻声共读 (+18 ♥)",
	"捧起瓷杯抿一口夸赞 (+18 ♥)",
	"替他拂去发梢樱花瓣 (+20 ♥)",
]

const HOTSPOT_CHOICE_B_LABELS: Array[String] = [
	"调侃他藏了书签秘密 (+22 ♥)",
	"让他亲手喂第一口 (+24 ♥)",
	"并肩望向对岸远山 (+16 ♥)",
]

const HOTSPOT_REPLY_A_LINES: Array[String] = [
	"「你念慢一点……我好像有点听不清诗句，光顾着听你的呼吸声了。」",
	"「嘴角沾了一点奶泡——别动，这样就刚刚好，甜度比我预想的还要满分。」",
	"「……原来是花瓣？我还以为是你故意找借口摸我的头发。不过，随时欢迎。」",
]

const HOTSPOT_REPLY_B_LINES: Array[String] = [
	"「被你发现了……那枚压花书签，确实是从上个春天起就准备送给你的。」",
	"「这么会撒娇啊……好，小心一点，杯沿温热，我的心跳可能比咖啡更烫。」",
	"「不管晴天还是落日星灯亮起的时候，只要身边是你，这片湖畔就永远看不腻。」",
]

const HOTSPOT_REPLY_A_EXPR: Array[int] = [1, 1, 2]
const HOTSPOT_REPLY_B_EXPR: Array[int] = [2, 2, 1]
const HOTSPOT_AFFINITY_A: Array[int] = [18, 18, 20]
const HOTSPOT_AFFINITY_B: Array[int] = [22, 24, 16]

const GREET_LINES: Array[String] = [
	"「我在看你呢。慢点走，石板路边有露水，手给我也可以。」",
	"「今天的阳光落在你眼睛里，比湖面上的碎金还要好看。」",
	"「累了就去长椅或者露台坐会儿，你的专属特调随时都在保温。」",
]
#endregion


#region Helpers
## 估算指定平面位置对应的露台地面基准高度（木质咖啡甲板抬高 `0.16m`）。
static func estimate_ground_height(world_pos: Vector3) -> float:
	if world_pos.x >= -1.48 and world_pos.x <= 3.58 and world_pos.z >= -4.58 and world_pos.z <= -1.52:
		return 0.16
	return 0.02
#endregion
