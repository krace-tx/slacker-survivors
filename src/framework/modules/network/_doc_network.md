# Framework · Network (HTTP 网络通信与原子文件传输系统)

> 统一接管游戏客户端 HTTP/HTTPS REST 通信、有界并发连接池调度、带随机抖动的指数退避重试、Bearer Token 鉴权与 401 单飞刷新拦截，以及基于 `.tmp` 事务级原子落盘与 MD5 强校验的流式文件传输。

```text
src/framework/modules/network/
├── _doc_network.md             # 本文档（12 维工程规范与使用范式）
├── base_network_client.gd      # 公开门面契约 BaseNetworkClient (App.net，详尽注释)
│
├── types/                      # [公开契约与数据对象] 脱离目录自解释
│   ├── network_error.gd        # 标准错误码常量 (Network.Timeout / Network.HttpUnauthorized / Network.HashMismatch 等)
│   └── network_request.gd      # 单次请求配置契约 (URL、Method、Query、Body、Headers、重试策略、CancellationToken)
│
└── impl/                       # [私有实现收敛] 外部不可见，严禁业务层直接引用
    ├── network_client.gd       # 核心编排实现 (NetworkClient extends BaseNetworkClient)
    └── request_queue.gd        # 有界并发队列、HTTPRequest 节点池、抖动指数退避与 401 单飞刷新调度器
```

> 模块目录名保持完整的 `network`；全局访问门面统一使用 `App.net`，内部实现类为 `NetworkClient`。

---

## 一、 核心工程设计机制 (12 维治理契约)

1. **职责边界 (Responsibility)**：
   - **负责**：HTTP/HTTPS 短连接 API 请求（`GET`/`POST`/`PUT`/`DELETE`/`PATCH`/`HEAD`）、URL Query 自动编码拼接、全局 `base_url` 与公共 Header 管理、Bearer Token 注入与 401 刷新重放、HMAC-SHA256 防篡改与防重放请求签名（`set_request_signing`）、`multipart/form-data` 上传、`.tmp` 原子流式下载与 MD5 校验。
   - **不负责**：具体业务 DTO 语义解析、本地多级缓存编排（由 `App.storage` 负责）、实时帧同步或长连接状态同步（WebSocket / ENet 需独立通道模块）。
2. **有界并发队列与连接池预算 (Performance Budget)**：
   - `RequestQueue` 默认限制**最大并发飞行请求数为 `6`**（`max_concurrent_requests = 6`），超出上限的请求自动进入 FIFO 等待队列；
   - 维护**最大容量为 `8` 的空闲 `HTTPRequest` 节点池**（`max_pool_size = 8`），高峰过后超出池容量的节点自动销毁，杜绝节点无限膨胀。
3. **带随机抖动（Jitter）的指数退避与 401 单飞刷新 (Failure & Retry Policy)**：
   - **可重试错误**：底层网络抖动（DNS/连接失败/TLS 握手失败/超时）及 HTTP `408`、`429 (Too Many Requests)`、`5xx` 自动按 `base * 2^(N-1) * randf_range(0.85, 1.15)` 阶梯退避重试，避免服务端恢复时的客户端惊群效应。
   - **快速失败**：HTTP `4xx`（除 401/408/429 外）与 JSON 解析错误立即失败，不浪费重试配额。
   - **401 Single-Flight 刷新**：注册 `set_unauthorized_handler` 后，当多个并发请求同时收到 HTTP 401 时，自动合并为单次刷新调用，刷新成功后无感重放原请求一次。
4. **事务级 `.tmp` 原子文件下载 (Atomic File Download)**：
   - `download_file` 与 `download_file_with_md5` 先流式写入 `<save_path>.<id>.tmp` 临时文件（开启 `use_threads = true` 后台线程 I/O）；
   - 仅当 HTTP 状态码为 `2xx` 且（若指定）MD5 哈希校验完全匹配后，才通过 [`FileUtils.rename_file`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/util/file/file_utils.gd) 原子替换至目标路径；任何断网、非 2xx 响应、MD5 不匹配或中途取消均立即清除 `.tmp` 残卷，原目标文件 100% 安全。
5. **零死锁异步取消与生命周期守卫 (Async & Lifecycle)**：
   - 解决 Godot `HTTPRequest.cancel_request()` 不发射 `request_completed` 信号的引擎限制；
   - 在排队期、飞行请求期、退避等待期及文件流传输期全链路支持 [`CancellationToken`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/async/cancellation_token.gd)（可绑定 `BaseScene.task_scope` / `BaseView.task_scope`），并在 `FrameworkRuntime` 执行 `shutdown_async()` / `dispose()` 时安全中止所有传输。
6. **标准化错误契约 (Public Error Contract)**：
   - 全面采用 [`NetworkError`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/modules/network/types/network_error.gd) 与 [`FrameworkError`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/core/contracts/framework_error.gd)，通过 `res.error_code()`、`res.is_retryable()`、`res.error_context()` 暴露完整诊断上下文（含 `url`、`status_code`、`attempt`），拒绝将损坏的 JSON 静默伪装为空字典。

---

## 二、 使用范式

### 1. 基础配置、鉴权与 GET/POST 请求
```gdscript
# 1. 初始化阶段配置基础地址与公共头
App.net.set_base_url("https://api.slacker-survivors.com")
App.net.set_default_header("X-Client-Version", "1.0.0")
App.net.set_auth_token(user_token)

# 2. 发送带 Query 参数的 GET 请求（自动拼接为 https://.../v1/leaderboard?season=3&limit=20）
var res := await App.net.get_request("/v1/leaderboard", {"season": 3, "limit": 20})
if res.is_ok():
	var data: Dictionary = res.value
else:
	App.logger.error("Network", "[%s] 请求失败: %s" % [res.error_code(), res.error_message()])
```

### 2. 绑定 UI/场景 `TaskScope` 实现退出即取消
```gdscript
# 在继承自 BaseView 或 BaseScene 的类中，传入 task_scope.get_token()
func _fetch_rank_list() -> void:
	var res := await App.net.post_request(
		"/v1/rank/query",
		{"page": 1},
		PackedStringArray(),
		task_scope.get_token() # 界面关闭时自动取消飞行中的请求与退避等待
	)
	if res.is_err():
		if res.error_code() == NetworkError.CANCELLED:
			return
		App.logger.warn("RankUI", "拉取失败: %s" % res.error_message())
		return
	_render_list(res.value)
```

### 3. 流式原子下载与 MD5 完整性校验
```gdscript
var dl_res := await App.net.download_file_with_md5(
	"https://cdn.slacker-survivors.com/patches/v102.pck",
	"user://patches/v102.pck",
	"e4d909c290d0fb1ca068ffaddf22cbd0",
	func(downloaded: int, total: int) -> void:
		if total > 0:
			progress_bar.value = float(downloaded) / float(total),
	PackedStringArray(),
	task_scope.get_token()
)
if dl_res.is_ok():
	App.logger.info("Patch", "补丁包校验通过并原子落盘: %s" % dl_res.value)
```
