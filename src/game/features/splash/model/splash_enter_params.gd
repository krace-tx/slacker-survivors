class_name SplashEnterParams
extends BaseParams

## 切入 [SplashScene] 的强类型入参契约（位于 src/game/features/splash/model/）。[br]
## 由极简空入口 [BootstrapScene] 或调试入口构造并透传。

## 强制指定的启动后直达目标场景路径（为空时走标准首屏路由裁决）
var override_target_scene: String = ""
## 透传给最终目标场景的强类型入参契约
var override_target_params: BaseParams = null


func _init(target_scene: String = "", target_params: BaseParams = null, dict: Dictionary = {}) -> void:
	override_target_scene = target_scene
	override_target_params = target_params
	super._init(dict)
