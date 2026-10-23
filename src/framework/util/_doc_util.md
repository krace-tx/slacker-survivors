# Utils (无状态工具库)

## 核心

提供全框架与业务层通用的无状态纯函数工具集合。
覆盖场景树节点操作、安全文件 I/O、资源与图像编解码、时间格式化、坐标数学计算与内存大小评估等基础领域。
所有工具类仅包含 `static func` 纯函数，不维护内部状态，不持有业务实例引用，失败操作严格通过 `Result` 显式向上传递。
*(注：有状态的异步任务生命周期作用域已收敛于 [`src/framework/infra/async/`](../infra/async/_doc_async.md) 的 `TaskScope` 中；Spine 骨骼动画流式控制器、享元对象池、视口内真预热与分频错峰调度已统一升级收敛于 [`src/framework/infra/spine/`](../infra/spine/_doc_spine.md) 的 `SpineController` 与 `SpinePool` 中；有状态的显示控制、窗口模式、分辨率与异形屏安全区已收敛于 [`src/framework/modules/display/`](../modules/display/_doc_display.md) 的 `App.display` 中。)*

---

## 细节

- **设计约束**：
  - **纯函数与零状态**：工具类不得持有成员变量，调用方随用随调，不产生外部不可预期的副作用。
  - **错误显式化**：凡涉及 I/O、节点挂载、资源实例化的可失败操作，强制返回 `Result.ok(val)` 或 `Result.err(msg)`，严禁静默吞错；仅基础设施底层确认必成功的操作提供 `_required` 后缀方法（失败直接 `assert`）。
- **职责划分**：
  - `NodeUtils`：节点场景树生命周期（`@abstract` 纯静态）——入树挂载（`mount` / `mount_required`）、预制体实例化（`spawn`）、子树复制（`clone`）、安全销毁（`safe_free` / `clear_children`）与信号驱动的 `wait_ready` 等待；失败返回 `Node.{Reason}` 错误码。节点查找直接用引擎内置 `find_child` / `get_node_or_null`，不在此封装。
  - `FileUtils`：工业级安全文件 I/O、`.tmp` 事务级原子落盘、ZSTD 压缩 / AES-256 加密读写（含 `write_encrypted_json` / `read_encrypted_json` 组合管线）、MD5 / SHA-256 完整性校验、64KB 分块流式复制、文件头 OS PageCache 预热（`warm_file_head`）、目录树生命周期管理与 `res://` 导出包资源实体化（`materialize_res_file` / `get_materialized_cache_path`）。
  - `CryptoUtils`：纯内存无状态密码学与二进制压缩原语，包含 Encrypt-then-MAC 认证加密信封（`AES-256-CBC + PKCS#7 + 随机 IV + HMAC-SHA256`，魔数 `FWKE`）、精确长度头 ZSTD 内存压缩帧（魔数 `FWKZ`）、HMAC-SHA256 请求签名、恒定时间防时序比对与硬件设备指纹密钥派生（`derive_passphrase`）。
  - `TimeUtils`：系统墙钟（`now_string`）与格式化时间（`format_mm_ss` / `format_hh_mm_ss`）。
  - `CoordUtils`：零开方空间距离/圆环/扇形锥（`is_within_cone`）判定、双向网格坐标换算（`world_to_grid` / `grid_to_world` / `snap_to_grid`）、Control 全局变换包围盒（`get_global_rect`）、等比内接矩形（`fit_rect_aspect`）与跨 CanvasLayer / 3D 视口投影桥接（`map_canvas_position` / `world3d_to_screen`）。
  - `MemoryUtils`：全类型严格 $O(1)$ 零循环、零堆分配的 `Variant`、全系 `Packed*Array`、`Image`（C++ `get_data_size()`）与 `Texture2D` 内存/显存占用字节估算（`estimate_bytes` / `estimate_resource_bytes`）。
  - `UuidUtils`：标准 UUID v4 生成与 Base64 紧凑短码互转。
  - `VersionUtils`：语义化版本号格式校验与比对（`compare`）。
  - `codec/`：文件与资源通用纯函数编解码（`FileCodecUtils` 基于文件头魔数的 O(1) 图像/纹理编解码；`ResourceCodecUtils` 基于预编译 Schema 缓存的零配置嵌套 `Resource` ↔ `Dictionary` 互转与内存深拷贝）。

```text
src/framework/util/
├── _doc_util.md                  # 本模块架构与使用文档
├── codec/                        # 编解码工具库
│   ├── file_codec_utils.gd       # (FileCodecUtils) Image / Texture2D 与二进制流 O(1) 魔数嗅探编解码
│   └── resource_codec_utils.gd   # (ResourceCodecUtils) 预编译 Schema 缓存的嵌套 Resource ↔ Dictionary 互转与 clone
├── coord/                        # 坐标数学、几何判定与跨画布投影
│   └── coord_utils.gd            # (CoordUtils) world_to_grid / grid_to_world / is_within_cone / map_canvas_position
├── crypto/                       # 无状态密码学、认证加密与内存压缩原语
│   └── crypto_utils.gd           # (CryptoUtils) encrypt_bytes / hmac_sha256_hex / derive_passphrase / compress_bytes
├── file/                         # 安全文件 I/O 与 VFS 事务操作
│   └── file_utils.gd             # (FileUtils) write_text / write_json / write_encrypted_json / verify_md5
├── memory/                       # 内存与显存字节估算
│   └── memory_utils.gd           # (MemoryUtils) estimate_bytes / estimate_resource_bytes
├── node/                         # 场景树操作与预制体挂载
│   └── node_utils.gd             # (NodeUtils) mount / spawn / clone / safe_free / clear_children / wait_ready
├── time/                         # 时间格式化
│   └── time_utils.gd             # (TimeUtils) now_string / format_mm_ss / format_hh_mm_ss
├── uuid/                         # UUID v4 生成与短码互转
│   └── uuid_utils.gd             # (UuidUtils) generate_v4 / to_base64
└── version/                      # 语义化版本号对比
	└── version_utils.gd          # (VersionUtils) compare / is_valid
```

---

## 样例

```gdscript
# 1. 场景节点安全挂载与预制体生成
var spawn_res := NodeUtils.spawn(card_prefab, $CardContainer)
if spawn_res.is_ok():
	var card_node := spawn_res.value

# 2. 文件安全写入与读取（沙盒一级/二级标准目录常量统一定义在 FileUtils）
var save_path := "%s/shared/demo_save.json" % FileUtils.USER_SAVES_DIR
var write_res := FileUtils.write_text(save_path, json_str, true)
if write_res.is_ok():
	var read_res := FileUtils.read_text(save_path)

# 3. 内存态 AES-256-CBC + HMAC-SHA256 认证加解密与请求签名
var enc_res := CryptoUtils.encrypt_text("secret_payload", "master_passphrase")
if enc_res.is_ok():
	var dec_res := CryptoUtils.decrypt_text(enc_res.value as String, "master_passphrase")
var sig_res := CryptoUtils.hmac_sha256_hex("api_secret", "canonical_data")

# 4. 时间格式化
var time_text := TimeUtils.format_mm_ss(125) # "02:05"

# 5. 坐标转换与版本比对
var grid_coord := CoordUtils.world_to_grid(Vector2(250, 100), Vector2(64, 64))
var is_newer := VersionUtils.compare("1.2.0", "1.1.9") > 0
```
