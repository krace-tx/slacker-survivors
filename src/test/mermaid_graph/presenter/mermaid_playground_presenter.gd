class_name MermaidPlaygroundPresenter
extends RefCounted

## Mermaid 图蓝图演练场薄协调器（位于 `src/test/mermaid_graph/presenter/`，遵循 MSVP `Presenter` 规范）。[br]
##
## [b]核心职责：[/b][br]
## 1. 连接被动视图 [MermaidPlaygroundView]、状态容器 [MermaidTestState] 与领域服务 [MermaidTestService]；[br]
## 2. 在 [method bind] 中完成服务初始化与首轮 5 项契约验证，在 [method unbind] 中安全解绑并释放调试器句柄。


#region Private Fields

var _host_scene: Node = null
var _view: MermaidPlaygroundView = null
var _state: MermaidTestState = null
var _service: MermaidTestService = null

#endregion


#region Lifecycle

func _init(host_scene: Node, view: MermaidPlaygroundView) -> void:
	_host_scene = host_scene
	_view = view
	_state = MermaidTestState.new()
	_service = MermaidTestService.new(_state)


## 绑定双向信号、初始化 FSM/BT 蓝图代理并执行首轮契约验证。
func bind() -> bool:
	_view.guard_sight_toggle_requested.connect(_on_guard_sight_toggle_requested)
	_view.guard_stun_requested.connect(_on_guard_stun_requested)
	_view.guard_revert_requested.connect(_on_guard_revert_requested)
	_view.alpha_damage_requested.connect(_on_alpha_damage_requested)
	_view.alpha_heal_requested.connect(_on_alpha_heal_requested)
	_view.alpha_distance_toggle_requested.connect(_on_alpha_distance_toggle_requested)
	_view.bravo_profile_toggle_requested.connect(_on_bravo_profile_toggle_requested)
	_view.rerun_verification_requested.connect(_on_rerun_verification_requested)

	var init_res: Result = _service.initialize(_host_owner_or_self())
	if init_res.is_err():
		App.logger.error("MermaidGraphTest", init_res.error_message())
		return false

	var all_passed: bool = _service.run_verification_suite(false)
	_view.render_all_logs(_state.log_lines)
	_view.render_state(_state)

	_state.state_changed.connect(_on_state_changed)
	_state.log_appended.connect(_on_log_appended)
	return all_passed


func _host_owner_or_self() -> Object:
	return _host_scene if is_instance_valid(_host_scene) else self


## 解绑所有信号并释放运行期资源。
func unbind() -> void:
	if is_instance_valid(_view):
		if _view.guard_sight_toggle_requested.is_connected(_on_guard_sight_toggle_requested):
			_view.guard_sight_toggle_requested.disconnect(_on_guard_sight_toggle_requested)
		if _view.guard_stun_requested.is_connected(_on_guard_stun_requested):
			_view.guard_stun_requested.disconnect(_on_guard_stun_requested)
		if _view.guard_revert_requested.is_connected(_on_guard_revert_requested):
			_view.guard_revert_requested.disconnect(_on_guard_revert_requested)
		if _view.alpha_damage_requested.is_connected(_on_alpha_damage_requested):
			_view.alpha_damage_requested.disconnect(_on_alpha_damage_requested)
		if _view.alpha_heal_requested.is_connected(_on_alpha_heal_requested):
			_view.alpha_heal_requested.disconnect(_on_alpha_heal_requested)
		if _view.alpha_distance_toggle_requested.is_connected(_on_alpha_distance_toggle_requested):
			_view.alpha_distance_toggle_requested.disconnect(_on_alpha_distance_toggle_requested)
		if _view.bravo_profile_toggle_requested.is_connected(_on_bravo_profile_toggle_requested):
			_view.bravo_profile_toggle_requested.disconnect(_on_bravo_profile_toggle_requested)
		if _view.rerun_verification_requested.is_connected(_on_rerun_verification_requested):
			_view.rerun_verification_requested.disconnect(_on_rerun_verification_requested)

	if _state != null:
		if _state.state_changed.is_connected(_on_state_changed):
			_state.state_changed.disconnect(_on_state_changed)
		if _state.log_appended.is_connected(_on_log_appended):
			_state.log_appended.disconnect(_on_log_appended)

	if _service != null:
		_service.cleanup_on_exit()

	_view = null
	_service = null
	_state = null
	_host_scene = null


## 帧级驱动领域服务推进。
func tick(delta: float) -> void:
	if _service != null:
		_service.tick(delta)

#endregion


#region Signal Handlers

func _on_state_changed() -> void:
	if _view != null and _state != null:
		_view.render_state(_state)


func _on_log_appended(bbcode_line: String) -> void:
	if _view != null:
		_view.append_log_line(bbcode_line)


func _on_guard_sight_toggle_requested() -> void:
	if _service != null:
		_service.toggle_guard_enemy_sight()


func _on_guard_stun_requested() -> void:
	if _service != null:
		_service.trigger_guard_hit_stun()


func _on_guard_revert_requested() -> void:
	if _service != null:
		_service.revert_guard_previous_state()


func _on_alpha_damage_requested() -> void:
	if _service != null:
		_service.damage_slime_alpha()


func _on_alpha_heal_requested() -> void:
	if _service != null:
		_service.heal_slime_alpha()


func _on_alpha_distance_toggle_requested() -> void:
	if _service != null:
		_service.toggle_slime_alpha_distance()


func _on_bravo_profile_toggle_requested() -> void:
	if _service != null:
		_service.toggle_slime_bravo_profile()


func _on_rerun_verification_requested() -> void:
	if _service != null and _view != null and _state != null:
		if _state.log_appended.is_connected(_on_log_appended):
			_state.log_appended.disconnect(_on_log_appended)
		_service.run_verification_suite(true)
		_view.render_all_logs(_state.log_lines)
		_state.log_appended.connect(_on_log_appended)

#endregion
