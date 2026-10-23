# Framework · Core · Contracts (结果封装与标准化错误契约)

> `contracts/` 存放跨全框架与业务层共享的可失败结果容器 [`Result`](result.gd) 与不可变结构化错误对象 [`FrameworkError`](framework_error.gd)。
> 强制所有涉及 I/O、资源加载、网络通信、存档迁移与跨端适配的可失败操作**显式表达成功与失败分支**，彻底杜绝静默返回 `null` 或吞没异常。

```text
src/framework/core/contracts/
├── _doc_contract.md      # 本文档
├── result.gd             # 可失败操作的统一返回值容器 (Result)
└── framework_error.gd    # 标准化不可变错误与上下文诊断对象 (FrameworkError)
```

> 各垂直技术模块的 `Base<Role>` 抽象门面契约就近保存在各自 `src/framework/modules/<module>/` 根目录下（按职责直接继承 `Node` 或 `RefCounted`）。

---

## 一、 `Result` 统一返回容器 (`result.gd`)

### 1. 构造与解包 API 速查

| 类别 | 方法签名 | 说明 |
| :--- | :--- | :--- |
| **成功构造** | `Result.ok(value: Variant = null) -> Result` | 构造成功结果并携带业务负载 `value` |
| **基础错误构造** | `Result.err(error: Variant = "", message: String = "") -> Result` | 传入 `FrameworkError`、`(code, message)` 双字符串或兼容错误对象构造失败结果 |
| **标准错误码构造** | `Result.err_code(code: String, message: String = "") -> Result` | 按 `{Module}.{Reason}` 格式构造包含 `FrameworkError` 的失败结果 |
| **增强诊断构造** | `Result.err_ex(code, message, context, retryable, cause, category) -> Result` | 构造携带结构化诊断字典 `context`、可重试标记 `retryable`、底层原因 `cause` 与分类的失败结果 |
| **状态判定** | `res.is_ok() -> bool` / `res.is_err() -> bool` | 显式判断操作成功或失败 |
| **安全解包** | `res.value` / `res.value_or(default: Variant) -> Variant` | 读取成功负载，或失败时无痛回退至默认值 `default` |
| **错误诊断提取** | `res.error_code() -> String`<br>`res.error_message() -> String`<br>`res.error_module() -> String`<br>`res.is_retryable() -> bool`<br>`res.error_context() -> Dictionary` | 无需手动强转 `res.error as FrameworkError`，直接安全读取错误码、描述、所属模块、重试建议与上下文字典 |

---

## 二、 `FrameworkError` 不可变错误模型 (`framework_error.gd`)

### 1. 错误码命名规范与 9 大标准分类

- **错误码格式**：严格遵循 `"{Module}.{Reason}"`（如 `"Scene.NotFound"`、`"Storage.VersionTooNew"`、`"Network.Timeout"`、`"Async.Cancelled"`）。构造时自动截取 `.` 前缀作为 `module` 字段。
- **9 大标准分类（`Category`）与智能推断**：若未显式传入 `category`，`FrameworkError._infer_category(code)` 会根据错误码语义自动归类：
  - `CATEGORY_GENERAL (&"general")`：常规未分类错误
  - `CATEGORY_PARAM (&"param")`：参数非法、为空或格式错误（含 `invalid` / `empty` / `param`）
  - `CATEGORY_IO (&"io")`：磁盘读写、文件流或底层设备 I/O 故障（含 `io` / `disk` / `file`）
  - `CATEGORY_TIMEOUT (&"timeout")`：异步任务或网络请求超时（含 `timeout`）
  - `CATEGORY_CANCELLED (&"cancelled")`：主动取消或宿主销毁中断（含 `cancel`）
  - `CATEGORY_VALIDATION (&"validation")`：哈希校验、签名或 Schema 校验失败
  - `CATEGORY_MIGRATION (&"migration")`：存档版本升级失败或版本过高拒绝降级（含 `migrat` / `version`）
  - `CATEGORY_NOT_FOUND (&"not_found")`：目标资源、存档或动作不存在（含 `notfound` / `not_found` / `missing`）
  - `CATEGORY_STATE (&"state")`：状态机非法跃迁或重入繁忙

### 2. 不可变链式派生与结构化导出

`FrameworkError` 所有属性均为只读，跨层传递时可通过链式方法生成附带新上下文的副本，绝不污染原始错误实例：
- `err.with_context(extra_context: Dictionary) -> FrameworkError`：合并附加诊断键值（如 `{"path": path, "attempt": 2}`）；
- `err.with_cause(cause: Variant) -> FrameworkError`：挂载底层原始错误原因；
- `err.with_retryable(retryable: bool, category: StringName = &"") -> FrameworkError`：更新可重试标记；
- `err.to_dict() -> Dictionary`：导出包含 `code / message / module / category / retryable / cause / context` 的标准字典，供日志或异常上报系统直接序列化。

---

## 三、 使用范式

```gdscript
# 1. 模块内部构造携带上下文与可重试标记的标准错误
if http_status == 503:
	return Result.err_ex(
		NetworkError.HTTP_SERVER_ERROR,
		"Service temporarily unavailable",
		{"url": req_url, "status": http_status},
		true, # retryable = true
		null,
		FrameworkError.CATEGORY_IO
	)

# 2. 调用方消费 Result 并利用 value_or 或结构化诊断
var res := await App.storage.read_async(&"player_profile")
if res.is_err():
	App.logger.error(
		res.error_module(),
		"[%s] 读取失败 (retryable=%s): %s | ctx=%s" % [
			res.error_code(),
			str(res.is_retryable()),
			res.error_message(),
			str(res.error_context()),
		]
	)
	return

var profile_dict: Dictionary = res.value_or({})
```
