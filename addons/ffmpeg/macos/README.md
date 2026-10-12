# macOS Universal (arm64 + x86_64) FFmpeg GDExtension

本目录包含适用于 macOS 平台的 EIRTeam.FFmpeg GDExtension 插件及全套 FFmpeg 运行时动态库。

## 文件构成

| 文件名 | 职责说明 |
| :--- | :--- |
| `libgdffmpeg.macos.template_debug.framework` | GDExtension 桥接 Framework（Debug 模板，通用双架构） |
| `libgdffmpeg.macos.template_release.framework` | GDExtension 桥接 Framework（Release 模板，通用双架构） |
| `libavcodec.dylib` | FFmpeg 核心音视频解码动态库（包含 H.264, HEVC, VP9, AV1 等） |
| `libavformat.dylib` | FFmpeg 媒体容器解封装动态库（包含 MP4, MKV, MOV 等） |
| `libavfilter.dylib` | FFmpeg 滤镜库 |
| `libavutil.dylib` | FFmpeg 基础工具库 |
| `libswresample.dylib` | FFmpeg 音频重采样库 |
| `libswscale.dylib` | FFmpeg 图像格式与色彩空间转换库 |

## 架构与兼容性

- **Universal 2 架构**：全部二进制均为 `Mach-O universal binary with 2 architectures: [arm64, x86_64]`，原生支持 Apple Silicon（M1/M2/M3/M4/M5 等芯片）与 Intel Mac；
- **动态链接寻址**：使用 `@loader_path/../` 相对路径寻址同级 FFmpeg 动态库，无需污染 `/usr/local/lib` 或安装系统级依赖；
- **签名与隔离清除**：已完成本地 Ad-hoc 代码签名，并清除了 macOS 隔离属性（Quarantine），杜绝安全拦截。

## 本地重新编译指南

在 macOS 设备上使用官方仓库一键编译：
```bash
# 1. 准备环境 (通过 Homebrew 安装构建工具)
brew install autoconf automake libtool pkg-config curl cmake gperf groff texinfo yasm nasm bison autogen git wget meson ninja guile

# 2. 拉取完整子模块并编译
git clone --recursive https://github.com/EIRTeam/EIRTeam.FFmpeg.git /tmp/ffmpeg-build
cd /tmp/ffmpeg-build
make bootstrap
make gdextension PLATFORM=macos

# 3. 将产物同步回本工程目录
cp -r gdextension_build/build/addons/ffmpeg/macos/* addons/ffmpeg/macos/
```
也可直接运行同级目录下的 `build_macos.sh` 脚本自动完成。
