class_name OtomeTerraceService
extends RefCounted

## 乙女向户外庭院「晴风湖畔 · 花树咖啡露台」领域服务。[br]
##
## [b]核心职责：[/b][br]
## 1. 管理 [OtomeTerraceState] 的穿搭/表情/手持道具组合、晴昼与落日星灯天气切换及心动值成长；[br]
## 2. 计算主角与三处户外交互热点的邻近触发关系，驱动热点入场特写与双分支心动对白；[br]
## 3. 合成温暖柔和的双音竖琴泛音与瓷杯风铃 16-bit PCM 音效，通过 [code]App.audio.play_sfx()[/code] 触发反馈。

#region Constants
const _LOG_TAG: String = "OtomeTerrace"
const _SAMPLE_RATE: int = 22050
#endregion

#region Public State & Private Audio Clips
var state: OtomeTerraceState = OtomeTerraceState.new()

var _greet_cursor: int = 0
var _sfx_chime_soft: AudioStreamWAV = null
var _sfx_heart_bloom: AudioStreamWAV = null
var _sfx_fabric_rustle: AudioStreamWAV = null
#endregion


#region Lifecycle
func _init() -> void:
	_sfx_chime_soft = _build_harp_chord_wav(523.25, 659.25, 0.22, 0.24)
	_sfx_heart_bloom = _build_harp_chord_wav(659.25, 987.77, 0.30, 0.28)
	_sfx_fabric_rustle = _build_harp_chord_wav(440.0, 587.33, 0.14, 0.20)
#endregion


#region Public Domain Operations
## 循环切换男主三套日常/咖啡师/风衣穿搭皮肤。
func cycle_outfit(step: int = 1) -> void:
	var count: int = OtomeTerraceConfig.OUTFIT_SKINS.size()
	state.outfit_index = posmod(state.outfit_index + step, count)
	state.status_badge_text = "换装 · %s" % OtomeTerraceConfig.OUTFIT_NAMES[state.outfit_index]
	_play_soft_sfx(_sfx_fabric_rustle, 1.0)
	if App.logger != null:
		App.logger.info(_LOG_TAG, "Switched outfit -> %s" % state.get_outfit_skin())
	state.notify_changed()


## 直接指定男主穿搭索引。
func select_outfit(index: int, silent: bool = false) -> void:
	var clamped: int = clampi(index, 0, OtomeTerraceConfig.OUTFIT_SKINS.size() - 1)
	if state.outfit_index == clamped:
		return
	state.outfit_index = clamped
	if not silent:
		_play_soft_sfx(_sfx_fabric_rustle, 1.02)
	state.notify_changed()


## 循环切换男主三套微表情皮肤（温柔浅笑 / 弯眼宠溺 / 微怔脸红）。
func cycle_expression(step: int = 1) -> void:
	var count: int = OtomeTerraceConfig.EXPR_SKINS.size()
	state.expr_index = posmod(state.expr_index + step, count)
	state.status_badge_text = "神态 · %s" % OtomeTerraceConfig.EXPR_NAMES[state.expr_index]
	_play_soft_sfx(_sfx_chime_soft, 1.06)
	state.notify_changed()


## 在「春昼晴风」与「落日星灯」两套户外光影天气预设间切换。
func toggle_weather_mode() -> int:
	state.weather_mode = (state.weather_mode + 1) % OtomeTerraceConfig.WEATHER_NAMES.size()
	state.status_badge_text = "天光 · %s" % OtomeTerraceConfig.WEATHER_NAMES[state.weather_mode]
	_play_soft_sfx(_sfx_chime_soft, 0.94)
	if App.logger != null:
		App.logger.info(_LOG_TAG, "Switched weather -> %s" % OtomeTerraceConfig.WEATHER_NAMES[state.weather_mode])
	state.notify_changed()
	return state.weather_mode


## 手动切换庭院漫游全景与男主半身特写镜头。
func toggle_closeup_camera() -> bool:
	state.is_closeup_camera = not state.is_closeup_camera
	if not state.is_closeup_camera and state.active_hotspot_id != OtomeTerraceConfig.HotspotId.NONE:
		state.active_hotspot_id = OtomeTerraceConfig.HotspotId.NONE
		state.prop_skin = "prop/none"
		state.choices_visible = false
	_play_soft_sfx(_sfx_chime_soft, 1.02)
	state.notify_changed()
	return state.is_closeup_camera


## 触发一次温柔挥手招呼互动，增加少量心动值并轮播问候语。
func trigger_greeting() -> void:
	var line_idx: int = _greet_cursor % OtomeTerraceConfig.GREET_LINES.size()
	_greet_cursor += 1
	state.active_hotspot_id = OtomeTerraceConfig.HotspotId.NONE
	state.prop_skin = "prop/none"
	state.expr_index = 1
	state.dialogue_visible = true
	state.dialogue_spot_tag = "温柔招呼"
	state.dialogue_body = OtomeTerraceConfig.GREET_LINES[line_idx]
	state.choices_visible = false
	state.status_badge_text = "互动 · 温柔挥手问候"
	_gain_affinity(8)
	_play_soft_sfx(_sfx_chime_soft, 1.08)
	state.notify_changed()


## 根据主角实时 3D 坐标计算最近的可交互热点（零开方距离检测）。
func update_proximity(actor_pos: Vector3) -> int:
	var best_id: int = OtomeTerraceConfig.HotspotId.NONE
	var best_dist_sq: float = OtomeTerraceConfig.HOTSPOT_TRIGGER_RADIUS * OtomeTerraceConfig.HOTSPOT_TRIGGER_RADIUS
	for i: int in range(OtomeTerraceConfig.HOTSPOT_STAND_POSITIONS.size()):
		var spot: Vector3 = OtomeTerraceConfig.HOTSPOT_STAND_POSITIONS[i]
		var dx: float = actor_pos.x - spot.x
		var dz: float = actor_pos.z - spot.z
		var d2: float = dx * dx + dz * dz
		if d2 <= best_dist_sq:
			best_dist_sq = d2
			best_id = i

	if state.nearby_hotspot_id != best_id:
		state.nearby_hotspot_id = best_id
		if state.active_hotspot_id == OtomeTerraceConfig.HotspotId.NONE:
			if best_id != OtomeTerraceConfig.HotspotId.NONE:
				state.status_badge_text = "靠近热点 · %s" % OtomeTerraceConfig.HOTSPOT_TITLES[best_id]
			else:
				state.status_badge_text = "漫步庭院 · 轻点地面或按 WASD 走近他"
		state.notify_changed()
	return best_id


## 进入指定户外热点的专属浪漫互动（自动匹配手持道具、推荐穿搭、近景推镜与双选项心动对话）。
func begin_hotspot_interaction(hotspot_id: int) -> bool:
	if hotspot_id < 0 or hotspot_id >= OtomeTerraceConfig.HOTSPOT_TITLES.size():
		return false

	state.active_hotspot_id = hotspot_id
	state.nearby_hotspot_id = hotspot_id
	state.is_closeup_camera = true
	state.outfit_index = OtomeTerraceConfig.HOTSPOT_PREFERRED_OUTFITS[hotspot_id]
	state.expr_index = 0
	state.prop_skin = OtomeTerraceConfig.HOTSPOT_PROPS[hotspot_id]
	state.dialogue_visible = true
	state.dialogue_spot_tag = OtomeTerraceConfig.HOTSPOT_TITLES[hotspot_id]
	state.dialogue_body = OtomeTerraceConfig.HOTSPOT_OPENING_LINES[hotspot_id]
	state.choice_a_text = OtomeTerraceConfig.HOTSPOT_CHOICE_A_LABELS[hotspot_id]
	state.choice_b_text = OtomeTerraceConfig.HOTSPOT_CHOICE_B_LABELS[hotspot_id]
	state.choices_visible = true
	state.status_badge_text = "甜蜜互动 · %s" % OtomeTerraceConfig.HOTSPOT_TITLES[hotspot_id]
	_gain_affinity(10)
	_play_soft_sfx(_sfx_heart_bloom, 1.0)
	if App.logger != null:
		App.logger.info(_LOG_TAG, "Entered hotspot interaction -> %s" % OtomeTerraceConfig.HOTSPOT_TITLES[hotspot_id])
	state.notify_changed()
	return true


## 选择底部浪漫对话分支（`choice_index`: `0` 选项 A，`1` 选项 B），更新男主微表情反应与心动等级。
func choose_dialogue_option(choice_index: int) -> void:
	var spot_id: int = state.active_hotspot_id
	if spot_id < 0 or spot_id >= OtomeTerraceConfig.HOTSPOT_TITLES.size():
		return

	if choice_index == 0:
		state.dialogue_body = OtomeTerraceConfig.HOTSPOT_REPLY_A_LINES[spot_id]
		state.expr_index = OtomeTerraceConfig.HOTSPOT_REPLY_A_EXPR[spot_id]
		_gain_affinity(OtomeTerraceConfig.HOTSPOT_AFFINITY_A[spot_id])
	else:
		state.dialogue_body = OtomeTerraceConfig.HOTSPOT_REPLY_B_LINES[spot_id]
		state.expr_index = OtomeTerraceConfig.HOTSPOT_REPLY_B_EXPR[spot_id]
		_gain_affinity(OtomeTerraceConfig.HOTSPOT_AFFINITY_B[spot_id])

	state.choices_visible = false
	state.status_badge_text = "心动回响 · %s" % OtomeTerraceConfig.EXPR_NAMES[state.expr_index]
	_play_soft_sfx(_sfx_heart_bloom, 1.10)
	state.notify_changed()


## 当玩家主动走开时退出当前热点特写并收起手持道具。
func exit_hotspot_interaction_if_active() -> void:
	if state.active_hotspot_id == OtomeTerraceConfig.HotspotId.NONE and not state.is_closeup_camera:
		return
	state.active_hotspot_id = OtomeTerraceConfig.HotspotId.NONE
	state.is_closeup_camera = false
	state.prop_skin = "prop/none"
	state.choices_visible = false
	state.status_badge_text = "漫步庭院 · 春风轻拂"
	state.notify_changed()
#endregion


#region Internal Affinity & Audio Helpers
func _gain_affinity(amount: int) -> void:
	state.affinity_points += maxi(0, amount)
	while state.affinity_points >= state.affinity_max:
		state.affinity_points -= state.affinity_max
		state.affinity_level += 1


func _play_soft_sfx(stream: AudioStreamWAV, pitch: float) -> void:
	if App.audio != null and stream != null:
		App.audio.play_sfx(stream, -7.5, pitch)
	if App.haptic != null:
		App.haptic.light()


func _build_harp_chord_wav(f1: float, f2: float, duration_sec: float, amp: float) -> AudioStreamWAV:
	var sample_count: int = maxi(128, int(duration_sec * float(_SAMPLE_RATE)))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var p1: float = 0.0
	var p2: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / float(sample_count)
		p1 += TAU * f1 / float(_SAMPLE_RATE)
		p2 += TAU * f2 / float(_SAMPLE_RATE)
		var attack: float = clampf(t / 0.06, 0.0, 1.0)
		var decay: float = pow(1.0 - t, 1.85)
		var second_entry: float = clampf((t - 0.14) / 0.08, 0.0, 1.0)
		var sample: float = (sin(p1) * 0.62 + sin(p2) * 0.48 * second_entry) * amp * attack * decay
		var s16: int = clampi(int(sample * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, s16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	return wav
#endregion
