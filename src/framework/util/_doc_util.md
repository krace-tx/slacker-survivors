# Utils (无状态工具库)

## 核心

提供全框架与业务层通用的无状态纯函数工具集合。
覆盖场景树节点操作、安全文件 I/O、异步并发编排、时间格式化、坐标数学计算、内存大小评估与 Spine 特效播放等基础领域。
所有工具类仅包含 `static func` 纯函数，不维护内部状态，不持有业务实例引用，失败操作严格通过 `Result` 显式向上传递。

---

## 细节

- **设计约束**：
  - **纯函数与零状态**：工具类不得持有成员变量，调用方随用随调，不产生外部不可预期的副作用。
  - **错误显式化**：凡涉及 I/O、节点挂载、资源实例化的可失败操作，强制返回 `Result.ok(val)` 或 `Result.err(msg)`，严禁静默吞错；仅基础设施底层确认必成功的操作提供 `_required` 后缀方法（失败直接 `assert`）。
  - **防 UAF 安全等待**：异步等待与节点生命周期强关联（`wait_safe` / `gather(context)`），在恢复执行时自动校验节点在树状态，杜绝 Use-After-Free 崩溃。
- **职责划分**：
  - `NodeUtils`：节点挂载（`mount`）、预制体实例化（`spawn`）、深度复制（`clone`）、安全销毁（`safe_free`）与 `wait_ready` 等待。
  - `AsyncUtils`：类 Python 风格的异步并发编排（`gather` 并发收集、`wait_first` 竞态等待、`sleep` 安全休眠）。
  - `FileUtils`：安全的文本、二进制与 JSON 文件读写、MD5 校验与父目录自动递归创建。
  - `TimeUtils`：系统墙钟（`now_string`）、格式化时间（`format_mm_ss` / `format_hh_mm_ss`）与生命周期安全等待（`wait_safe`）。
  - `CoordUtils`：世界坐标与网格坐标转换、Control 全局边界计算（`get_global_rect`）。
  - `MemoryUtils`：Variant 动态类型、Image 像素缓冲区与 Texture2D 显存占用字节估算。
  - `SpineUtils`：Spine 骨骼动画资产缓存、场景外预热（`warmup`）与单次/循环特效播放（`play_oneshot`）。
  - `UuidUtils`：标准 UUID v4 生成与 Base64 紧凑短码互转。
  - `VersionUtils`：语义化版本号格式校验与比对（`compare`）。
  - `codec/`：文件与资源通用编解码（`FileCodecUtils` / `ResourceCodecUtils`）。

```text
src/framework/util/
├── _doc_util.md                  # 本模块架构与使用文档
├── codec/                        # 编解码工具库
│   ├── file/                     # 二进制/贴图文件底层 Codec
│   │   ├── file_codec.gd         # 文件 Codec 抽象基类
│   │   ├── file_codec_type.gd    # 编码格式枚举 (IMAGE / TEXTURE_2D)
│   │   ├── image_file_codec.gd   # Image 格式编解码
│   │   └── texture_2d_file_codec.gd # Texture2D 格式编解码
│   ├── file_codec_utils.gd       # 统一文件编解码门面
│   └── resource_codec_utils.gd   # 资源 (Resource) 与 Dictionary 互转
├── async_utils.gd                # 异步并发编排 (gather / wait_first / sleep)
├── coord_utils.gd                # 坐标数学与网格换算 (world_to_grid / grid_to_world)
├── file_utils.gd                 # 安全文件 I/O (write_text / read_text / md5)
├── memory_utils.gd               # 内存与显存字节估算 (estimate_bytes)
├── node_utils.gd                 # 场景树操作 (mount / spawn / clone / safe_free)
├── spine_utils.gd                # Spine 骨骼动画预热与播放 (warmup / play_oneshot)
├── time_utils.gd                 # 时间字符串格式化与安全等待 (format_mm_ss / wait_safe)
├── uuid_utils.gd                 # UUID v4 生成与短码互转
└── version_utils.gd              # 语义化版本号对比 (compare)
```

---

## 样例

```gdscript
# 1. 场景节点安全挂载与预制体生成
var spawn_res := NodeUtils.spawn(card_prefab, $CardContainer)
if spawn_res.is_ok():
	var card_node := spawn_res.value

# 2. 异步任务并发执行 (类似 Python asyncio.gather)
var results := await AsyncUtils.gather([
	func(): return await App.asset.load("res://icon.svg"),
	func(): return await _fetch_user_profile_async(),
], self)

# 3. 文件安全写入与读取
var write_res := FileUtils.write_text("user://save.json", json_str)
if write_res.is_ok():
	var read_res := FileUtils.read_text("user://save.json")
	print(read_res.value)

# 4. 时间格式化与生命周期安全等待（防 UAF）
var time_text := TimeUtils.format_mm_ss(125) # "02:05"
var wait_res := await TimeUtils.wait_safe(self, 1.5)
if wait_res.is_ok():
	# 节点在等待期间未被释放，安全继续执行后续逻辑
	pass

# 5. Spine 特效预热与播放
SpineUtils.warmup([SpineCatalog.LEVEL_PASS_PIECE], self)
SpineUtils.play_oneshot(SpineCatalog.LEVEL_PASS_PIECE, $EffectLayer, Vector2(540, 960))

# 6. 坐标转换与版本比对
var grid_coord := CoordUtils.world_to_grid(Vector2(250, 100), Vector2(64, 64))
var is_newer := VersionUtils.compare("1.2.0", "1.1.9") > 0
```
