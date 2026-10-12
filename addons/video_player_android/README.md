# Android Native Video Player Plugin (ExoPlayer)

本插件底座用于在 Android 导出时接管全屏视频播放，调用 Android 系统原生硬件加速解码器（Media3 ExoPlayer / MediaPlayer）。

## 特性
* **零发热、极省电**：芯片内置 VPU 硬解，不占用游戏 CPU/GPU 渲染循环；
* **零多余包体**：依赖系统自带库与 AndroidX Media3，无需在 APK 中打包 20MB+ 的 FFmpeg 二进制；
* **全格式兼容**：原生支持 Android 平台上所有受硬件认证的 H.264 / H.265 / VP9 视频；
* **Godot 4 官方规范**：提供标准的 `plugin.cfg`、`export_plugin.gd` 与 `.gdap` 插件描述。

## 目录结构
```text
addons/video_player_android/
├── plugin.cfg                  # Godot 插件配置
├── export_plugin.gd            # Godot 导出插件 (自动注册 .gdap 库)
├── godot_video_player.gdap     # Godot Android 插件清单
├── godot_video_player.aar      # 预打包 AAR 二进制库
├── src/                        # 完整原生源码
│   └── main/
│       ├── AndroidManifest.xml
│       └── java/org/godotengine/plugin/android/videoplayer/GodotVideoPlayer.java
└── README.md                   # 本文档
```

## 导出说明
在 Godot 导出 Android APK 时：
1. 打开 **Project -> Export...**，选择 Android 导出预设；
2. 勾选 **Use Gradle Build**；
3. 在 **Plugins** 列表中勾选 **GodotVideoPlayer**；
4. 导出后的 APK 运行时，Framework 的 `NativeMobileVideoAdapter` 会自动通过 `Engine.has_singleton("GodotVideoPlayer")` 建立硬件桥接，无缝播放 cutscene。
