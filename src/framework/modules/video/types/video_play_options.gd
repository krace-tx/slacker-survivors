class_name VideoPlayOptions
extends RefCounted

## 视频播放参数配置对象。[br]
## 封装播放行为控制、循环规则、音视频总线路由与 BGM 避让策略。

## 是否循环播放视频。默认为 false。
var loop: bool = false

## 线性音量大小 (0.0 表示静音，1.0 表示原声音量)。默认为 1.0。
var volume: float = 1.0

## 视频绑定的 Godot 音频总线名称。默认为 "Master"。
var audio_bus: StringName = &"Master"

## 加载并打开成功后是否立即自动开始播放。默认为 true。
var auto_play: bool = true

## 初始播放偏移位置（秒）。默认为 0.0。
var start_position: float = 0.0

## 播放视频时是否自动避让/淡出游戏背景音乐（Audio Ducking）。默认为 true。
var duck_bgm: bool = true

## 避让 BGM 时的淡入/淡出过渡秒数。默认为 0.5 秒。
var duck_fade_seconds: float = 0.5

## 播放速率缩放倍率 (0.5x, 1.0x, 2.0x 等)。默认为 1.0。
var speed_scale: float = 1.0

## 是否允许玩家在全屏过场模式下点击/手势跳过。默认为 true。
var allow_skip: bool = true

## 强制观看最短秒数（在此之前不允许跳过，0.0 表示无限制随时可跳）。默认为 0.0。
var min_watch_seconds: float = 0.0

## 原生全屏播放器等待完成的最长秒数。小于等于 0 时使用门面默认值。
## 防止原生插件丢失完成/错误回调后永久阻塞过场协程。
var timeout_seconds: float = 300.0


## 快速构造配置实例的辅助静态工厂方法。
static func create(p_loop: bool = false, p_auto_play: bool = true, p_duck_bgm: bool = true) -> VideoPlayOptions:
	var options := VideoPlayOptions.new()
	options.loop = p_loop
	options.auto_play = p_auto_play
	options.duck_bgm = p_duck_bgm
	return options
