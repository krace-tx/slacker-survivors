class_name SoulsSoundService
extends RefCounted

## 魂系演练场程序化物理建模音效与氛围音乐服务（位于 src/test/souls_arena/service/，遵循 MSVP 的 `Service` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 在初始化阶段基于 16-bit PCM 物理建模合成 11 种高辨识度魂系战斗音效（金铁振刀弹反、大盾沉闷格挡、巨剑破空挥砍、红光「危」字警报、架势崩裂、致命处决、战败丧钟、讨伐号角等）与深渊古战场低频氛围 BGM；[br]
## 2. 严格通过框架音频门面 `App.audio.play_sfx()` 与 `App.audio.play_bgm()` 调度播放（享受框架 16 通道空闲优先声道池与防爆限频保护）。


#region 采样率与缓存音频流

const MIX_RATE: int = 22050

var _sfx_parry_clang: AudioStreamWAV = null
var _sfx_shield_block: AudioStreamWAV = null
var _sfx_shield_raise: AudioStreamWAV = null
var _sfx_dodge_whoosh: AudioStreamWAV = null
var _sfx_iframe_evade: AudioStreamWAV = null
var _sfx_danger_warning: AudioStreamWAV = null
var _sfx_sword_swing: AudioStreamWAV = null
var _sfx_melee_hit: AudioStreamWAV = null
var _sfx_stagger_break: AudioStreamWAV = null
var _sfx_riposte_exec: AudioStreamWAV = null
var _sfx_lock_on: AudioStreamWAV = null
var _sfx_victory_fanfare: AudioStreamWAV = null
var _sfx_defeat_toll: AudioStreamWAV = null
var _bgm_abyss_drone: AudioStreamWAV = null

#endregion


#region 生命周期与初始化

func _init() -> void:
	_synthesize_all_streams()


func cleanup() -> void:
	if App != null and App.audio != null:
		App.audio.stop_all_sfx()
		App.audio.stop_bgm(0.0)

#endregion


#region 语义化音效触发接口 (通过 App.audio 门面播放)

## 启动深渊古战场低沉氛围背景音乐
func start_arena_bgm() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if App != null and App.audio != null and _bgm_abyss_drone != null:
		App.audio.play_bgm(_bgm_abyss_drone, -11.0, 0.8, true)


## 1. 完美弹反振刀金铁交鸣音 ("叮——嗡！")
func play_parry_clang() -> void:
	_play(_sfx_parry_clang, 1.5, randf_range(0.97, 1.04))


## 2. 举盾格挡沉闷铁盾撞击音 ("铛！")
func play_shield_block() -> void:
	_play(_sfx_shield_block, 0.5, randf_range(0.94, 1.05))


## 3. 举盾/振刀起手金属摩擦音
func play_shield_raise(is_boss: bool) -> void:
	_play(_sfx_shield_raise, -3.5, 0.85 if is_boss else 1.05)


## 4. 翻滚闪避衣袂破风音
func play_dodge_roll(is_boss: bool) -> void:
	_play(_sfx_dodge_whoosh, -1.5, 0.86 if is_boss else 1.04)


## 5. 无敌帧完美穿过刀光清脆共鸣音
func play_iframe_evade_chime() -> void:
	_play(_sfx_iframe_evade, 0.0, randf_range(0.98, 1.04))


## 6. Boss 红光「危」技不可防御警报音
func play_unblockable_danger_warning() -> void:
	_play(_sfx_danger_warning, 1.0, 1.0)


## 7. 刀剑挥砍破空音（Boss 巨剑低沉厚重，玩家长剑三段连击各有音高与重音辨识度）
func play_sword_swing(is_boss: bool, combo_step: int = 1) -> void:
	var base_pitch: float = 0.76 if is_boss else 1.12
	if is_boss:
		if combo_step == 2:
			base_pitch = 0.84
		elif combo_step >= 3:
			base_pitch = 0.66
	else:
		if combo_step == 2:
			base_pitch = 1.24
		elif combo_step >= 3:
			base_pitch = 0.88
	_play(_sfx_sword_swing, -0.5, base_pitch * randf_range(0.96, 1.04))


## 8. 利刃砍中铠甲与肉体沉重受击音
func play_melee_hit() -> void:
	_play(_sfx_melee_hit, 1.0, randf_range(0.93, 1.06))


## 8b. 砍中 Boss 黄金霸体时的沉重钢甲硬抗闷响（不打断动作）
func play_hyper_armor_tank() -> void:
	_play(_sfx_shield_block, 1.5, 0.72)


## 9. 架势槽归零崩溃破防重音
func play_posture_break() -> void:
	_play(_sfx_stagger_break, 2.0, 1.0)


## 10. 致命处决贯穿与震波音
func play_riposte_execution() -> void:
	_play(_sfx_riposte_exec, 2.5, 1.0)


## 11. 视角锁定切换提示音
func play_lock_on_toggle(locked: bool) -> void:
	_play(_sfx_lock_on, -2.0, 1.08 if locked else 0.86)


## 12. 薪王讨伐成功庄严和弦钟声
func play_victory_fanfare() -> void:
	_play(_sfx_victory_fanfare, 2.0, 1.0)


## 13. 灰烬陨落战败低沉丧钟
func play_defeat_toll() -> void:
	_play(_sfx_defeat_toll, 2.0, 1.0)


func _play(stream: AudioStreamWAV, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if stream == null or App == null or App.audio == null:
		return
	App.audio.play_sfx(stream, volume_db, pitch)

#endregion


#region 16-bit PCM 物理建模波形合成器

func _synthesize_all_streams() -> void:
	_sfx_parry_clang = _synth_parry_clang()
	_sfx_shield_block = _synth_shield_block()
	_sfx_shield_raise = _synth_shield_raise()
	_sfx_dodge_whoosh = _synth_dodge_whoosh()
	_sfx_iframe_evade = _synth_iframe_evade()
	_sfx_danger_warning = _synth_danger_warning()
	_sfx_sword_swing = _synth_sword_swing()
	_sfx_melee_hit = _synth_melee_hit()
	_sfx_stagger_break = _synth_stagger_break()
	_sfx_riposte_exec = _synth_riposte_exec()
	_sfx_lock_on = _synth_lock_on()
	_sfx_victory_fanfare = _synth_victory_fanfare()
	_sfx_defeat_toll = _synth_defeat_toll()
	_bgm_abyss_drone = _synth_abyss_bgm_drone()


## 合成完美弹反振刀音：非谐波高频钢刃泛音簇 + 瞬态金属撞击
func _synth_parry_clang() -> AudioStreamWAV:
	var duration := 0.52
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env_ring := exp(-t * 6.8)
		var env_ping := exp(-t * 28.0)
		var env_click := exp(-t * 140.0)
		var fm := sin(TAU * 420.0 * t) * 0.45 * env_ping
		var sig := (
			sin(TAU * 1380.0 * t + fm) * 0.36 * env_ring
			+ sin(TAU * 2190.0 * t) * 0.28 * env_ring
			+ sin(TAU * 3170.0 * t) * 0.20 * exp(-t * 9.5)
			+ sin(TAU * 4620.0 * t) * 0.14 * env_ping
			+ sin(TAU * 580.0 * t) * 0.25 * env_ping
			+ ( hash_noise(i) * 0.45 * env_click )
		)
		_write_sample16(pcm, i, sig * 0.92)
	return _pack_wav(pcm)


## 合成举盾格挡音：厚重黑铁盾低频闷响 + 中频金属震颤
func _synth_shield_block() -> AudioStreamWAV:
	var duration := 0.26
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env_thud := exp(-t * 22.0)
		var env_metal := exp(-t * 16.0)
		var env_noise := exp(-t * 55.0)
		var pitch_drop := 220.0 * exp(-t * 12.0) + 75.0
		var sig := (
			sin(TAU * pitch_drop * t) * 0.52 * env_thud
			+ sin(TAU * 640.0 * t) * 0.24 * env_metal
			+ sin(TAU * 980.0 * t) * 0.18 * env_metal
			+ hash_noise(i) * 0.35 * env_noise
		)
		_write_sample16(pcm, i, sig * 0.88)
	return _pack_wav(pcm)


## 合成举盾/振刀起手音
func _synth_shield_raise() -> AudioStreamWAV:
	var duration := 0.14
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env := sin(clampf(t / duration, 0.0, 1.0) * PI) * exp(-t * 10.0)
		var freq := lerpf(320.0, 680.0, t / duration)
		var sig := (sin(TAU * freq * t) * 0.35 + hash_noise(i) * 0.22) * env
		_write_sample16(pcm, i, sig * 0.65)
	return _pack_wav(pcm)


## 合成翻滚破风与铠甲摩擦音
func _synth_dodge_whoosh() -> AudioStreamWAV:
	var duration := 0.25
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	var lp_state := 0.0
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var ratio := t / duration
		var env := sin(ratio * PI) * exp(-t * 4.5)
		var raw_n := hash_noise(i)
		var cutoff := lerpf(0.08, 0.32, sin(ratio * PI))
		lp_state += cutoff * (raw_n - lp_state)
		var low_step := sin(TAU * (120.0 - 50.0 * ratio) * t) * 0.28 * exp(-t * 18.0)
		var sig := lp_state * 0.75 * env + low_step
		_write_sample16(pcm, i, sig * 0.80)
	return _pack_wav(pcm)


## 合成无敌帧完美闪避清脆幻影共鸣音
func _synth_iframe_evade() -> AudioStreamWAV:
	var duration := 0.30
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 11.0)
		var freq := lerpf(780.0, 1560.0, clampf(t / 0.18, 0.0, 1.0))
		var sig := (
			sin(TAU * freq * t) * 0.42
			+ sin(TAU * (freq * 1.5) * t) * 0.24
		) * env
		_write_sample16(pcm, i, sig * 0.78)
	return _pack_wav(pcm)


## 合成红光「危」技不可防御警报音（只狼风格不协和金属警音 + 低频压迫感）
func _synth_danger_warning() -> AudioStreamWAV:
	var duration := 0.44
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 6.2)
		var vibrato := sin(TAU * 18.0 * t) * 14.0
		var sig := (
			sin(TAU * (820.0 + vibrato) * t) * 0.36 * env
			+ sin(TAU * (1160.0 - vibrato) * t) * 0.30 * env
			+ sin(TAU * 195.0 * t) * 0.34 * exp(-t * 8.0)
		)
		_write_sample16(pcm, i, sig * 0.88)
	return _pack_wav(pcm)


## 合成刀剑破空挥砍音
func _synth_sword_swing() -> AudioStreamWAV:
	var duration := 0.22
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	var lp := 0.0
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var ratio := t / duration
		var env := sin(ratio * PI) * exp(-t * 6.5)
		var n := hash_noise(i)
		var alpha := lerpf(0.42, 0.08, ratio)
		lp += alpha * (n - lp)
		var blade_whistle := sin(TAU * lerpf(540.0, 180.0, ratio) * t) * 0.38 * env
		var sig := lp * 0.68 * env + blade_whistle
		_write_sample16(pcm, i, sig * 0.85)
	return _pack_wav(pcm)


## 合成利刃命中铠甲与肉体受击音
func _synth_melee_hit() -> AudioStreamWAV:
	var duration := 0.28
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env_punch := exp(-t * 20.0)
		var env_crunch := exp(-t * 36.0)
		var sub_freq := 145.0 * exp(-t * 16.0) + 42.0
		var sig := (
			sin(TAU * sub_freq * t) * 0.62 * env_punch
			+ sin(TAU * 410.0 * t) * 0.24 * env_crunch
			+ hash_noise(i) * 0.44 * env_crunch
		)
		_write_sample16(pcm, i, sig * 0.92)
	return _pack_wav(pcm)


## 合成架势槽崩溃破防巨响
func _synth_stagger_break() -> AudioStreamWAV:
	var duration := 0.56
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env_boom := exp(-t * 5.8)
		var env_shatter := exp(-t * 14.0)
		var drop_freq := 180.0 * exp(-t * 7.5) + 38.0
		var sig := (
			sin(TAU * drop_freq * t) * 0.58 * env_boom
			+ sin(TAU * 890.0 * t) * 0.24 * env_shatter
			+ sin(TAU * 1340.0 * t) * 0.18 * env_shatter
			+ hash_noise(i) * 0.30 * exp(-t * 25.0)
		)
		_write_sample16(pcm, i, sig * 0.92)
	return _pack_wav(pcm)


## 合成致命处决贯穿与重击爆裂音
func _synth_riposte_exec() -> AudioStreamWAV:
	var duration := 0.68
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 4.8)
		var sub := sin(TAU * (160.0 * exp(-t * 6.0) + 36.0) * t) * 0.56 * env
		var ring := (
			sin(TAU * 1120.0 * t) * 0.26
			+ sin(TAU * 1680.0 * t) * 0.20
		) * exp(-t * 7.5)
		var crunch := hash_noise(i) * 0.38 * exp(-t * 18.0)
		_write_sample16(pcm, i, (sub + ring + crunch) * 0.94)
	return _pack_wav(pcm)


## 合成视角锁定切换提示音
func _synth_lock_on() -> AudioStreamWAV:
	var duration := 0.11
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 32.0)
		var freq := 960.0 if t < 0.04 else 1320.0
		var sig := sin(TAU * freq * t) * 0.48 * env
		_write_sample16(pcm, i, sig * 0.72)
	return _pack_wav(pcm)


## 合成薪王讨伐成功庄严和弦钟声 (D Major Cathedral Swell)
func _synth_victory_fanfare() -> AudioStreamWAV:
	var duration := 1.15
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var attack := clampf(t / 0.08, 0.0, 1.0)
		var decay := exp(-t * 2.4)
		var env := attack * decay
		var sig := (
			sin(TAU * 293.66 * t) * 0.32
			+ sin(TAU * 369.99 * t) * 0.26
			+ sin(TAU * 440.00 * t) * 0.28
			+ sin(TAU * 587.33 * t) * 0.24
			+ sin(TAU * 880.00 * t) * 0.14 * exp(-t * 4.2)
		) * env
		_write_sample16(pcm, i, sig * 0.88)
	return _pack_wav(pcm)


## 合成灰烬陨落 (YOU DIED) 深渊丧钟音
func _synth_defeat_toll() -> AudioStreamWAV:
	var duration := 1.25
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		var env := exp(-t * 2.2)
		var sig := (
			sin(TAU * 110.0 * t) * 0.44
			+ sin(TAU * 220.0 * t) * 0.28
			+ sin(TAU * 261.63 * t) * 0.24
			+ sin(TAU * 518.0 * t) * 0.16 * exp(-t * 5.0)
		) * env
		_write_sample16(pcm, i, sig * 0.90)
	return _pack_wav(pcm)


## 合成深渊古战场低沉无缝循环氛围 BGM (3.6s 周期)
func _synth_abyss_bgm_drone() -> AudioStreamWAV:
	var duration := 3.60
	var samples := int(MIX_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(MIX_RATE)
		# 使用整数倍周期频率确保首尾相位严格连续无缝循环
		var lfo := 0.72 + 0.28 * sin(TAU * (t / duration))
		var sig := (
			sin(TAU * 73.333 * t) * 0.38
			+ sin(TAU * 110.000 * t) * 0.28
			+ sin(TAU * 146.667 * t) * 0.20
			+ sin(TAU * 220.000 * t) * 0.12
		) * lfo
		_write_sample16(pcm, i, sig * 0.55)
	return _pack_wav(pcm)


static func hash_noise(seed_idx: int) -> float:
	var n: int = (seed_idx << 13) ^ seed_idx
	var masked: int = (n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff
	return 1.0 - float(masked) / 1073741824.0


static func _write_sample16(buf: PackedByteArray, sample_idx: int, val: float) -> void:
	var clamped := clampf(val, -1.0, 1.0)
	var pcm_int := int(roundf(clamped * 32760.0))
	buf.encode_s16(sample_idx * 2, pcm_int)


static func _pack_wav(pcm_bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = pcm_bytes
	return stream

#endregion
