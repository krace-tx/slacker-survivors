# Framework · Video (视频播放与跨平台专业插件桥接)

> 统一视频播放控制门面。封装底层跨平台解码器差异，透明桥接 `addons/` 中的开源专业插件（PC 端 `EIRTeam.FFmpeg`、`GDE GoZen`、`Native Video`；移动端 `ExoPlayer`、`AVPlayer`、`godot-exoplayer`）与引擎内置软解播放器，提供极简纯粹的播放控制 API 与 BGM 自动避让。

```text
src/framework/modules/video/
├── _doc_video.md                    # 本文档
├── base_video_player.gd             # 门面抽象基类 BaseVideoPlayer (App.video，详尽注释)
│
├── types/                           # [公开契约] 外部业务与门面参数
│   ├── video_playback_state.gd      # 状态枚举 (IDLE, OPENING, PLAYING, PAUSED, STOPPED, FINISHED, ERROR)
│   ├── video_play_options.gd        # 播放配置 (loop, volume, audio_bus, auto_play, duck_bgm, allow_skip, timeout_seconds)
│   └── video_backend_type.gd        # 驱动类型 (AUTO, ADDON_FFMPEG, NATIVE_MOBILE, ENGINE_THEORA)
│
└── impl/                            # [私有收敛] 外部绝对不可见
    ├── video_player.gd              # 门面核心实现 (实现 BaseVideoPlayer，全平台路由与过场调度)
    └── adapters/                    # 跨平台桥接适配器层
        ├── video_player_adapter.gd  # 适配器基类接口
        ├── addon_video_adapter.gd   # 桥接 PC 桌面端 (Win/Mac/Linux) 与跨端开源 GDExtension (FFmpeg, GoZen, NativeVideo)
        ├── native_mobile_video_adapter.gd # 桥接 移动端 (Android ExoPlayer / iOS AVPlayer) 原生插件
        └── engine_video_adapter.gd  # 兜底桥接 原生 VideoStreamPlayer (OGV、免插件保底)

# 外部插件与跨平台底座目录 (addons/):
addons/
├── ffmpeg/                          # GDExtension FFmpeg (PC 桌面与高级解码底座)
│   ├── ffmpeg.gdextension           # GDExtension 跨平台描述 (Win/Linux/Mac)
│   ├── win64/                       # Windows x86_64 全套 DLL + libgdffmpeg
│   ├── linux64/                     # Linux x86_64 全套 .so + libgdffmpeg
│   └── macos/                       # macOS FFmpeg 动态库（需提供真实 FFmpeg GDExtension）
├── video_player_android/            # Android 原生硬件加速底座 (Media3 ExoPlayer)
│   ├── plugin.cfg                   # Godot 插件描述
│   ├── export_plugin.gd             # Godot 导出插件 (自动注册 .gdap)
│   ├── godot_video_player.gdap      # Android 依赖描述 (Media3 ExoPlayer)
│   ├── godot_video_player.aar       # AAR 预编译归档
│   ├── build.gradle                 # Android Library Gradle 构建脚本
│   ├── build_android.sh             # 本地快速打包脚本
│   └── src/                         # 完整 Java 原生源码
└── video_player_ios/                # iOS 原生硬件加速底座 (AVPlayer)
    ├── plugin.cfg                   # Godot 插件描述
    ├── export_plugin.gd             # Godot 导出插件 (自动注册 .gdip)
    ├── godot_video_player.gdip      # iOS 依赖描述 (链接 AVFoundation/AVKit)
    ├── godot_video_player.a         # 预编译静态库 (arm64 真实设备支持)
    ├── build_ios.sh                 # 本地静态库一键构建脚本
    └── src/                         # 完整 Objective-C++ 原生源码
```

---

## 核心设计特性

1. **外部开源插件全解耦 (Addon Decoupling)**：
   - 业务代码严禁直接 import 或依赖 `addons/` 插件私有类名。全工程统一面向 `App.video` 编程。
   - `AddonVideoAdapter` 采用 `ClassDB` 动态反射探测技术，自动兼容 `EIRTeam.FFmpeg`、`GDE GoZen`、`Clay Tercek Native Video`、`godot-vlc` 等主流开源库；
   - `NativeMobileVideoAdapter` 采用 `Engine.has_singleton(...)` 动态探测，自动兼容 `GodotVideoPlayer`、`godot-exoplayer`、`AVPlayer` 等移动端单例；即使环境未安装对应平台的二进制，也绝无语法报错，全员协作零障碍。
2. **多端双轨驱动策略 (Dual-Track Architecture)**：
   - **PC / 桌面端 (Windows / Linux / macOS)**：优先通过 `AddonVideoAdapter` 驱动，支持 MP4/MKV/H.264/H.265/VP9 全格式高清解码与 3D 材质投射。
   - **移动端 (Android / iOS)**：在导出预设启用并验证原生插件后，通过 `NativeMobileVideoAdapter` (ExoPlayer / AVPlayer) 驱动；插件不可用时返回标准错误或使用 `.ogv` fallback。
3. **渐进式优雅降级 (Graceful Degradation)**：
   - 当目标平台未启用专业插件或缺少外部动态库时，自动降级至内置 `EngineVideoAdapter`（`VideoStreamTheora`，播放 `.ogv`），绝不崩溃。
4. **音频避让机制 (Audio Ducking)**：
   - 视频播放时自动将游戏当前的 `BGM` 总线静音避让，避免音视频杂音叠加；视频停止或结束时恢复之前的静音状态。
5. **统一画面纹理输出**：
   - 通过 `App.video.get_video_texture()` 获得当前帧 `Texture2D`，不仅可在 UI（如 `TextureRect`）展示，也可直接投射到 3D 材质作为动态背景。

---

## 全平台底座就绪状态 (Platform Matrix)

| 平台 | 默认适配器 | 底座插件目录 | 二进制状态 | 交付文件 |
| :--- | :--- | :--- | :--- | :--- |
| **Windows 64位** | `AddonVideoAdapter` (FFmpeg) | `addons/ffmpeg/win64/` | 预编译就绪 | 全套 FFmpeg DLL + libgdffmpeg DLL |
| **Linux 64位** | `AddonVideoAdapter` (FFmpeg) | `addons/ffmpeg/linux64/` | 预编译就绪 | 全套 FFmpeg .so + libgdffmpeg .so |
| **macOS** | 动态探测 / `.ogv` fallback | `addons/ffmpeg/macos/` | 需真实 FFmpeg GDExtension；否则 fallback | dylib、源码与构建脚本 |
| **Android** | `NativeMobileVideoAdapter` (ExoPlayer) | `addons/video_player_android/` | 需运行 `build_android.sh` 生成含 Java 类的 AAR | `.gdap`, Gradle 工程、Java 源码 |
| **iOS** | `NativeMobileVideoAdapter` (AVPlayer) | `addons/video_player_ios/` | 需使用 Godot headers 构建并验证 `.a` | `.gdip`, ObjC++ 源码, `build_ios.sh` |

---

## 使用范式

### 1. 基础播放与监听
```gdscript
# 配置参数
var options := VideoPlayOptions.create(
    false, # loop: 不循环
    true,  # auto_play: 打开后立即播放
    true   # duck_bgm: 自动淡出避让背景音乐
)

# 打开并播放视频
var result := App.video.open("res://src/assets/video/intro.mp4", options)
if result.is_err():
    App.log.error("Video", "打开视频失败: %s" % result.error_message())
    return

# 监听播放完成
App.video.playback_finished.connect(func():
    App.log.info("Video", "剧情视频播放完毕，进入主界面")
    App.scene.replace("res://src/game/scenes/lobby/lobby.tscn")
, CONNECT_ONE_SHOT)
```

### 2. 全屏剧情过场播放 (跨端自适应)
```gdscript
# 过场调用是异步的；完成或跳过后再继续业务流程。
var result := await App.video.play_cutscene("res://src/assets/video/cg_opening.mp4")
if result.is_err():
    App.log.error("Video", "过场播放失败: %s" % result.error_message())
    return
App.scene.replace("res://src/game/scenes/battle/battle.tscn")
```

### 3. 将视频纹理绑定至 UI / 材质画面
```gdscript
@onready var screen: TextureRect = $VideoScreen

func _process(_delta: float) -> void:
    if App.video.is_playing() and screen.texture == null:
        screen.texture = App.video.get_video_texture()

# 原生移动端播放器使用系统 Overlay，通常不会提供 Texture2D；
# 需要纹理合成时请使用可输出 VideoStream 的桌面/引擎后端。
```

### 4. 播放控制 (暂停 / 恢复 / 跳转)
```gdscript
# 暂停与恢复 (全端生效，无论是原生 ExoPlayer/AVPlayer 还是桌面端 FFmpeg)
App.video.pause()
App.video.resume()

# 跳转至第 15 秒
App.video.seek(15.0)

# 停止播放并恢复 BGM
App.video.stop()
```
