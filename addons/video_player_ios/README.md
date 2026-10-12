# iOS Native Video Player Plugin (AVPlayer)

本插件底座用于在 iOS 导出时接管全屏视频播放，调用 Apple iOS 平台原生硬件加速解码框架（AVFoundation / AVKit）。

## 特性
* **零发热、极致流畅**：调用 Apple 芯片专属硬解通道，零 CPU 软解负担；
* **系统框架解码**：直接链接 iOS 系统内置 `AVFoundation.framework` 与 `AVKit.framework`，无需打包 FFmpeg 解码库；
* **原生 UI 控件**：内嵌 `AVPlayerViewController`，支持原生手势、跳过按钮与全屏响应；
* **Godot 4 官方规范**：提供标准的 `plugin.cfg`、`export_plugin.gd` 与 `.gdip` 插件描述。

## 目录结构
```text
addons/video_player_ios/
├── plugin.cfg                  # Godot 插件配置
├── export_plugin.gd            # Godot 导出插件 (自动注册 .gdip 插件)
├── godot_video_player.gdip     # Godot iOS 插件清单 (自动链接 AVFoundation/AVKit)
├── godot_video_player.a        # 预编译静态库 (arm64 真实设备支持)
├── build_ios.sh                # 本地编译脚本
├── src/                        # 完整原生源码
│   ├── GodotVideoPlayer.h
│   └── GodotVideoPlayer.mm
└── README.md                   # 本文档
```

## 导出与编译说明
1. 使用与 iOS 导出模板匹配的 Godot 源码头文件构建插件：
   ```bash
   GODOT_HEADERS=/path/to/godot ./addons/video_player_ios/build_ios.sh
   ```
   构建脚本会检查 `register_avplayer_types` 注册入口，并在失败时保留旧归档；
2. 在 Godot 导出 iOS Xcode 工程时：
   - 打开 **Project -> Export...**，选择 iOS 预设；
   - 勾选或启用 **AVPlayer** 插件；
   - 导出后生成的 Xcode 工程会自动包含 `godot_video_player.a` 并链接 `AVFoundation`、`AVKit` 与 `CoreMedia`；
3. 运行时，Framework 的 `NativeMobileVideoAdapter` 会自动检测 `Engine.has_singleton("AVPlayer")` 启动原生硬件全屏播放；
