# Framework · Auth (跨平台身份认证、Steam 票据交换与多端会话系统)

> 统一接管全平台身份取证（Steam / Apple / Google Play / 自建 OAuth / 本机指纹游客）、单机直通与自建后端双模会话签发、HTTP 401 Single-Flight 自动续期以及游客无损转正（Account Linking）。对外唯一门面入口为 `App.auth`（[`BaseAuthSystem`](base_auth_system.gd)）。

```text
src/framework/modules/auth/
├── _doc_auth.md                           # 本文档（12 维工程规范、网关协议契约与使用范式）
├── base_auth_system.gd                    # 公开门面契约 BaseAuthSystem (App.auth，详尽注释)
│
├── types/                                 # [公开契约] 外部可见的数据实体与枚举（严禁进 impl）
│   ├── auth_error.gd                      # 标准错误码 (Auth.ProviderUnavailable / TicketTimeout / VerificationRejected 等)
│   ├── auth_provider_type.gd              # 渠道标识常量 (AUTO / STEAM / APPLE / GOOGLE / CUSTOM / GUEST)
│   ├── auth_state.gd                      # 状态机枚举与流转守卫 (UNAUTHENTICATED / AUTHENTICATING / AUTHENTICATED / OFFLINE / ERROR)
│   ├── auth_options.gd                    # 登录配置实体 (首选渠道、是否请求 Ticket、是否启用远端网关、离线降级开关)
│   ├── auth_credential.gd                 # 第一阶段产物：平台原始凭证 (provider, platform_user_id, display_name, raw_ticket)
│   └── auth_session.gd                    # 第二阶段产物：游戏生效会话 (account_id, access_token, refresh_token, is_offline 等)
│
└── impl/                                  # [私有收敛] 单一职责内部实现（业务层严禁直接引用）
	├── auth_system.gd                     # 门面协调器 (实现 BaseAuthSystem，串联取证、验签与 App.net / App.clock 协同)
	├── providers/                         # 第一阶段：多平台凭证供给适配器 (全部采用 Engine.has_singleton 动态反射，零插件硬耦合)
	│   ├── auth_provider_adapter.gd       # 渠道适配器抽象基类
	│   ├── steam_auth_provider.gd         # Steam 适配器 (GodotSteam 反射桥接、WebAPI Ticket 异步获取、Steam Deck 离线模式保底)
	│   ├── apple_auth_provider.gd         # Apple 生态适配器 (iOS / macOS Sign in with Apple & GameCenter 反射桥接)
	│   ├── google_play_auth_provider.gd   # Google Play 适配器 (Android GPGS v2 反射桥接与 ServerAuthCode 获取)
	│   ├── custom_token_auth_provider.gd  # 自建账号 / TapTap / WeGame / OAuth 令牌注入适配器
	│   └── guest_auth_provider.gd         # 设备指纹游客适配器 (基于 CryptoUtils.derive_passphrase 确定性派生本机游客 ID)
	└── verifiers/                         # 第二阶段：会话签发与网关换票策略
		├── auth_session_verifier.gd       # 验证器抽象基类
		├── local_passthrough_verifier.gd  # 纯单机/Steam 直连签发器 (零后端依赖，0ms 确定性签发会话)
		└── remote_gateway_verifier.gd     # 远端自建后端网关换票器 (POST Ticket 换取 JWT，网络故障自动降级离线会话)
```

---

## 一、 核心工程设计机制 (12 维治理契约)

1. **两段式正交流水线（`AuthProviderAdapter` 取证 $\times$ `AuthSessionVerifier` 签发）**：
   - **第一阶段（平台取证）**：只关心如何从宿主平台（Steam / Apple / Google / Custom / Guest）采集标准化的 [`AuthCredential`](types/auth_credential.gd)；
   - **第二阶段（会话签发）**：决定是走 **纯单机本地直通**（[`LocalPassthroughVerifier`](impl/verifiers/local_passthrough_verifier.gd)，适用于单机买断制或离线模式），还是 **发往自建后端网关验票换取 JWT**（[`RemoteGatewayVerifier`](impl/verifiers/remote_gateway_verifier.gd)，适用于联机赛季/云存档/排行榜）。
   - 项目从纯单机阶段演进至自建后端阶段时，仅需在环境配置中调用 `App.auth.set_remote_gateway_enabled(true)`，业务层登录与档案代码**零改动**。
2. **外部 SDK 零编译期耦合（Dynamic Reflection Bridge）**：
   - [`SteamAuthProvider`](impl/providers/steam_auth_provider.gd)、[`AppleAuthProvider`](impl/providers/apple_auth_provider.gd)、[`GooglePlayAuthProvider`](impl/providers/google_play_auth_provider.gd) 均通过 `Engine.has_singleton(...)` 动态探测与 `.call(...)` 反射调用；
   - 即使开发机未安装 `GodotSteam` 或移动端原生插件，全工程依然 100% 正常静态编译运行，并在 `login_auto_async()` 时自动平滑降级至 [`GuestAuthProvider`](impl/providers/guest_auth_provider.gd)。
3. **Steam Deck 离线模式与断网自动降级（Offline-First Resilience）**：
   - 当玩家在 Steam 离线模式下启动游戏时，`SteamAuthProvider` 检测到 `loggedOn() == false` 但 `getSteamID() > 0`，立即签发携带真实 `SteamID64` 且标记 `is_platform_offline = true` 的凭证，确保单机游玩与本地存档归属不断链；
   - 当启用远端网关但服务器维护或玩家断网时，若 [`AuthOptions.allow_offline_fallback`](types/auth_options.gd) 为 `true`，`RemoteGatewayVerifier` 自动无感降级为本地离线会话。
4. **与 `App.net`、`App.clock`、`App.storage` 全自动闭环协同**：
   - 会话签发或刷新后，[`AuthSystem`](impl/auth_system.gd) 自动调用 `App.net.set_auth_token(session.access_token)` 注入全局 Bearer Token，并在初始化时向 `App.net` 注册 `set_unauthorized_handler(...)` 实现 **HTTP 401 Single-Flight 自动静默续期**；
   - 若后端返回 `server_time_ms`，自动调用 `App.clock.sync(server_time_ms)` 完成防作弊权威时钟校准；
   - 配合 [`StorageItem.with_steam_cloud()`](../storage/types/storage_item.gd) 与 [`RemoteStorageDriver`](../storage/impl/drivers/remote_storage_driver.gd)，同时支持 **Steam Cloud (`steam://...`)** 与 **自建后端 HTTP 云存档 (`/v1/...`)** 双通道镜像写与降级读。
5. **游客无损转正（Account Linking）**：
   - 移动端或未开 Steam 的玩家前期以 `Guest` 身份游玩产生本地进度后，调用 `await App.auth.link_provider_async(AuthProviderType.APPLE)` 绑定正式平台账号；
   - 签发的新 [`AuthSession.linked_from_account_id`](types/auth_session.gd) 自动携带原 `guest_<id>`，供业务层（如 `PlayerProfileModel.apply_auth_session`）将原游客进度无缝过户至正式账号。

---

## 二、 自建后端网关通信协议契约 (`RemoteGatewayVerifier`)

当开启 `use_remote_gateway = true` 时，[`RemoteGatewayVerifier`](impl/verifiers/remote_gateway_verifier.gd) 与自建后端网关交互的标准 JSON 契约如下：

### 1. 票据换取会话接口 (`POST /v1/auth/exchange`)
- **请求体 (Request Body)**：
  ```json
  {
	"provider": "steam",
	"platform_user_id": "76561198000000000",
	"display_name": "SteamPlayer",
	"ticket": "14000000a1b2c3...",
	"metadata": {
	  "app_id": 480,
	  "steam_service_identity": "game_backend"
	}
  }
  ```
- **响应体 (Response Body，支持顶层或包裹在 `data` 字段内)**：
  ```json
  {
	"account_id": "acc_9f8e7d6c",
	"display_name": "SteamPlayer",
	"avatar_url": "https://...",
	"access_token": "eyJhbGciOiJIUzI1Ni...",
	"refresh_token": "rt_8a7b6c5d...",
	"expires_at_ms": 1735689600000,
	"server_time_ms": 1735603200000
  }
  ```

### 2. 令牌续期接口 (`POST /v1/auth/refresh`)
- **请求体**：`{ "account_id": "acc_9f8e7d6c", "refresh_token": "rt_8a7b6c5d..." }`
- **响应体**：返回新的 `access_token`、可选的新 `refresh_token`、`expires_at_ms` 与 `server_time_ms`。

---

## 三、 使用范式

### 1. 启动期全平台智能自动登录（Steam / Apple / Google / Guest 兜底）
```gdscript
# 自动按当前平台择优登录（Desktop 优先 Steam -> iOS 优先 Apple -> Android 优先 Google -> 兜底本机指纹 Guest）
var res := await App.auth.login_auto_async()
if res.is_ok():
	var session := res.value as AuthSession
	App.logger.info("Auth", "当前登录账号: %s (%s), 离线模式: %s" % [
		session.display_name, session.account_id, str(session.is_offline)
	])
```

### 2. 开启自建后端网关验票（Steam WebAPI Ticket 换取后端 JWT）
```gdscript
# 方式 A：在环境配置 Profile (如 ProdEnvProfile._on_configure) 中全局开启远端网关换票
App.auth.set_remote_gateway_enabled(true, "/v1/auth/exchange", "/v1/auth/refresh")

# 方式 B：在单次登录时通过 AuthOptions 链式指定
var opts := AuthOptions.create() \
	.with_provider(AuthProviderType.STEAM) \
	.with_require_ticket(true, "game_backend") \
	.with_remote_gateway(true, "/v1/auth/exchange") \
	.with_offline_fallback(true)

var res := await App.auth.login_auto_async(opts)
```

### 3. 移动端/PC 游客转正（Guest 绑定升级至 Steam / Apple / Google）
```gdscript
# 玩家前期以 Guest 游玩，点击“绑定 Apple / Google / Steam 账号”时：
var link_res := await App.auth.link_provider_async(AuthProviderType.APPLE)
if link_res.is_ok():
	var new_session := link_res.value as AuthSession
	# new_session.linked_from_account_id 记录了原 Guest 账号 ID，供档案服务自动绑定升级
	PlayerProfileService.get_current().apply_auth_session(new_session)
	await PlayerProfileService.save_async()
```
