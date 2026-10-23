# Test · Auth (跨平台登录、Steam 票据交换与云存档系统验证)

> 验证 `App.auth`（[`src/framework/modules/auth/`](../../framework/modules/auth/_doc_auth.md)）、`GodotSteam` 动态反射桥接与 `App.storage` Steam Cloud 云存档（[`src/framework/modules/storage/`](../../framework/modules/storage/_doc_storage.md)）的自动化契约自检与交互式可视化沙盒面板（[`auth_test.gd`](auth_test.gd)）。支持在编辑器中直接按 `F6` 独立运行。

```text
src/test/auth/
├── _doc_auth.md        # 本文档
├── auth_test.gd        # 6 项自动化契约自检 + Steam 票据/云存档实时看板 + 交互式登录矩阵 (extends BaseScene)
└── auth_test.tscn      # 测试入口场景 (含 BaseView 根节点 $UI)
```

---

## 验证清单

1. **自动化契约自检（启动时自动运行并输出至 `App.logger` 与右侧报告面板）**：
   - **[1/6] `GodotSteam` GDExtension 探测与多端渠道注册校验**：验证 `App.auth.get_available_providers()` 渠道发现机制，以及宿主 Steam 客户端运行时的 `Steam` 单例与 `AppID` 反射探测；
   - **[2/6] Steam 登录与 `getAuthTicketForWebApi` 异步取证验证**：验证通过 `AuthProviderType.STEAM` 采集真实 `SteamID64`、玩家昵称（`getPersonaName`）以及向 Valve 服务端异步申请十六进制 `WebAPI Ticket`（`session.platform_ticket`）；
   - **[3/6] 本机设备指纹游客（`Guest`）确定性派生与登出释放**：验证 `logout()` 释放底层 `HAuthTicket` 句柄并归零状态机，且多次 `AuthProviderType.GUEST` 登录生成完全一致的确定性 `guest_<hash>` 账号；
   - **[4/6] 游客无损转正（`link_provider_async` Account Linking）**：验证从 `Guest` 会话直接绑定升级至 `Steam`（或 `Custom`）正式账号，且新会话的 `linked_from_account_id` 精确记录原游客 ID 以供存档过户；
   - **[5/6] 自建后端网关不可达时的离线容灾降级（`RemoteGatewayVerifier` Offline Fallback）**：验证开启 `use_remote_gateway = true` 但远端网关断连时，系统不阻断单机进游，自动降级签发保留真实 `SteamID64` 的 `AuthState.OFFLINE` 会话；
   - **[6/6] `Steam Cloud (ISteamRemoteStorage)` 与 `PlayerProfileService` 云存档闭环**：验证玩家档案自动合并当前 `AuthSession` 身份，并通过 `StorageItem.with_steam_cloud()` 完成本地落盘与 Steam Cloud 远端云存储读写往返校验。
2. **实时交互验证沙盒**：
   - **实时会话与 Steamworks 诊断看板**：动态展示当前 `AuthState`、渠道、游戏内 `account_id`、`SteamID64`、昵称、`WebAPI Ticket` 十六进制摘要、Steam Cloud 配额及 `PlayerProfileModel` 同步状态；
   - **8 项交互式登录与云存档操作矩阵**：支持一键触发智能自动登录、Steam 含票据登录、Steam 免票据 0ms 直通、游客登录、游客转正绑定 Steam、模拟远端网关断网降级、Steam Cloud 云存档读写校验及登出释放。
