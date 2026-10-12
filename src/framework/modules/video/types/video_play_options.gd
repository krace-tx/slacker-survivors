class_name VideoPlayOptions
extends BaseParams

## 视频播放参数配置契约实体（Video Play Options Entity）。[br]
##
## 继承自框架通用参数基类 [BaseParams]，原生具备强类型属性声明与 Dictionary 自动双向映射。[br]
## 采用现代 Fluent Builder（流式链式调用）设计模式，彻底抛弃旧式多参构造与静态重载。[br]
##
## [b]现代化调用范式：[/b][br]
## [codeblock]
## # 1. 现代流式链式构建 (推荐)
## var opts := VideoPlayOptions.new() \
##     .with_loop(false) \
##     .with_duck_bgm(true, 0.5) \
##     .with_skip(true, 3.0) \
##     .with_volume(0.8)
##
## # 2. 通过 Dictionary 字典无缝实例化 (适合网络下发、配置表或跨场景路由)
## var opts := VideoPlayOptions.new({
##     "loop": false,
##     "duck_bgm": true,
##     "allow_skip": true,
##     "min_watch_seconds": 3.0,
##     "volume": 0.8
## })
## [/codeblock]

## 是否循环播放视频。默认为 false。
var loop: bool = false

## 线性音量标量（0.0 表示静音，1.0 表示原声音量）。默认为 1.0。
var volume: float = 1.0

## 视频绑定的 Godot 音频总线名称。默认为 "Master"。
var audio_bus: StringName = &"Master"

## 加载并打开成功后是否立即自动开始解码播放。默认为 true。
var auto_play: bool = true

## 初始播放偏移位置（秒）。默认为 0.0。
var start_position: float = 0.0

## 播放视频期间是否自动淡出避让游戏背景音乐（Audio Ducking）。默认为 true。
var duck_bgm: bool = true

## 避让 BGM 时的淡出与恢复淡入过渡秒数。默认为 0.5 秒。
var duck_fade_seconds: float = 0.5

## 播放速率缩放倍率（0.5x, 1.0x, 2.0x 等）。默认为 1.0。
var speed_scale: float = 1.0

## 是否允许玩家在全屏过场模式下点击屏幕或跳过按钮退出。默认为 true。
var allow_skip: bool = true

## 强制观看最短秒数（在此秒数之前跳过按钮保持隐藏；0.0 表示无限制随时可跳）。默认为 0.0。
var min_watch_seconds: float = 0.0

## 原生全屏播放器等待完成的最长超时秒数（防原生异常回调丢失导致协程永久阻塞）。默认为 300.0 秒。
var timeout_seconds: float = 300.0


## 构造函数：支持直接传入 Dictionary 快速实例化并自动反射填充字段
func _init(dict: Dictionary = {}) -> void:
	super(dict)


#region Fluent Builder API
## 链式配置：是否循环播放
func with_loop(p_loop: bool) -> VideoPlayOptions:
	loop = p_loop
	return self


## 链式配置：线性音量 (0.0 ~ 1.0)
func with_volume(p_volume: float) -> VideoPlayOptions:
	volume = clampf(p_volume, 0.0, 1.0)
	return self


## 链式配置：是否自动播放
func with_auto_play(p_auto_play: bool) -> VideoPlayOptions:
	auto_play = p_auto_play
	return self


## 链式配置：音频避让机制与淡变时长
func with_duck_bgm(p_duck_bgm: bool, p_fade_seconds: float = 0.5) -> VideoPlayOptions:
	duck_bgm = p_duck_bgm
	duck_fade_seconds = maxf(0.0, p_fade_seconds)
	return self


## 链式配置：过场跳过权限与保底观看时长
func with_skip(p_allow_skip: bool, p_min_watch_seconds: float = 0.0) -> VideoPlayOptions:
	allow_skip = p_allow_skip
	min_watch_seconds = maxf(0.0, p_min_watch_seconds)
	return self


## 链式配置：音频输出总线
func with_audio_bus(p_bus: StringName) -> VideoPlayOptions:
	audio_bus = p_bus
	return self


## 链式配置：播放速度缩放倍率
func with_speed(p_speed: float) -> VideoPlayOptions:
	speed_scale = maxf(0.01, p_speed)
	return self


## 链式配置：初始起始时间偏移（秒）
func with_start_position(p_seconds: float) -> VideoPlayOptions:
	start_position = maxf(0.0, p_seconds)
	return self


## 链式配置：最大等待超时秒数
func with_timeout(p_timeout: float) -> VideoPlayOptions:
	timeout_seconds = maxf(0.0, p_timeout)
	return self
#endregion
