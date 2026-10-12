# Windows 64-bit FFmpeg GDExtension Plugin

本目录包含适用于 Windows 64 位（x86_64）平台的 EIRTeam.FFmpeg GDExtension 二进制及全套 FFmpeg 运行时动态库。

## 文件构成

| 文件名 | 职责说明 |
| :--- | :--- |
| `libgdffmpeg.windows.template_debug.x86_64.dll` | GDExtension 核心桥接库（Debug 模板，包含调试符号与更全日志） |
| `libgdffmpeg.windows.template_release.x86_64.dll` | GDExtension 核心桥接库（Release 模板，高优化生产运行） |
| `avcodec-60.dll` | FFmpeg 核心音视频解码库（支持 H.264, HEVC, VP9, AV1 等） |
| `avformat-60.dll` | FFmpeg 媒体容器解封装库（支持 MP4, MKV, MOV, WebM, FLV 等） |
| `avutil-58.dll` | FFmpeg 通用基础计算工具库 |
| `swresample-4.dll` | FFmpeg 音频重采样库 |
| `swscale-7.dll` | FFmpeg 图像格式与色彩空间转换库（YUV420P 到 RGB 硬件纹理转换） |
| `avfilter-9.dll` | FFmpeg 滤镜处理库 |

## 运行与导出规范

1. **环境依赖**：
   - 客户端 Windows 系统需要安装 **Microsoft Visual C++ 2015–2022 Redistributable (x64)**。
2. **编辑器预览**：
   - `ffmpeg.gdextension` 中已配置 `windows.editor.x86_64`，启动 Godot 编辑器即可自动载入并预览 MP4 视频。
3. **游戏导出 (Export)**：
   - 本插件配备 `addons/ffmpeg/export_plugin.gd` 导出插件，在导出 Windows 游戏时会自动将上述 DLL 复制到 `.exe` 的同级输出目录中。
   - 确保导出的可执行程序能够通过 Windows 默认的 DLL 寻址机制正常加载 FFmpeg 核心，杜绝 `Error 126 (Module not found)`。

## 本地重新编译（可选）

如需为 Windows 重新构建二进制，可在 Windows 设备上使用 SCons：
```cmd
git clone --recursive https://github.com/EIRTeam/EIRTeam.FFmpeg.git
cd EIRTeam.FFmpeg
scons platform=windows target=template_release
scons platform=windows target=template_debug
```
产物将输出至 `gdextension_build/build/addons/ffmpeg/win64/`。
