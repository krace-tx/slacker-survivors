class_name GamePresenter
extends RefCounted

## MSVP 架构 · 表现调度层基类 (Presenter)。[br]
##
## 职责：[br]
## 1. 充当 View 与 Model / Service 之间的中介者与胶水桥梁；[br]
## 2. 监听 View 派发的用户操作交互事件，委托转交给 Service 执行业务逻辑；[br]
## 3. 监听 Model 的数据变更信号，驱动 View 刷新视觉展示；[br]
## 4. 自身不包含复杂游戏数值规则（归 Service），也不直接写动画与节点操作（归 View）。

var _view_ref: WeakRef
var _model: GameModel
var _service: GameService
var _is_bound: bool = false


## 绑定三要素：View、Model、Service
func bind(view: Object, model: GameModel = null, service: GameService = null) -> void:
	if _is_bound:
		unbind()
	
	_view_ref = weakref(view) if view != null else null
	_model = model
	_service = service
	_is_bound = true
	
	_on_bind()


## 解除绑定并断开信号连接
func unbind() -> void:
	if not _is_bound:
		return
	
	_on_unbind()
	_is_bound = false
	_view_ref = null
	_model = null
	_service = null


## 获取当前关联的视图对象 (若节点已释放则返回 null)
func get_view() -> Object:
	if _view_ref != null:
		return _view_ref.get_ref()
	return null


## 获取当前关联的数据模型
func get_model() -> GameModel:
	return _model


## 获取当前关联的业务服务
func get_service() -> GameService:
	return _service


## 判断是否处于有效绑定状态
func is_bound() -> bool:
	return _is_bound and get_view() != null


#region Subclass Lifecycle Hooks
## 子类覆写：挂载监听、连接信号并执行初次 View 刷新
func _on_bind() -> void:
	pass


## 子类覆写：注销信号监听、清理临时状态
func _on_unbind() -> void:
	pass
#endregion
