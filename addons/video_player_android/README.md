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
├── godot_video_player.aar      # 由 build_android.sh 生成的 AAR 二进制库
├── src/                        # 完整原生源码
│   └── main/
│       ├── AndroidManifest.xml
│       └── java/org/godotengine/plugin/android/videoplayer/GodotVideoPlayer.java
└── README.md                   # 本文档
```

## 构建与导出说明

> **默认已打包**：本仓库中已预置经过严格编译与验证的 `godot_video_player.aar`（内含包含完整字节码的 `classes.jar`、`AndroidManifest.xml` 及 `R.txt`），可直接用于导出，无需再次打包。

若修改了 Java 源码需重新构建，或需校验现有包的完整性：

```bash
# 校验现有 AAR 包完整性
./addons/video_player_android/build_android.sh --check

# 重新构建 AAR（支持 Gradle 或 JDK javac/jar 自动回退构建）
./addons/video_player_android/build_android.sh
```

构建脚本会自动验证 `classes.jar` 非空并包含 `GodotVideoPlayer.class`。

在 Godot 导出 Android APK 时：
1. 打开 **Project -> Export...**，选择 Android 导出预设；
2. 勾选 **Use Gradle Build**；
3. 在 **Plugins** 列表中勾选 **GodotVideoPlayer**；
4. 导出后的 APK 运行时，Framework 的 `NativeMobileVideoAdapter` 会自动通过 `Engine.has_singleton("GodotVideoPlayer")` 建立硬件桥接，无缝播放 cutscene。
