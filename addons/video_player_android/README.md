# Android Native Video Player Plugin (ExoPlayer)

本插件底座用于在 Android 导出时接管全屏视频播放，调用 Android 系统原生硬件加速解码器（Media3 ExoPlayer / MediaPlayer）。

## 特性
* **零发热、极省电**：芯片内置 VPU 硬解，不占用游戏 CPU/GPU 渲染循环；
* **硬件优先**：通过 AndroidX Media3 ExoPlayer 使用平台硬件解码；Media3 依赖会由 Gradle 合并进 Android 导出包；
* **常见格式硬件加速**：优先使用 Android 设备支持的 H.264 / H.265 / VP9 编解码器，具体能力取决于设备；
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

## 构建与导出说明

`godot_video_player.aar` 必须由 Gradle 构建。`build_android.sh` 会拒绝空的
`classes.jar`，避免把只有 Manifest 的占位 AAR 带入导出包：

```bash
./addons/video_player_android/build_android.sh
```

构建完成后应能在 AAR 的 `classes.jar` 中找到
`org/godotengine/plugin/android/videoplayer/GodotVideoPlayer.class`。

在 Godot 导出 Android APK 时：
1. 打开 **Project -> Export...**，选择 Android 导出预设；
2. 勾选 **Use Gradle Build**；
3. 在 **Plugins** 列表中勾选 **GodotVideoPlayer**；
4. 导出后的 APK 运行时，Framework 的 `NativeMobileVideoAdapter` 会自动通过 `Engine.has_singleton("GodotVideoPlayer")` 建立硬件桥接，无缝播放 cutscene。
