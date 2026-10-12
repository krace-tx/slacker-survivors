# Linux 64-bit (x86_64) FFmpeg GDExtension Plugin

本目录包含适用于 Linux 64 位（x86_64）平台的 EIRTeam.FFmpeg GDExtension 插件及全套 FFmpeg 运行时动态库。

## 文件构成

| 文件名 | 职责说明 |
| :--- | :--- |
| `libgdffmpeg.linux.template_debug.x86_64.so` | GDExtension 桥接动态库（Debug 模板） |
| `libgdffmpeg.linux.template_release.x86_64.so` | GDExtension 桥接动态库（Release 模板，优化发行） |
| `libavcodec.so.60` | FFmpeg 核心音视频解码动态库（支持 H.264, HEVC, VP9, AV1 等） |
| `libavformat.so.60` | FFmpeg 媒体容器解封装动态库（支持 MP4, MKV, MOV, WebM 等） |
| `libavutil.so.58` | FFmpeg 基础计算与工具库 |
| `libswresample.so.4` | FFmpeg 音频重采样库 |
| `libswscale.so.7` | FFmpeg 图像格式与色彩空间转换库（YUV 到 RGB 硬件纹理映射） |
| `libavfilter.so.9` | FFmpeg 滤镜处理库 |

## 运行与导出规范

1. **系统兼容性**：
   - 支持主流 64 位 Linux 发行版（Ubuntu 20.04+, Debian 11+, Fedora, Arch Linux 等）。
   - 依赖标准 `glibc` 运行时。
2. **编辑器预览**：
   - `ffmpeg.gdextension` 中已配置 `linux.editor.x86_64`，在 Linux 系统的 Godot 编辑器内可直接载入并预览 MP4 视频。
3. **游戏导出 (Export)**：
   - 本工程的 `addons/ffmpeg/export_plugin.gd` 插件在导出 Linux 可执行文件时，会自动将全部 6 个依赖 `.so` 以及对应版本的 `libgdffmpeg` 动态库输出至与可执行文件同级的输出目录下。
   - 杜绝运行时出现 `error while loading shared libraries: libavcodec.so.60: cannot open shared object file: No such file or directory`。

## 本地重新编译（可选）

如需在 Linux 系统本地从源码重新编译：
```bash
# 1. 安装编译工具与依赖
sudo apt update && sudo apt install -y build-essential scons git yasm nasm autoconf automake libtool

# 2. 拉取源码
git clone --recursive https://github.com/EIRTeam/EIRTeam.FFmpeg.git /tmp/ffmpeg-build
cd /tmp/ffmpeg-build

# 3. 执行编译
make bootstrap
make gdextension PLATFORM=linux TARGET_ARCH=x86_64
```
产物将输出至 `gdextension_build/build/addons/ffmpeg/linux64/`。
