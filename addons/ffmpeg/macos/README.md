# FFmpeg GDExtension for macOS

本目录已包含 macOS 通用二进制库（Universal Binary: Apple Silicon `arm64` + Intel `x86_64`）。

## 当前状态
- 已预置并编译 `libgdffmpeg.macos.dylib`（包含 Universal arm64 + x86_64 符号架构），并在 `ffmpeg.gdextension` 中完成映射。
- Godot 启动时可正常解析该 GDExtension 并建立扩展生命周期，引擎日志 0 错误。
- 当工程在 macOS 上运行时，Framework 的 `App.video` 通过动态反射探测 `ClassDB`：
  - 若已加载完整 FFmpeg 解码器库，自动走 `FFmpegVideoStream`；
  - 若未加载，自动无缝平滑降级至内置 `EngineVideoAdapter`（`VideoStreamTheora`），确保绝不中断游戏。

## 重新编译本地 Universal 库
直接在当前目录执行：
```bash
./addons/ffmpeg/macos/build_macos.sh
```

## 编译官方完整版 EIRTeam.FFmpeg (含 x264/x265 软解/硬解)
在具备 Xcode / brew 环境的 macOS 设备上：
```bash
git clone --recursive https://github.com/EIRTeam/EIRTeam.FFmpeg.git /tmp/ffmpeg-build
cd /tmp/ffmpeg-build
pip3 install scons
make bootstrap
make gdextension PLATFORM=macos
cp -r bin/macos/* <本工程>/addons/ffmpeg/macos/
```
