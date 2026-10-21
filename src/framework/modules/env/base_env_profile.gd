class_name BaseEnvProfile
extends BaseParams

## 多环境配置策略与初始化模板基类（Environment Profile Strategy & Template Base）。[br]
##
## 采用 **多态策略模式（Strategy）+ 模板方法模式（Template Method）**：[br]
## 1. **强类型配置承载**：继承自 [BaseParams]，子类声明的所有公开成员变量天然具备强类型补全与 [method BaseParams.to_dict] / [method BaseParams.from_dict] 序列化能力；[br]
## 2. **共性下沉与差异多态**：业务层可定义公共基底 Profile（设置默认参数与公共初始化逻辑），并按需派生 `DevEnvProfile`、`ProdEnvProfile` 等子类，仅重写差异属性与 [method _on_configure] 钩子；[br]
## 3. **统一注册与自动调度**：通过 [method BaseRuntimeEnvironment.register_profile] 注册后，由 [code]App.env.activate_profile()[/code] 自动实例化当前环境匹配的策略并执行模板方法 [method configure]。

#region Internal State
var _is_configured: bool = false
#endregion


#region Template Method Lifecycle
## 执行当前环境 Profile 的初始化配置流程（模板方法，由 [code]App.env[/code] 统一调度，保证幂等执行）。[br]
##
## [param env] 当前运行环境门面实例。
func configure(env: BaseRuntimeEnvironment) -> Result:
	if _is_configured:
		return Result.ok(self)
	_on_configure(env)
	_is_configured = true
	return Result.ok(self)


## 当前 Profile 是否已执行过 [method configure] 初始化配置逻辑。
func is_configured() -> bool:
	return _is_configured
#endregion


#region Subclass Polymorphic Hook
## 【子类重写钩子】在当前环境 Profile 被激活时自动调用。[br]
##
## 子类可在此处编写当前环境专属的初始化配置逻辑（例如：设置特殊调试开关、配置环境专属服务参数等）。[br]
## [param _env] 当前运行环境门面实例（只读）。
func _on_configure(_env: BaseRuntimeEnvironment) -> void:
	pass
#endregion
