@abstract
class_name NodeSubsystem
extends Node

## 框架节点级子系统抽象基类 (Node)。
## 适用于需要挂载在场景树、持有子节点、渲染层或系统级生命周期的常驻子系统。
## 若需帧驱动，子类可直接启用或覆写引擎原生的 _process(delta) / _physics_process(delta)。

## 获取子系统全局唯一标识符
@abstract
func get_id() -> String


## 子系统初始化（支持异步或同步执行，返回确定性结果）
func initialize() -> Result:
	return Result.ok()


## 销毁清理子系统（释放子节点、注销监听、自移除出场景树）
func dispose() -> void:
	if is_inside_tree():
		queue_free()
