# Display & Graphics Test Module (显示与画质工业化控制测试模块)

> 本模块用于验证工业级游戏屏幕控制与画质档位联动体系，严格遵循 [`_doc_test.md`](file:///d:/code/GodotProject/slacker-survivors/src/test/_doc_test.md) 的 **MSVP 交互模块模式** 与 [`_doc_game.md`](file:///d:/code/GodotProject/slacker-survivors/src/game/_doc_game.md) 的 **`view/scene/<domain>/` + `view/component/<domain>/`** 单元目录规范。

---

## 一、 架构目录树

```text
src/test/display/
├── _doc_display.md                                  # 本模块说明文档
├── model/
│   ├── display_enter_params.gd                      # 页面进入强类型入参契约 (extends BaseParams)
│   ├── settings_result_params.gd                    # 设置页返回大厅结果契约 (extends BaseParams)
│   ├── confirm_dialog_params.gd                     # 15秒切屏确认弹窗入参契约 (extends BaseParams)
│   └── display_test_state.gd                        # 响应式显示与画质状态模型 (extends RefCounted)
├── service/
│   └── display_test_service.gd                      # 窗口切换、快照回滚与画质联动服务 (extends RefCounted)
├── presenter/
│   ├── display_lobby_presenter.gd                   # 大厅页协调器 (extends RefCounted)
│   └── display_settings_presenter.gd                # 设置页协调器 (extends RefCounted)
└── view/
	├── scene/
	│   ├── lobby/
	│   │   ├── display_lobby_scene.tscn             # 大厅主场景 (声明式极简 UI)
	│   │   ├── display_lobby_scene.gd               # 大厅场景生命周期 (extends BaseScene)
	│   │   └── display_lobby_view.gd                # 大厅被动视图 (extends BaseView)
	│   └── settings/
	│       ├── display_settings_scene.tscn          # 设置子场景 (声明式简约单卡片表单)
	│       ├── display_settings_scene.gd            # 设置场景生命周期 (extends BaseScene)
	│       └── display_settings_view.gd             # 设置页被动视图 (extends BaseView)
	└── component/
		└── confirm/
			├── display_confirm_dialog.tscn          # 15秒切屏确认弹窗场景
			└── display_confirm_dialog.gd            # 15秒倒计时确认弹窗 (extends BaseDialog)
```

---

## 二、 核心验证项

1. **双页面压栈/弹栈路由流转**：
   - 大厅页 (`DisplayLobbyScene`) 通过 `App.scene.push_scene()` 跳转设置页 (`DisplaySettingsScene`)。
   - 设置页通过 `App.scene.pop_scene(SettingsResultParams)` 返回大厅页并触发 `_on_resume` 同步最新显示摘要。
2. **窗口模式与分辨率实时切换 + 15 秒自动还原保护**：
   - 支持窗口模式 (`WINDOWED`)、无边框全屏 (`BORDERLESS`)、全屏 (`FULLSCREEN`)、独占全屏 (`EXCLUSIVE_FULLSCREEN`) 及显示器安全分辨率列表切换。
   - 切屏或修改分辨率后弹出 `DisplayConfirmDialog`，15 秒未确认或按下 `ESC` 自动回滚至变更前快照。
3. **画质预设与细分项双向联动**：
   - 选择 `低 / 中 / 高 / 极高` 档位自动同步 MSAA、后处理抗锯齿与 3D 渲染倍率。
   - 单独修改任意细分项自动将画质档位切换为 `自定义 (CUSTOM)`。
4. **全局安全区比例与设计宽高比锁定**：
   - 支持调节 `HUD 安全区比例`（`100% / 95% / 90% / 85%` 四周对称向内留白）与 `安全区设计宽高比`（自适应全屏 vs 锁定项目基准设计宽高比居中安全框），`Background` 保持 100% 铺满而 `BaseView` 实时响应内缩。

---

## 三、 运行方式

在 Godot 编辑器中打开 [`display_lobby_scene.tscn`](file:///d:/code/GodotProject/slacker-survivors/src/test/display/view/scene/lobby/display_lobby_scene.tscn) 并按 `F6` 即可直接运行测试。
