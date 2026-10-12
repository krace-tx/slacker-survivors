@abstract
class_name Subsystem
extends RefCounted

## 框架轻量级子系统抽象基类 (RefCounted)。
## 适用于无需挂载场景树的纯逻辑、数据、工具类常驻子系统。
## 提供标准生命周期规范：唯一标识、显式初始化与安全销毁。

## 获取子系统全局唯一标识符
@abstract
func get_id() -> String


## 子系统初始化（支持异步或同步执行，返回确定性结果）
func initialize() -> Result:
	return Result.ok()


## 销毁清理子系统（释放内存、取消注册监听）
func dispose() -> void:
	pass
