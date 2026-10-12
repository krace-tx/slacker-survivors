class_name GameBootstrapper
extends RefCounted

## 游戏业务层启动器与两阶段装配调度总控。[br]
##
## 严格分为两大独立阶段：
## - 阶段一 (CORE)：游戏内核的启动组件加载 (Framework 12 大底层技术服务)
## - 阶段二 (BUSINESS)：游戏业务启动加载 (静态数据、用户存档、音视频偏好、状态就绪)

enum Phase {
	IDLE = 0,
	CORE = 1,
	BUSINESS = 2,
	COMPLETED = 3,
}

signal phase_started(phase: int, phase_name: String)
signal phase_step(phase: int, step_name: String, phase_progress: float)
signal progress_updated(overall_progress: float, current_phase: int, status_text: String)
signal phase_completed(phase: int, phase_name: String)
signal boot_completed(metrics: Dictionary)

const CORE_WEIGHT: float = 0.5
const BUSINESS_WEIGHT: float = 0.5

var _core_phase: CoreBootPhase
var _business_phase: BusinessBootPhase
var _context: BootContext
var _current_phase: int = Phase.IDLE


func _init() -> void:
	_context = BootContext.new()
	_core_phase = CoreBootPhase.new()
	_business_phase = BusinessBootPhase.new()

	_core_phase.step_changed.connect(func(step_name: String, step_progress: float):
		var overall := step_progress * CORE_WEIGHT
		phase_step.emit(Phase.CORE, step_name, step_progress)
		progress_updated.emit(overall, Phase.CORE, "【阶段 1/2 内核加载】%s" % step_name)
	)

	_business_phase.step_changed.connect(func(step_name: String, step_progress: float):
		var overall := CORE_WEIGHT + (step_progress * BUSINESS_WEIGHT)
		phase_step.emit(Phase.BUSINESS, step_name, step_progress)
		progress_updated.emit(overall, Phase.BUSINESS, "【阶段 2/2 业务启动】%s" % step_name)
	)


## 执行完整的两阶段启动流水线
## @return 返回 Result 封装
func start_boot_sequence() -> Result:
	# ----------------------------------------------------
	# 阶段一：游戏内核的启动组件加载 (Phase 1: Core)
	# ----------------------------------------------------
	_current_phase = Phase.CORE
	phase_started.emit(Phase.CORE, _core_phase.get_phase_name())
	progress_updated.emit(0.0, Phase.CORE, "【阶段 1/2 内核加载】正在装配基础服务...")

	var core_res: Result = await _core_phase.execute(_context)
	if core_res.is_err():
		return core_res
	phase_completed.emit(Phase.CORE, _core_phase.get_phase_name())

	# ----------------------------------------------------
	# 阶段二：游戏的业务启动加载 (Phase 2: Business)
	# ----------------------------------------------------
	_current_phase = Phase.BUSINESS
	phase_started.emit(Phase.BUSINESS, _business_phase.get_phase_name())
	progress_updated.emit(CORE_WEIGHT, Phase.BUSINESS, "【阶段 2/2 业务启动】正在装载游戏数据...")

	var biz_res: Result = await _business_phase.execute(_context)
	if biz_res.is_err():
		return biz_res
	phase_completed.emit(Phase.BUSINESS, _business_phase.get_phase_name())

	# ----------------------------------------------------
	# 两阶段装配完成
	# ----------------------------------------------------
	_current_phase = Phase.COMPLETED
	var total_time := _context.finish()
	progress_updated.emit(1.0, Phase.COMPLETED, "启动完成 (耗时 %d ms)，正在进入游戏..." % total_time)
	boot_completed.emit(_context.get_metrics())
	return Result.ok()


## 获取当前所处的启动阶段
func get_current_phase() -> int:
	return _current_phase


## 获取启动上下文数据
func get_context() -> BootContext:
	return _context
