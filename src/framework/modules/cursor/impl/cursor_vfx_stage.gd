class_name CursorVfxStage
extends Node2D

## 微内核 ③：顶层粒子与特效伴随舞台（Cursor Trail & Click Burst VFX Stage）。[br]
##
## [b]单一职责：[/b][br]
## 1. [b]移动星尘拖尾（Trail VFX）[/b]：随鼠标移动实时发射星尘粒子与丝滑渐变轨迹（`Line2D`），静止超过 `60ms` 或移出窗口自动停止；[br]
## 2. [b]点击爆裂环形对象池（Click Burst Pool）[/b]：预分配 8 个槽位（Ring-Buffer Pool），左键点击时在点击坐标处触发扩散波纹与径向火花粒子，零运行时 `instantiate/queue_free` 开销；[br]
## 3. 与指针本体是硬件光标还是软件光标完全正交解耦。

#region Constants & State
const CLICK_POOL_SIZE: int = 8
const TRAIL_MAX_POINTS: int = 14
const TRAIL_IDLE_STOP_SEC: float = 0.065

var _trail_enabled: bool = false
var _click_enabled: bool = false
var _master_visible: bool = true
var _inside_window: bool = true

var _trail_color: Color = Color(0.42, 0.88, 1.0, 0.85)
var _click_color: Color = Color(1.0, 0.85, 0.35, 0.95)

var _trail_root: Node2D = null
var _trail_particles: CPUParticles2D = null
var _trail_ribbon: Line2D = null
var _trail_custom_node: Node2D = null
var _trail_points: Array[Vector2] = []
var _idle_timer: float = 1.0
var _last_mouse_pos: Vector2 = Vector2.ZERO

var _click_pool_root: Node2D = null
var _click_pool: Array[Dictionary] = [] ## [{"root": Node2D, "particles": CPUParticles2D, "ring": Line2D, "tween": Tween}]
var _pool_cursor: int = 0
var _total_bursts_spawned: int = 0
#endregion


#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 90
	_setup_trail_stage()
	_setup_click_pool()


func _process(delta: float) -> void:
	_idle_timer += delta
	var is_moving := _idle_timer <= TRAIL_IDLE_STOP_SEC and _trail_enabled and _master_visible and _inside_window
	if _trail_particles != null and _trail_particles.emitting != is_moving:
		_trail_particles.emitting = is_moving

	# 当鼠标静止时渐隐丝带轨迹点
	if not is_moving and not _trail_points.is_empty():
		_trail_points.pop_front()
		if _trail_ribbon != null:
			_trail_ribbon.points = PackedVector2Array(_trail_points)
#endregion


#region Public Control API
func apply_theme(theme: CursorThemeConfig) -> void:
	if theme == null:
		_trail_enabled = false
		_click_enabled = false
		if is_instance_valid(_trail_custom_node):
			_trail_custom_node.queue_free()
			_trail_custom_node = null
		_clear_trail()
		return
	_trail_enabled = theme.enable_trail_vfx
	_click_enabled = theme.enable_click_vfx
	_trail_color = theme.trail_color
	_click_color = theme.click_color

	if is_instance_valid(_trail_custom_node):
		_trail_custom_node.queue_free()
		_trail_custom_node = null
	if theme.trail_vfx_scene != null and _trail_root != null:
		var custom_inst := theme.trail_vfx_scene.instantiate() as Node2D
		if custom_inst != null:
			_trail_custom_node = custom_inst
			_trail_root.add_child(_trail_custom_node)

	if _trail_particles != null:
		_trail_particles.color = _trail_color
	if _trail_ribbon != null:
		_trail_ribbon.default_color = _trail_color
		var grad := Gradient.new()
		grad.set_color(0, Color(_trail_color.r, _trail_color.g, _trail_color.b, 0.0))
		grad.set_color(1, _trail_color)
		_trail_ribbon.gradient = grad

	for slot: Dictionary in _click_pool:
		var ptc: CPUParticles2D = slot.get("particles", null)
		if ptc != null:
			ptc.color = _click_color
		var ring: Line2D = slot.get("ring", null)
		if ring != null:
			ring.default_color = _click_color


func set_vfx_enabled(trail_on: bool, click_on: bool = true) -> void:
	_trail_enabled = trail_on
	_click_enabled = click_on
	if not _trail_enabled:
		_clear_trail()


func is_trail_enabled() -> bool:
	return _trail_enabled


func is_click_enabled() -> bool:
	return _click_enabled


func set_master_visible(vis: bool) -> void:
	_master_visible = vis
	visible = vis
	if not vis:
		_clear_trail()


func set_window_inside(inside: bool) -> void:
	_inside_window = inside
	if not inside:
		_clear_trail()


## 在鼠标移动事件 (`_input`) 中即时更新拖尾发射器坐标与丝带顶点。
func notify_mouse_moved(canvas_pos: Vector2) -> void:
	var dist_sq := canvas_pos.distance_squared_to(_last_mouse_pos)
	_last_mouse_pos = canvas_pos
	if _trail_root != null:
		_trail_root.position = canvas_pos

	if not _trail_enabled or not _master_visible or not _inside_window:
		return

	if dist_sq >= 4.0:
		_idle_timer = 0.0
		_trail_points.append(canvas_pos)
		if _trail_points.size() > TRAIL_MAX_POINTS:
			_trail_points.pop_front()
		if _trail_ribbon != null:
			_trail_ribbon.points = PackedVector2Array(_trail_points)


## 从 8 槽位环形对象池中取出一个闲置槽位，在点击坐标处触发水波纹扩散与径向火花粒子。
func trigger_click_burst(canvas_pos: Vector2) -> void:
	if not _click_enabled or not _master_visible or _click_pool.is_empty():
		return

	var target_pos := canvas_pos if (canvas_pos.x >= 0.0 and canvas_pos.y >= 0.0) else _last_mouse_pos
	var slot: Dictionary = _click_pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % _click_pool.size()
	_total_bursts_spawned += 1

	var slot_root: Node2D = slot["root"]
	var ptc: CPUParticles2D = slot["particles"]
	var ring: Line2D = slot["ring"]
	var prev_tw: Tween = slot.get("tween", null)
	if prev_tw != null and prev_tw.is_valid():
		prev_tw.kill()

	slot_root.position = target_pos
	slot_root.visible = true

	ptc.restart()
	ptc.emitting = true

	ring.scale = Vector2(0.25, 0.25)
	ring.modulate = Color(1.0, 1.0, 1.0, 0.95)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.45, 1.45), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	slot["tween"] = tw


func get_total_bursts_spawned() -> int:
	return _total_bursts_spawned
#endregion


#region Internal Stage & Pool Builders
func _setup_trail_stage() -> void:
	_trail_ribbon = Line2D.new()
	_trail_ribbon.name = "TrailRibbon"
	_trail_ribbon.width = 4.0
	_trail_ribbon.default_color = _trail_color
	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 0.0))
	width_curve.add_point(Vector2(1.0, 1.0))
	_trail_ribbon.width_curve = width_curve
	var grad := Gradient.new()
	grad.set_color(0, Color(_trail_color.r, _trail_color.g, _trail_color.b, 0.0))
	grad.set_color(1, _trail_color)
	_trail_ribbon.gradient = grad
	add_child(_trail_ribbon)

	_trail_root = Node2D.new()
	_trail_root.name = "TrailEmitterRoot"
	add_child(_trail_root)

	_trail_particles = CPUParticles2D.new()
	_trail_particles.name = "StardustTrailParticles"
	_trail_particles.emitting = false
	_trail_particles.amount = 24
	_trail_particles.lifetime = 0.36
	_trail_particles.local_coords = false
	_trail_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_trail_particles.emission_sphere_radius = 4.0
	_trail_particles.direction = Vector2(0.0, 1.0)
	_trail_particles.spread = 180.0
	_trail_particles.gravity = Vector2(0.0, 18.0)
	_trail_particles.initial_velocity_min = 12.0
	_trail_particles.initial_velocity_max = 38.0
	_trail_particles.scale_amount_min = 2.0
	_trail_particles.scale_amount_max = 4.5
	_trail_particles.color = _trail_color
	_trail_root.add_child(_trail_particles)


func _setup_click_pool() -> void:
	_click_pool_root = Node2D.new()
	_click_pool_root.name = "ClickBurstPool"
	add_child(_click_pool_root)

	var ring_pts := PackedVector2Array()
	var segments := 20
	var radius := 18.0
	for i in range(segments + 1):
		var ang := TAU * float(i) / float(segments)
		ring_pts.append(Vector2(cos(ang) * radius, sin(ang) * radius))

	for idx in range(CLICK_POOL_SIZE):
		var slot_root := Node2D.new()
		slot_root.name = "BurstSlot_%02d" % idx
		slot_root.visible = false
		_click_pool_root.add_child(slot_root)

		var ring := Line2D.new()
		ring.width = 2.2
		ring.default_color = _click_color
		ring.points = ring_pts
		slot_root.add_child(ring)

		var ptc := CPUParticles2D.new()
		ptc.emitting = false
		ptc.one_shot = true
		ptc.amount = 14
		ptc.lifetime = 0.28
		ptc.explosiveness = 0.95
		ptc.spread = 180.0
		ptc.gravity = Vector2.ZERO
		ptc.initial_velocity_min = 48.0
		ptc.initial_velocity_max = 115.0
		ptc.damping_min = 180.0
		ptc.damping_max = 260.0
		ptc.scale_amount_min = 2.5
		ptc.scale_amount_max = 5.0
		ptc.color = _click_color
		slot_root.add_child(ptc)

		_click_pool.append({
			"root": slot_root,
			"particles": ptc,
			"ring": ring,
			"tween": null,
		})


func _clear_trail() -> void:
	_trail_points.clear()
	if _trail_ribbon != null:
		_trail_ribbon.clear_points()
	if _trail_particles != null:
		_trail_particles.emitting = false
#endregion
