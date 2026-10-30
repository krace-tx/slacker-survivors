class_name SpineStageService
extends RefCounted

## 2.5D「方案 B」原型领域服务（负责换装状态流转、近战扇形命中裁决与程序化音效合成）。[br]
##
## [b]核心职责：[/b][br]
## 1. 管理 [SpineStageState] 武器、护甲套装与光影模式的切换规则；[br]
## 2. 基于零开方水平距离与朝向判定武器挥砍命中的木偶目标；[br]
## 3. 合成轻量 16-bit PCM [AudioStreamWAV] 声效并通过 [code]App.audio.play_sfx()[/code] 与 [code]App.haptic[/code] 触发清脆反馈。

#region Constants
const _LOG_TAG: String = "SpineStage"
const _SAMPLE_RATE: int = 22050
#endregion

#region Public Properties & Private State
var state: SpineStageState = SpineStageState.new()

var _sfx_equip: AudioStreamWAV = null
var _sfx_slash: AudioStreamWAV = null
var _sfx_hit: AudioStreamWAV = null
var _sfx_jump: AudioStreamWAV = null
#endregion


#region Lifecycle
func _init() -> void:
	_sfx_equip = _build_tone_wav(680.0, 1020.0, 0.085, 0.28)
	_sfx_slash = _build_noise_sweep_wav(0.12, 0.26)
	_sfx_hit = _build_tone_wav(190.0, 72.0, 0.11, 0.42)
	_sfx_jump = _build_tone_wav(260.0, 520.0, 0.09, 0.24)
#endregion


#region Public API
## 切换指定槽位的武器皮肤。
func select_weapon(index: int, play_feedback: bool = true) -> bool:
	var clamped: int = SpineStageConfig.clamp_weapon_index(index)
	if state.weapon_index == clamped:
		return false
	state.weapon_index = clamped
	if play_feedback:
		_play_equip_feedback(1.04)
	App.logger.info(
		_LOG_TAG,
		"Switched weapon skin -> %s (%s)" % [
			SpineStageConfig.get_weapon_skin(clamped),
			SpineStageConfig.WEAPON_NAMES[clamped],
		]
	)
	state.notify_changed()
	return true


## 按步长循环切换武器皮肤。
func cycle_weapon(step: int) -> void:
	select_weapon(state.weapon_index + step, true)


## 切换指定槽位的服饰套装皮肤。
func select_outfit(index: int, play_feedback: bool = true) -> bool:
	var clamped: int = SpineStageConfig.clamp_outfit_index(index)
	if state.outfit_index == clamped:
		return false
	state.outfit_index = clamped
	if play_feedback:
		_play_equip_feedback(0.92)
	App.logger.info(
		_LOG_TAG,
		"Switched outfit skin -> %s (%s)" % [
			SpineStageConfig.get_outfit_skin(clamped),
			SpineStageConfig.OUTFIT_NAMES[clamped],
		]
	)
	state.notify_changed()
	return true


## 按步长循环切换服饰套装皮肤。
func cycle_outfit(step: int) -> void:
	select_outfit(state.outfit_index + step, true)


## 在「黄昏斜阳」与「幽蓝月夜火把」两套 3D 光影预设之间切换。
func toggle_lighting_mode() -> int:
	state.lighting_mode = (state.lighting_mode + 1) % SpineStageConfig.LIGHTING_NAMES.size()
	_play_equip_feedback(1.16)
	App.logger.info(
		_LOG_TAG,
		"Switched 3D lighting preset -> %s" % SpineStageConfig.LIGHTING_NAMES[state.lighting_mode]
	)
	state.notify_changed()
	return state.lighting_mode


## 获取当前穿戴套装计算后的主角 3D 地面移速。
func get_effective_move_speed() -> float:
	var mult: float = SpineStageConfig.OUTFIT_SPEED_MULTS[state.outfit_index]
	return SpineStageConfig.BASE_MOVE_SPEED * mult


## 播放起跳声效。
func notify_jump_triggered() -> void:
	if App.audio != null and _sfx_jump != null:
		App.audio.play_sfx(_sfx_jump, -5.0, randf_range(0.96, 1.05))


## 播放挥砍破空声效。
func notify_attack_started(combo_step: int) -> void:
	if App.audio != null and _sfx_slash != null:
		var pitch: float = 0.94 if combo_step == 1 else 1.12
		App.audio.play_sfx(_sfx_slash, -4.0, pitch)


## 更新主角动作状态文案（仅在文案变化时广播）。
func update_action_label(label_text: String) -> void:
	if state.action_status_text == label_text:
		return
	state.action_status_text = label_text
	state.notify_changed()


## 裁决主角一次近战挥砍命中的目标木偶下标列表，并累加连击与伤害统计。
func evaluate_melee_hits(
	attacker_pos: Vector3,
	facing_right: bool,
	dummy_positions: Array[Vector3],
	combo_step: int
) -> Array[int]:
	var hit_indices: Array[int] = []
	var reach: float = SpineStageConfig.WEAPON_REACHES[state.weapon_index]
	var reach_sq: float = reach * reach
	var base_dmg: int = SpineStageConfig.WEAPON_DAMAGES[state.weapon_index]
	var dmg: int = int(round(float(base_dmg) * (1.22 if combo_step >= 2 else 1.0)))
	var dir_sign: float = 1.0 if facing_right else -1.0

	for i: int in range(dummy_positions.size()):
		var target_pos: Vector3 = dummy_positions[i]
		var dx: float = target_pos.x - attacker_pos.x
		var dz: float = target_pos.z - attacker_pos.z
		var dist_sq: float = dx * dx + dz * dz
		if dist_sq > reach_sq:
			continue
		if dx * dir_sign < -0.45 or absf(dz) > 1.55:
			continue
		hit_indices.append(i)
		state.combo_hits += 1
		state.total_damage += dmg

	if not hit_indices.is_empty():
		if App.audio != null and _sfx_hit != null:
			App.audio.play_sfx(_sfx_hit, -2.5, randf_range(0.92, 1.08))
		if App.haptic != null:
			App.haptic.medium()
		state.notify_changed()

	return hit_indices
#endregion


#region Internal Audio Synthesis Helpers
func _play_equip_feedback(pitch: float) -> void:
	if App.audio != null and _sfx_equip != null:
		App.audio.play_sfx(_sfx_equip, -5.5, pitch)
	if App.haptic != null:
		App.haptic.light()


func _build_tone_wav(freq_start: float, freq_end: float, duration_sec: float, amp: float) -> AudioStreamWAV:
	var sample_count: int = maxi(64, int(duration_sec * float(_SAMPLE_RATE)))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var freq: float = lerpf(freq_start, freq_end, t)
		phase += TAU * freq / float(_SAMPLE_RATE)
		var env: float = (1.0 - t) * (1.0 - t)
		var val: float = sin(phase) * amp * env
		var s16: int = clampi(int(val * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, s16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	return wav


func _build_noise_sweep_wav(duration_sec: float, amp: float) -> AudioStreamWAV:
	var sample_count: int = maxi(64, int(duration_sec * float(_SAMPLE_RATE)))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261030
	var lp: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var env: float = sin(t * PI) * (1.0 - 0.35 * t)
		var white: float = rng.randf_range(-1.0, 1.0)
		var cutoff: float = lerpf(0.55, 0.14, t)
		lp = lp + cutoff * (white - lp)
		var s16: int = clampi(int(lp * amp * env * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, s16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	return wav
#endregion
