class_name OtomeTerraceState
extends RefCounted

## 乙女向户外庭院「晴风湖畔 · 花树咖啡露台」响应式视图模型（ViewModel）。[br]
##
## 封装主角穿搭/神态/手持物皮肤索引、心动羁绊等级与进度、邻近热点、近景聚焦相机状态及底部浪漫对话卡数据。

#region Signals
## 当任意状态字段发生变化时广播，驱动 [OtomeHudPanel] 单向幂等刷新。
signal changed
#endregion

#region State Fields
var outfit_index: int = 0
var expr_index: int = 0
var prop_skin: String = "prop/none"
var weather_mode: int = OtomeTerraceConfig.WeatherMode.BREEZE_DAY

var affinity_level: int = 1
var affinity_points: int = 32
var affinity_max: int = 100

var nearby_hotspot_id: int = OtomeTerraceConfig.HotspotId.NONE
var active_hotspot_id: int = OtomeTerraceConfig.HotspotId.NONE
var is_closeup_camera: bool = false
var status_badge_text: String = "漫步庭院 · 轻点地面或按 WASD 走近他"

var dialogue_visible: bool = true
var dialogue_speaker: String = OtomeTerraceConfig.HERO_NAME
var dialogue_spot_tag: String = "晴风初遇"
var dialogue_body: String = "「你来啦。湖畔的风刚刚吹开第一批春樱——想先去树下读诗，还是来露台尝一杯手冲拿铁？」"
var choice_a_text: String = ""
var choice_b_text: String = ""
var choices_visible: bool = false
#endregion


#region Helpers
## 获取当前激活的服饰 Spine 皮肤名。
func get_outfit_skin() -> String:
	var idx: int = clampi(outfit_index, 0, OtomeTerraceConfig.OUTFIT_SKINS.size() - 1)
	return OtomeTerraceConfig.OUTFIT_SKINS[idx]


## 获取当前激活的表情 Spine 皮肤名。
func get_expr_skin() -> String:
	var idx: int = clampi(expr_index, 0, OtomeTerraceConfig.EXPR_SKINS.size() - 1)
	return OtomeTerraceConfig.EXPR_SKINS[idx]


## 广播状态更新信号。
func notify_changed() -> void:
	changed.emit()
#endregion
