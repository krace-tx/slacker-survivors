# Framework · Audio

> 统一音频能力门面。封装 BGM 交叉淡入淡出（Cross-Fade）、SFX 播放器池与音频总线路由。

```text
src/framework/modules/audio/
├── _doc_audio.md               # 本文档
├── base_audio_system.gd        # 公开门面契约 BaseAudioSystem (App.audio，详尽注释)
└── impl/                       # 私有实现收敛
    ├── audio_system.gd         # 门面实现：资源加载、总线音量 / 静音、同音限频
    ├── bgm_player.gd           # 双播放器交叉淡变 + 强制循环
    └── sfx_pool.gd             # 固定数量 SFX 播放器轮转复用
```

---

## 核心设计特性

1. **BGM 平滑交叉淡变 (Cross-Fade)**：`BgmPlayer` 内置双播放器，新旧曲目并行淡入淡出，彻底告别切歌突兀切断。
2. **SFX 播放器池与限频**：`SfxPool` 固定大小对象池轮转复用；`AudioSystem` 做同音效高频防爆音门禁（默认 30ms 最小间隔）。
3. **总线分离与静音控制**：自动绑定 `Master`、`BGM`、`SFX` 音频总线，支持独立静音与音量调节。
4. **解耦业务音频**：支持 `default_button_sfx` 属性注入，解耦底层 UI 按钮对游戏资源的依赖。

---

## 使用范式

```gdscript
# 1. 播放 BGM (音量单位 dB，第三个参数为交叉淡变秒数)
App.audio.play_bgm_by_path("res://src/assets/audio/bgm_main.mp3", 0.0, 1.0)

# 2. 即发即弃播放 SFX 音效
App.audio.play_sfx_by_path("res://src/assets/audio/click.wav")

# 3. 暂停与恢复全部音频
App.audio.set_paused(true)
```
