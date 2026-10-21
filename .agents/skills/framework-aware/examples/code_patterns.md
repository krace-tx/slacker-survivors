# Skill Wiki · 框架编码正反范例库 (Code Patterns)

> **Wiki 定位**：通过黄金示例 (Golden Patterns) 与反模式 (Anti-Patterns) 的直观对比，指导 Agent 编写完全贴合框架约定的规范代码。

---

## 范例 1：场景系统生命周期

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误：直接继承 Node，使用 Godot 原生生命周期，无法被 App.scene 管理
class_name BattleScene extends Node

func _ready() -> void:
    # 臆造场景初始化，未接入框架传参和生命周期
    print("Battle started")
```

### 黄金范式 (Golden Pattern)
```gdscript
# 正确：继承 BaseScene，重写 4 大生命周期钩子，通过 App.logger 记录
class_name BattleScene extends BaseScene

func _on_enter(params: Dictionary = {}) -> void:
    App.logger.info("Battle", "关卡场景进入，注入参数: %s" % str(params))
    # 初始化关卡逻辑

func _on_exit() -> void:
    App.logger.info("Battle", "关卡场景退出，释放临时资源")

func _on_pause() -> void:
    App.logger.info("Battle", "关卡暂停")

func _on_resume() -> void:
    App.logger.info("Battle", "关卡恢复")
```

---

## 范例 2：UI 视图编排与业务弹窗

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误 1：UI 根节点继承 Control 并直接写业务弹窗逻辑
# 错误 2：将弹窗放到 framework/modules/ui 中
class_name MyUIPanel extends Control

func open_dialog() -> void:
    var dialog = preload("res://src/framework/modules/ui/my_dialog.tscn").instantiate()
    add_child(dialog)
```

### 黄金范式 (Golden Pattern)
```gdscript
# 1. 场景内 UI 根节点：继承 BaseView，节点命名为 UI
class_name BattleUIView extends BaseView

# 2. 弹窗类：继承 BaseDialog（位于 src/game/shared/component/dialog/），业务弹窗放在 features/<feature>/view/
class_name SettingsDialog extends BaseDialog

func _on_dialog_opened() -> void:
    App.logger.info("SettingsDialog", "设置弹窗已打开")

# 3. 业务调用弹窗：通过 DialogManager 统一调度
func _on_settings_button_pressed() -> void:
    DialogManager.open("res://src/game/features/settings/view/settings_dialog.tscn")
```

---

## 范例 3：按钮点击反馈与动效

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误：使用原生 TextureButton，手写 Tween 缩放和 AudioServer 播放，代码臃肿且全项目风格不一
@onready var btn: TextureButton = $StartButton

func _ready() -> void:
    btn.pressed.connect(func():
        AudioServer.play(...) # 臆造或侵入式音频调用
        var tw = create_tween()
        tw.tween_property(btn, "scale", Vector2(0.9, 0.9), 0.1)
        tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1)
        _on_start_game()
    )
```

### 黄金范式 (Golden Pattern)
```gdscript
# 正确：使用 BaseTextureButton（位于 src/game/shared/component/button/）
# 基类自动处理了：缩放反馈、悬停动画、禁用态着色、点击音效与触感震动
@onready var btn: BaseTextureButton = $StartButton

func _ready() -> void:
    btn.pressed.connect(_on_start_game)
```

---

## 范例 4：全局网络调用与参数契约

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误 1：使用已废弃的 App.network 别名或原生 HTTPRequest 节点
# 错误 2：裸拼字典传参，无类型校验
func fetch_player_data(player_id: String) -> void:
    var dict = {"id": player_id}
    var http = HTTPRequest.new()
    add_child(http)
    # 裸写请求和回调解析...
```

### 黄金范式 (Golden Pattern)
```gdscript
# 1. 契约实体：继承 BaseParams（位于 src/framework/infra/param/）
class_name PlayerFetchParams extends BaseParams

var player_id: String = ""

# 2. 网络调用：统一面向 App.net 编程，接收强类型 Result
func fetch_player_data(params: PlayerFetchParams) -> void:
    var result := await App.net.post_request("/api/v1/player", params.to_dict())
    if result.is_err():
        App.logger.error("PlayerService", "[%s] 获取玩家信息失败: %s" % [result.error_code(), result.error_message()])
        return
    
    var data: Dictionary = result.value
    App.logger.info("PlayerService", "成功获取玩家数据: %s" % str(data))
```

---

## 范例 5：工具函数调用

### 典型反模式 (Anti-Pattern)
```gdscript
# 错误：自己手写递归深度遍历查找子节点
func find_child_recursive(parent: Node, name: String) -> Node:
    for child in parent.get_children():
        if child.name == name:
            return child
        var found = find_child_recursive(child, name)
        if found: return found
    return null
```

### 黄金范式 (Golden Pattern)
```gdscript
# 正确：直接使用框架二级工具类 NodeUtils（位于 src/framework/util/node/node_utils.gd）
var target_node := NodeUtils.find_child_recursive(self, "HealthBar")
```
