# Framework · Env

> 运行环境只读边界快照与多环境配置策略调度服务。在进程启动瞬间采集并固化**部署目标域、宿主构建形态、物理操作系统平台**三大正交维度的客观事实，并提供基于**多态策略模式 + 模板方法模式**的 [`BaseEnvProfile`](base_env_profile.gd) 注册与调度机制。

```text
src/framework/modules/env/
├── _doc_env.md                  # 本文档
├── base_runtime_environment.gd  # 公开门面契约 BaseRuntimeEnvironment (App.env，详尽注释)
├── base_env_profile.gd          # 多环境配置策略与初始化模板基类 BaseEnvProfile (继承 BaseParams)
├── types/                       # [公开契约]
│   └── env_type.gd              # 部署环境档位枚举定义 EnvType (LOCAL..PROD, DEFAULT)
└── impl/                        # [私有实现收敛]
    └── runtime_environment.gd   # 门面实现：启动即快照、多源优先级探测与 Profile 策略调度
```

---

## 一、 第一性原理与三大正交维度

`App.env` 严格遵循**「进程启动一次性快照」**原则，所有环境与平台查询均为 $O(1)$ 纯内存字段读取：

| 正交维度 | 核心方法 | 解决的问题与典型消费场景 |
| :--- | :--- | :--- |
| **1. 部署目标域**<br>(Deployment Tier) | `get_env_type()` / `is_local()` / `is_emulator()` / `is_dev()` / `is_test()` / `is_staging()` / `is_prod()` / `get_name()` | **连向哪个外部环境**：对应 [`EnvType`](types/env_type.gd) 6 档枚举，决定当前激活哪份 [`BaseEnvProfile`](base_env_profile.gd) 策略、日志默认过滤级别及调试门禁。 |
| **2. 宿主与构建形态**<br>(Host & Build) | `is_editor()` / `is_debug_build()` / `has_feature(tag)` | **以什么容器/编译模式运行**：区分 Godot 编辑器内运行与独立导出包、Debug/Release 构建，以及透传查询 `"demo"`、`"steam"` 等发行 Feature Tag。 |
| **3. 操作系统与平台**<br>(OS Platform) | `is_desktop()` / `is_mobile()` / `is_android()` / `is_ios()` / `is_web()` / `is_windows()` / `is_macos()` / `is_linux()` / `get_platform_name()` | **跑在什么物理硬件载体上**：决定默认交互形态（移动端触屏虚拟摇杆 vs 桌面端键鼠/全屏设置）、iOS 审核规范适配等。 |

---

## 二、 部署环境（EnvType）探测优先级链

为解决编辑器按 F5/F6 运行时无导出 Feature Tag 导致无法切换环境调试的痛点，[`RuntimeEnvironment`](impl/runtime_environment.gd) 启动时按以下优先级从高到低判定部署档位：

1. **构造函数显式注入**（单元测试优先）：`RuntimeEnvironment.new(EnvType.PROD, "iOS")`
2. **启动命令行参数**：支持 `--env=dev` / `--env=test` / `--env=staging` / `--env=prod` / `--env=emulator` / `--env=local`
3. **系统环境变量**：读取 `APP_ENV`（大小写不敏感）
4. **导出 Feature Tag**：`prod` > `staging` > `test` (`qa`) > `dev` > `emulator`
5. **默认兜底**：`EnvType.LOCAL`（本机回环开发环境）

---

## 三、 多环境配置策略模式（`BaseEnvProfile`）

通过**多态策略模式（Strategy）+ 模板方法模式（Template Method）**，彻底消除散落在各模块中的多分支 `if/elif` 与魔法字符串字典：

1. **定义基底 Profile（继承 [`BaseEnvProfile`](base_env_profile.gd)）**：承载默认强类型属性与通用 `_on_configure(env)` 模板钩子。
2. **派生特定环境子类**：仅重写当前环境差异化的字段与专属配置逻辑（符合开闭原则 OCP）。
3. **链式注册与按需激活**：传入脚本类（`Script`）注册时，**仅命中当前运行环境的那一个子类会被懒加载实例化**并执行 `configure(env)`。

```gdscript
# 1. 定义默认基底环境策略 (如 local_env_profile.gd)
class_name LocalEnvProfile
extends BaseEnvProfile

var api_base_url: String = "http://127.0.0.1:8080"
var enable_gm_console: bool = true

func _on_configure(env: BaseRuntimeEnvironment) -> void:
	App.logger.info("Env", "Configured profile for %s -> %s" % [env.get_name(), api_base_url])


# 2. 派生生产环境专属策略 (如 prod_env_profile.gd)，仅重写差异项
class_name ProdEnvProfile
extends LocalEnvProfile

func _init() -> void:
	super._init()
	api_base_url = "https://api.example.com"
	enable_gm_console = false

func _on_configure(env: BaseRuntimeEnvironment) -> void:
	super._on_configure(env)
	# 执行生产环境专属初始化配置逻辑


# 3. 启动阶段链式注册并激活（未单独注册的环境自动回退 EnvType.DEFAULT）
App.env.register_profile(EnvType.DEFAULT, LocalEnvProfile) \
	.register_profile(EnvType.PROD, ProdEnvProfile)
App.env.activate_profile()

# 4. 业务层强类型读取当前生效的 Profile
var profile := App.env.get_profile() as LocalEnvProfile
```
