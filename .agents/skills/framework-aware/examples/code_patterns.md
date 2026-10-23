# Skill Wiki · 框架编码正反范例库 (Code Patterns)

> **Wiki 定位**：通过黄金范式 (Golden Patterns) 与反模式 (Anti-Patterns) 的直观对比，指导 Agent 编写 100% 符合架构铁律与静态类型规范的代码。

---

## 范例 1：场景生命周期、强类型入参与 `TaskScope` 并发守卫

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误 1：直接继承 Node，无法接入 App.scene 历史栈与转场管线
# 错误 2：使用裸 Dictionary 传参，且使用裸 create_timer 引发退场后 UAF 崩溃
# 错误 3：残留原生 print() (触发 R13 违规)
class_name BattleScene
extends Node

func _ready() -> void:
	print("Battle started")
	await get_tree().create_timer(1.0).timeout
	$UI.visible = true # 若 1 秒内玩家切走场景，此处直接 Use-After-Free 崩溃！
```

### 黄金范式 (Golden Pattern)
```gdscript
# 1. 强类型场景入参契约 (model/battle_enter_params.gd)
class_name BattleEnterParams
extends BaseParams

var stage_id: int = 1
var difficulty: int = 0


# 2. 顶层场景舞台 (view/scene/battle/battle_scene.gd)
class_name BattleScene
extends BaseScene

@onready var _ui: BattleView = $UI


func _on_enter(params: BaseParams = null) -> void:
	var enter_params: BattleEnterParams = params as BattleEnterParams
	var stage_id: int = enter_params.stage_id if enter_params != null else 1
	App.logger.info("Battle", "Enter stage %d" % stage_id)

	# 绑定宿主 task_scope：若等待期间场景退出，自动取消并返还 Async.Cancelled，杜绝 UAF
	if (await task_scope.sleep(0.5)).is_err():
		return
	_ui.set_View_visible(true)


func _on_exit() -> void:
	App.logger.info("Battle", "Exit stage")
```

---

## 范例 2：MSVP 视图拆分与模态弹窗调度 (`R05`)

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误 1：将 .tscn 平铺在 view/ 根目录，且在 View 内部直接读写 App.storage
# 错误 2：在 src/framework/ 下编写业务弹窗或绕过 DialogManager 直接 add_child
class_name BadSettingsPanel
extends Control

func _on_save_pressed() -> void:
	App.storage.write_async(...) # 违规：View 层严禁直接触碰存储或网络 I/O
	var dlg := preload("res://src/framework/modules/display/my_dialog.tscn").instantiate()
	add_child(dlg)
```

### 黄金范式 (Golden Pattern)
```gdscript
# 1. 场景内 UI 根节点 (view/scene/lobby/lobby_view.gd)：继承 BaseView，节点名固定为 UI
class_name LobbyView
extends BaseView

signal settings_requested

@onready var _settings_btn: BaseTextureButton = $SafeArea/SettingsButton


func _ready() -> void:
	super._ready()
	_settings_btn.pressed.connect(func() -> void: settings_requested.emit())


# 2. 业务弹窗预制体 (view/component/settings/settings_dialog.gd)：继承 BaseDialog
class_name SettingsDialog
extends BaseDialog

func _on_dialog_opened(_params: BaseParams = null) -> void:
	App.logger.info("SettingsDialog", "Opened")


# 3. 通过 DialogManager 统一打开（自动管理 UI 输入上下文压栈与防穿透）
func open_settings_dialog() -> void:
	await DialogManager.open("res://src/game/features/lobby/view/component/settings/settings_dialog.tscn")
```

---

## 范例 3：交互按钮反馈 (`BaseTextureButton`)

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误：使用原生 TextureButton 手写 Tween 缩放与 AudioServer 调用
@onready var _start_btn: TextureButton = $StartButton

func _ready() -> void:
	_start_btn.pressed.connect(func() -> void:
		var tw := create_tween()
		tw.tween_property(_start_btn, "scale", Vector2(0.9, 0.9), 0.08)
	)
```

### 黄金范式 (Golden Pattern)
```gdscript
# 正确：使用 BaseTextureButton（内置按压缩放 Tween、悬停高亮、SFX 音效与 Haptic 轻触震动）
@onready var _start_btn: BaseTextureButton = $StartButton

func _ready() -> void:
	_start_btn.pressed.connect(_on_start_pressed)
```

---

## 范例 4：本地沙盒持久化与二级架构域绑定 (`R16`)

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误 1：在 Service 或 View 中裸写 "user://..." 字符串字面量 (触发 R16 违规)
# 错误 2：使用原生 FileAccess 硬编码读写存档，绕过 .tmp/.bak 事务自愈与版本迁移
func save_talent_tree(data: Dictionary) -> void:
	var f := FileAccess.open("user://talent_save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
```

### 黄金范式 (Golden Pattern)
```gdscript
# 1. 仅在 model/*_model.gd 中声明 STORAGE_DOMAIN 并通过语义工厂构造 StorageItem
# 路径：src/game/features/talent/model/talent_tree_model.gd
class_name TalentTreeModel
extends BaseParams

## 二级架构域必须与所在 Feature 目录名 "talent" 逐字一致 (shared/ 下则为 &"shared")
const STORAGE_DOMAIN: StringName = &"talent"
const STORAGE_SUBJECT: StringName = &"tree"
const SCHEMA_VERSION: int = 1

var unlocked_ids: Array[int] = []


## 语义工厂自动映射至 user://saves/talent/tree.sav
static func storage_item() -> StorageItem:
	return StorageItem.for_save(STORAGE_DOMAIN, STORAGE_SUBJECT, SCHEMA_VERSION) \
		.with_compression(FileAccess.COMPRESSION_ZSTD) \
		.with_device_encryption("slacker.talent.v1")


# 2. 在 Service 层通过 App.storage 异步读写
func save_async(model: TalentTreeModel) -> Result:
	return await App.storage.write_async(TalentTreeModel.storage_item(), model.to_dict())
```

---

## 范例 5：框架模块显式构造注入与组合根装配 (`R08`, `R09`)

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误 1：未声明 MODULE_ID / REQUIRED_MODULES / OPTIONAL_MODULES (触发 R09 违规)
# 错误 2：在 src/framework/modules/ 内部直接调用 App.logger / App.asset (触发 R08 违规)
class_name BadAudioSystem
extends BaseAudioSystem

func play_sfx(path: String) -> void:
	var res := App.asset.get_cached(path)
	App.logger.info("Audio", "Playing %s" % path)
```

### 黄金范式 (Golden Pattern)
```gdscript
# 1. 模块主实现类显式声明依赖清单与构造函数注入
class_name AudioSystem
extends BaseAudioSystem

#region Module Dependency Manifest
const MODULE_ID: StringName = &"audio"
const REQUIRED_MODULES: Array[StringName] = []
const OPTIONAL_MODULES: Array[StringName] = [&"asset", &"logger"]
#endregion

var _asset: BaseAssetSystem = null
var _logger: BaseFrameworkLogger = null


func _init(asset: BaseAssetSystem = null, logger: BaseFrameworkLogger = null) -> void:
	_asset = asset
	_logger = logger


# 2. 在 FrameworkRuntime._assemble_modules_async() 中显式注入并由 _host.install() 核对拓扑契约
var audio := AudioSystem.new(asset, logger)
res = await _host.install(audio)
if res.is_err(): return res
```

---

## 范例 6：强类型 `Variant` 解包与全局 `class_name` 直呼 (`R12`, `R15`)

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误 1：对已声明 class_name 的脚本使用 preload 别名 (触发 R15 违规)
const _FileUtils = preload("res://src/framework/util/file/file_utils.gd")

func parse_response(res: Result, payload: Dictionary) -> void:
	# 错误 2：res.value 与 payload.get() 返回 Variant，直接用 := 会触发编译器类型推导报错 (R12)
	var tex := res.value
	var count := payload.get("count", 0)
```

### 黄金范式 (Golden Pattern)
```gdscript
func parse_response(res: Result, payload: Dictionary) -> void:
	# 1. 直接使用全局 class_name 调用工具方法
	var dir_res := FileUtils.ensure_dir(FileUtils.USER_CACHE_RES_DIR)
	if dir_res.is_err():
		return

	# 2. 从 Variant 容器取值时显式标注目标类型并使用 as 或类型转换函数
	var tex: Texture2D = res.value as Texture2D
	var count: int = int(payload.get("count", 0))
	var ratio: float = clampf(float(payload.get("ratio", 1.0)), 0.0, 1.0)
	if tex != null and count > 0 and ratio > 0.0:
		pass
```
