# EIRTeam.FFmpeg · Godot 4 跨平台视频解码 GDExtension

本插件是基于开源项目 [EIRTeam.FFmpeg](https://github.com/EIRTeam/EIRTeam.FFmpeg) 针对 Godot 4+ 打造的高性能多媒体解码 GDExtension 插件。

为项目提供对 **MP4、MKV、MOV、WebM、AVI、FLV** 等主流视频格式的高清软解/硬解播放能力，彻底摆脱原生引擎仅支持 `.ogv`（Theora）格式且画质模糊的限制。

---

## 一、跨平台支持一览 (Platform Support)

| 目标平台 | 二进制架构 | 存放目录 | 状态 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| **Windows** | x86_64 (64位) | `addons/ffmpeg/win64/` | ✅ 就绪 | 预编译全套 FFmpeg DLL + 导出保护 |
| **macOS** | Universal (arm64 + x86_64) | `addons/ffmpeg/macos/` | ✅ 就绪 | 本地源码编译双架构 Framework + Dylib |
| **Linux** | x86_64 (64位) | `addons/ffmpeg/linux64/` | ✅ 就绪 | 预编译全套 FFmpeg .so + 导出保护 |
| **Android** | arm64 (可选) | `addons/ffmpeg/android/` | 💡 可选 | 移动端优先使用原生 `addons/video_player_android` (ExoPlayer) |

---

## 二、目录结构

```text
addons/ffmpeg/
├── ffmpeg.gdextension      # GDExtension 声明与全平台二进制/依赖映射
├── plugin.cfg              # Godot 编辑器插件元数据
├── export_plugin.gd        # 跨平台导出插件 (自动打包 Windows DLL 与 Linux .so)
├── README.md               # 本文档
│
├── win64/                  # Windows 64 位运行时
│   ├── README.md           # Windows 环境配置与依赖说明
│   ├── build_windows.bat   # Windows 本地重新编译脚本
│   ├── libgdffmpeg.windows.template_*.x86_64.dll
│   └── avcodec-60.dll / avformat-60.dll / avutil-58.dll 等
│
├── macos/                  # macOS 通用双架构运行时
│   ├── README.md           # macOS 构建与签名说明
│   ├── build_macos.sh      # macOS 本地重新编译脚本
│   ├── libgdffmpeg.macos.template_*.framework/
│   └── libavcodec.dylib / libavformat.dylib / libavutil.dylib 等
│
└── linux64/                # Linux 64 位运行时
    ├── README.md           # Linux 运行环境说明
    ├── build_linux.sh      # Linux 本地重新编译脚本
    ├── libgdffmpeg.linux.template_*.x86_64.so
    └── libavcodec.so.60 / libavformat.so.60 / libavutil.so.58 等
```

---

## 三、核心技术保障

### 1. 编辑器内即时预览与运行
在 `ffmpeg.gdextension` 中已全量声明各平台的 `editor` 映射：
- `windows.editor.x86_64`
- `macos.editor`
- `linux.editor.x86_64`

无论是打开 Godot 编辑器检查场景纹理，还是直接在编辑器内按 F5 启动，均可自动载入 GDExtension，无需先打包。

### 2. 自动化导出保护 (Zero-Config Export)
针对桌面端（Windows / Linux）发布可执行文件时依赖动态链接库同级放置的要求，本插件内置 `export_plugin.gd`：
- 在 Godot 导出 Windows 时，自动将 6 个核心 DLL 复制到 `.exe` 同级目录；
- 在 Godot 导出 Linux 时，自动将 6 个核心 `.so` 复制到可执行文件同级目录；
- 避免发布版本在玩家电脑上运行时报 `Error 126 (DLL not found)` 或 `cannot open shared object file`。

---

## 四、业务调用与接入规范

**严禁在游戏业务代码中直接硬编码或引用插件私有类名。**

业务层请统一通过框架模块 `App.video` 访问（详见 `src/framework/modules/video/_doc_video.md`）：

```gdscript
# 播放任意视频文件（全平台自适应选择最优解码器）
var result := App.video.open("res://src/assets/videos/intro.mp4")
if result.is_ok():
    App.video.play()
```

框架层的 `AddonVideoAdapter` 会通过反射动态探测 `FFmpegVideoStream` 类并自动挂载解码器，在未安装插件的环境下会自动优雅降级为引擎内置播放器，绝不崩溃。
