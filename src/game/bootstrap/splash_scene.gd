class_name SplashScene
extends BaseScene

## 游戏首发闪屏与加载场景（Game Bootstrap Scene）。[br]
## 继承 [BaseScene]，负责呈现加载界面、进度条，并在启动完成后跳转至大厅场景。

@onready var _progress_bar: ProgressBar = $UI/CenterContainer/VBoxContainer/ProgressBar
@onready var _status_label: Label = $UI/CenterContainer/VBoxContainer/StatusLabel
@onready var _title_label: Label = $UI/CenterContainer/VBoxContainer/TitleLabel

var _bootstrapper: GameBootstrapper


func _ready() -> void:
	_bootstrapper = GameBootstrapper.new()
	_bootstrapper.progress_updated.connect(_on_progress_updated)


func _on_enter(_params: Dictionary = {}) -> void:
	if _progress_bar != null:
		_progress_bar.value = 0.0
	if _status_label != null:
		_status_label.text = "Loading..."
	
	_run_bootstrap()


func _run_bootstrap() -> void:
	var result := await _bootstrapper.start_boot_sequence()
	if result.is_ok():
		# 稍微延迟 0.1 秒让进度条拉满动效自然平滑
		await get_tree().create_timer(0.15).timeout
		if App.scene != null:
			App.scene.replace(GameConstants.SCENE_LOBBY)
	else:
		if _status_label != null:
			_status_label.text = "Startup Error: %s" % result.error_message()


func _on_progress_updated(progress: float, step_name: String) -> void:
	if _progress_bar != null:
		_progress_bar.value = progress * 100.0
	if _status_label != null:
		_status_label.text = step_name
