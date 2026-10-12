class_name GameModel
extends RefCounted

## MSVP 架构 · 基础模型层基类 (Model)。[br]
##
## 职责：[br]
## 1. 持有模块的纯状态与领域数据，绝对严禁引用 View 或任何 Godot UI 控件节点；[br]
## 2. 状态发生变更时，通过信号（Signals）通知外部订阅者（主要为 Presenter）；[br]
## 3. 提供数据校验、重置与序列化能力。

signal data_changed()


## 重置模型至初始默认状态
func reset() -> void:
	_on_reset()
	data_changed.emit()


## 子类覆写：自定义重置逻辑
func _on_reset() -> void:
	pass


## 触发通用数据变更信号
func notify_changed() -> void:
	data_changed.emit()
