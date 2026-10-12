# 视频播放器测试场景与全屏沉浸式播放器规范

本目录包含视频播放器功能验证场景 `video_player_test.tscn` 及其配套资源。

---

## 一、场景结构与设计语言

场景定位为 **全屏现代流媒体/电影级播放器**：
- **画面层 (`%VideoScreen`)**：采用 `TextureRect`，设置 `expand_mode = EXPAND_IGNORE_SIZE` 与 `stretch_mode = STRETCH_KEEP_ASPECT_CENTERED`，确保在任何屏幕长宽比下等比例自适应画面；
- **交互层 (`%TouchOverlay`)**：全屏透明触控区域，单击可切换播放/暂停或唤醒控制栏；
- **顶层悬浮栏**：
  - 左上角：磨砂质感圆形返回按钮（`back.svg`）；
  - 顶部居中：胶囊提示通知框（用于显示初始化、报错或状态提示）；
- **中心极简控制栏**：
  - 快退 10 秒（`rewind.svg`）；
  - 核心播放 / 暂停切换（大尺寸圆形 `play_circle.svg` / `pause_circle.svg`）；
  - 快进 10 秒（`forward.svg`）；
  - 跳过（`skip_next.svg`）；
- **底部流线进度栏**：
  - 当前时间码（`CurrentTimeLabel`）；
  - 平滑拖拽进度条（`ProgressSlider`）；
  - 总时长时间码（`TotalTimeLabel`）；
- **自动淡隐机制**：播放中闲置 3.2 秒自动通过 Tween 动画平滑淡出全部悬浮控件；鼠标移动、点击或暂停时立即唤醒。

---

## 二、测试资源清单

| 资源路径 | 格式 / 规格 | 用途说明 |
| :--- | :--- | :--- |
| `assets/big_buck_bunny_1080p_30sec.mp4` | 1920x1080 @ 30fps (H.264 / AAC) | 高清 MP4 测试源，用于验证 GDExtension FFmpeg 与原生硬件播放器 |
| `assets/sample.ogv` | 1920x1080 @ 30fps (Theora / Vorbis) | 高清 OGV 测试源，用于验证免插件引擎原生保底播放链路 |
| `assets/icons/*.svg` | 矢量极简白线图标 | 播放器全套 UI 控件矢量图标 |

---

## 三、快速测试与运行方法

### 1. 在 Godot 编辑器内运行
1. 打开工程；
2. 在文件系统中双击 `src/test/video/video_player_test.tscn`；
3. 按下快捷键 `F6`（运行当前场景），或在右上角点击“运行当前场景”按钮。

### 2. 通过命令行运行
```bash
# macOS
/Applications/Godot.app/Contents/MacOS/Godot src/test/video/video_player_test.tscn

# Windows
godot.exe src/test/video/video_player_test.tscn

# Linux
godot src/test/video/video_player_test.tscn
```

### 3. 验证项清单
- [x] 打开场景自动初始化框架运行时（`App.bootstrap()`）；
- [x] 控制台输出当前识别的后端信息（如 `Active Backends -> [GDExtension: Open-Source GDExtension (FFmpegVideoStream)...]`）；
- [x] 画面流畅渲染 1080p MP4 视频，无黑屏与杂音；
- [x] 点击播放/暂停切换平滑；
- [x] 快进/快退/进度条跳转精准同步。
