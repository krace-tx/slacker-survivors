class_name GameEnvConfig
extends Resource

## 游戏多环境部署参数与安全策略配置资源（对应 [code]res://src/resources/envs/env_*.tres[/code]）。[br]
##
## [b]核心职责：[/b][br]
## 1. 支持在 Godot Inspector 中按环境档位（`local` / `dev` / `staging` / `prod`）可视化切换存档加密开关；[br]
## 2. 统一承载本地核心存档（`saves/`）的加密口令、硬件指纹绑定与旧明文兼容策略；[br]
## 3. 统一承载远端业务 API 网关地址与请求防篡改签名配置（由 [GameEnvService] 在启动期一次性注入底层门面）。

#region Save & Storage Security
@export_group("Save Encryption & Compression")
## 是否开启本地核心存档（`saves/`）透明 AES-256 认证加密（`config/` 设备偏好设置自动豁免保持明文 JSON）
@export var enable_save_encryption: bool = true
## 开启加密时，是否混入当前设备硬件唯一指纹（[method OS.get_unique_id]）防跨机器复制替档
@export var bind_save_to_device: bool = true
## 开启加密时，是否在加密前自动执行 ZSTD 内存帧压缩
@export var compress_saves: bool = true
## 开启加密时，是否允许兼容读取历史未加密的明文旧档（读取后下次保存自动升级为密文；正式生产环境建议关闭以防明文降级篡改）
@export var allow_plaintext_save_fallback: bool = false
## 本地核心存档全局主派生口令（底层按各存档 `key_id` 独立加盐二次派生；正式导出包建议同步开启 Godot PCK 脚本加密）
@export var save_encryption_secret: String = "slacker_survivors_save_kdf_v1"
#endregion

#region Network & Runtime Switches
@export_group("Network & Runtime")
## 远端业务 API 网关基础地址（为空表示纯单机 / Steam Cloud 模式，不连接自建网关）
@export var api_base_url: String = ""
## 自建网关 HTTP 请求防篡改 HMAC-SHA256 签名密钥（为空表示不启用请求签名）
@export var request_signing_secret: String = ""
## 是否允许启用开发期调试工具与诊断入口
@export var enable_debug_tools: bool = false
#endregion
