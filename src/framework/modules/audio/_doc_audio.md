# Framework · Audio

> 统一音频能力门面。封装同步热路径播放、BGM 双通道交叉淡入淡出（Cross-Fade）、无损循环控制、正交音画避让（Audio Ducking）与 SFX 16 通道智能声道池。

```text
src/framework/modules/audio/
├── _doc_audio.md               # 本文档
├── base_audio_system.gd        # 公开门面契约 BaseAudioSystem (App.audio)
└── impl/                       # 私有实现收敛
    ├── audio_system.gd         # 门面实现：零协程缓存热路径、版本化切歌守卫、正交 duck_bgm、同音限频
    ├── bgm_player.gd           # 双播放器交叉淡变、无损 finished 信号循环、暂停态 Tween 同步冻结
    └── sfx_pool.gd             # 16 通道空闲优先 (Idle-First) + 最老声道抢占 (Oldest-Stealing) 对象池
```

---

## 一、核心设计特性

1. **统一双态入口与零协程同步热路径**：
   - `play_bgm(source, volume, fade, loop)` 与 `play_sfx(source, volume, pitch_scale)` 同时支持传入 `res://` 路径字符串或已加载的 `AudioStream` 实例（保留 `play_bgm_by_path` / `play_sfx_by_path` 兼容别名）。
   - 主入口函数不含 `await`，当传入 `AudioStream` 或路径已命中 [`App.asset.get_cached()`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/modules/asset/base_asset_system.gd) 时，**零协程状态机分配、零帧延迟当场播放**；仅在首次冷加载未命中时转入内部异步加载慢路径。
2. **无损循环控制与异步切歌竞态守卫**：
   - `BgmPlayer` 通过监听播放器自身的 `finished` 信号实现循环重播，**绝不篡改共享 `AudioStream` 资源的 `.loop` 属性**，兼容全部音频流类型并支持非循环曲目（`loop = false`）。
   - `AudioSystem` 通过单调递增的 `_bgm_request_id` 拦截异步加载期间过期的切歌或停止指令，杜绝快速切换场景时的背景音乐串音覆盖。
3. **正交音画避让（`duck_bgm` / `unduck_bgm`）**：
   - 内部将**用户设定音量（`_user_bus_volumes`）**与**系统避让衰减系数（`_bgm_duck_scale`）**正交分离（物理音量 = `user_volume * duck_scale`）。
   - 视频或语音避让期间，`get_bus_volume("BGM")` 始终返回真实的用户设定音量，彻底杜绝避让态下打开设置或保存存档导致玩家音量被覆写为 `0.0` 的隐患。
4. **SFX 16 通道智能声道池与防爆限频**：
   - `SfxPool` 采用 **空闲通道优先（Idle-First）+ 最早播放抢占（Oldest-Active Stealing）** 策略，确保池中有空闲通道时绝不打断正在播放的长音效。
   - 支持 `pitch_scale` 音高倍率微调、`stop_all_sfx()` 退场清场、静音态零 I/O 短路及 30ms 同音防爆音限频。

---

## 二、使用范式

```gdscript
# 1. 播放 BGM（支持传入路径或 AudioStream，支持 fade 秒数与 loop 控制）
App.audio.play_bgm("res://src/assets/audio/bgm/lobby/bgm_lobby_main_loop.ogg", 0.0, 1.0, true)

# 2. 播放 SFX（已缓存音效零协程当场瞬发，支持随机微调音高防听觉疲劳）
App.audio.play_sfx("res://src/assets/audio/sfx/shared/sfx_shared_ui_click_01.wav", 0.0, randf_range(0.95, 1.05))

# 3. 过场视频或语音期间压低与恢复 BGM（正交避让，不污染用户音量设置）
App.audio.duck_bgm(0.2, 0.4)
App.audio.unduck_bgm(0.4)

# 4. 退场时停止所有残留音效或全局暂停
App.audio.stop_all_sfx()
App.audio.set_paused(true)
```
