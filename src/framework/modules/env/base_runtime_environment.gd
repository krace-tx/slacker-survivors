@abstract
class_name BaseRuntimeEnvironment
extends RefCounted

## 运行环境只读边界快照与多环境配置策略门面契约（Runtime Environment Contract）。[br]
##
## 从第一性原理出发，本模块承担两大核心职责：[br]
## 1. **三大正交维度的客观事实快照（$O(1)$ 纯内存查询）**：[br]
##    - **部署目标域（Deployment Tier）**：区分 [code]LOCAL / EMULATOR / DEV / TEST / STAGING / PROD[/code]（见 [EnvType]）；[br]
##    - **宿主与构建形态（Host & Build）**：区分编辑器宿主、Debug/Release 构建与导出 Feature Tag；[br]
##    - **操作系统与硬件平台（OS Platform）**：区分 Desktop / Mobile / Web 及具体操作系统。[br]
## 2. **多环境配置策略注册与调度（Strategy & Template Method）**：[br]
##    - 接收业务层或各模块按 [EnvType] 注册的 [BaseEnvProfile] 子类（或实例），自动匹配当前环境（未命中时回退 [constant EnvType.DEFAULT]）并调度其 [method BaseEnvProfile.configure] 配置逻辑。[br]
##
## 业务代码应统一通过 [code]App.env[/code] 访问本契约提供的方法。


#region 1. Deployment Tier (部署目标域)
## 获取当前部署环境的枚举值（参见 [EnvType]：[code]EnvType.LOCAL .. EnvType.PROD[/code]）。
@abstract
func get_env_type() -> int


## 当前是否为完全离线的纯本机回环开发环境 (LOCAL, 127.0.0.1)。
@abstract
func is_local() -> bool


## 当前是否为模拟器穿透宿主机调试环境 (EMULATOR, 如 Android 模拟器 10.0.2.2)。
@abstract
func is_emulator() -> bool


## 当前是否为开发联调服环境 (DEV)。
@abstract
func is_dev() -> bool


## 当前是否为内网 QA 测试服环境 (TEST)。
@abstract
func is_test() -> bool


## 当前是否为灰度预发布服环境 (STAGING)。
@abstract
func is_staging() -> bool


## 当前是否为正式线上生产服环境 (PROD)。
@abstract
func is_prod() -> bool


## 获取当前部署环境的标准化大写英文名称（"LOCAL" / "EMULATOR" / "DEV" / "TEST" / "STAGING" / "PROD"）。
@abstract
func get_name() -> String
#endregion


#region 2. Host & Build Mode (宿主与构建形态)
## 当前是否在 Godot 编辑器进程内运行（包含 F5/F6 编辑器调试运行）。
@abstract
func is_editor() -> bool


## 当前是否为带调试符号的构建版本（编辑器运行或 Debug 导出模板）。
@abstract
func is_debug_build() -> bool


## 查询当前运行包体是否具备指定的导出特性标签（Feature Tag，如 "demo"、"steam"、"taptap" 等）。[br]
##
## [param tag] 待查询的 Feature Tag 名称。
@abstract
func has_feature(tag: String) -> bool
#endregion


#region 3. OS & Hardware Platform (操作系统与硬件平台)
## 获取当前操作系统平台标准名称（如 "Windows"、"macOS"、"Linux"、"Android"、"iOS"、"Web"）。
@abstract
func get_platform_name() -> String


## 当前是否运行在桌面操作系统平台（Windows / macOS / Linux）。
@abstract
func is_desktop() -> bool


## 当前是否运行在移动端原生真机环境（非编辑器宿主，且操作系统为 Android 或 iOS）。
@abstract
func is_mobile() -> bool


## 当前操作系统是否为 Android。
@abstract
func is_android() -> bool


## 当前操作系统是否为 iOS。
@abstract
func is_ios() -> bool


## 当前是否运行在 Web (HTML5 / Wasm) 浏览器平台。
@abstract
func is_web() -> bool


## 当前操作系统是否为 Windows。
@abstract
func is_windows() -> bool


## 当前操作系统是否为 macOS。
@abstract
func is_macos() -> bool


## 当前操作系统是否为 Linux / BSD。
@abstract
func is_linux() -> bool
#endregion


#region 4. Environment Profile Strategy & Dispatch (多环境配置策略注册与调度)
## 为指定环境档位注册配置策略（支持链式调用）。[br]
##
## [param env_type] 目标环境枚举（取值 [EnvType] 中的 `LOCAL..PROD`，或传入 [constant EnvType.DEFAULT] 作为未命中环境时的默认回退策略）。[br]
## [param profile_or_script] 继承自 [BaseEnvProfile] 的脚本类（[Script]，仅在命中当前环境时按需懒加载实例化）或已创建的 [BaseEnvProfile] 实例。[br]
## @return 返回 [code]self[/code] 以支持流式链式注册。
@abstract
func register_profile(env_type: int, profile_or_script: Variant) -> BaseRuntimeEnvironment


## 激活并执行当前环境匹配的 [BaseEnvProfile] 策略（若当前环境未单独注册，自动回退 [constant EnvType.DEFAULT]）。[br]
##
## 激活过程会自动实例化目标 Profile 并调用其 [method BaseEnvProfile.configure] 模板方法（触发子类 [method BaseEnvProfile._on_configure]）。[br]
## @return 成功时返回携带激活 [BaseEnvProfile] 实例的 [Result]；未注册任何可用 Profile 或类型非法时返回错误 [Result]。
@abstract
func activate_profile() -> Result


## 获取当前环境已激活的 [BaseEnvProfile] 实例（若尚未调用 [method activate_profile]，将自动触发惰性激活）。[br]
##
## @return 返回当前生效的 [BaseEnvProfile] 子类实例；若未注册任何可用 Profile 则返回 [code]null[/code]。
@abstract
func get_profile() -> BaseEnvProfile


## 查询当前环境是否已有可用（已激活或可匹配）的 [BaseEnvProfile] 策略。
@abstract
func has_profile() -> bool
#endregion
