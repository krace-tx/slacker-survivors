# Test · Storage (`src/test/storage/`)

> 针对 `App.storage` 全局核心存档加密（`set_save_encryption`）、`GameEnvConfig` 环境开关与 `OS.get_unique_id()` 硬件设备指纹绑定的 **声明式 `.tscn` 组件化 MSVP 交互透视演练场 + 9 项无头自动化契约验证模块**。

---

## 一、 模块分层与声明式 `.tscn` 预制体树 (MSVP)

```text
src/test/storage/
├── _doc_storage.md                                             # 本说明文档
├── storage_test.tscn                                           # 快捷启动入口（继承 storage_playground_scene.tscn）
├── model/
│   ├── storage_demo_save_model.gd                              # 零加密样板核心存档模型 (StorageItem.for_save)
│   ├── storage_demo_prefs_model.gd                             # 设备偏好设置模型 (StorageItem.for_config，自动豁免加密)
│   └── storage_demo_state.gd                                   # 演练场视图状态快照 (*State)
├── service/
│   └── storage_demo_service.gd                                 # 9 项自动化断言、策略开关切换、篡改/替档模拟与磁盘字节采样
├── presenter/
│   └── storage_demo_presenter.gd                               # View <-> Service 双向胶水协调器
└── view/
	├── component/
	│   ├── pill/                                               # [叶组件] 顶栏状态胶囊徽章
	│   │   ├── storage_stat_pill.tscn
	│   │   └── storage_stat_pill.gd
	│   ├── header/                                             # [区域面板] 顶部状态栏（预实例化 3 枚 StatPill）
	│   │   ├── storage_header_bar.tscn
	│   │   └── storage_header_bar.gd
	│   ├── control/                                            # [区域面板] 环境策略开关与 6 项攻防实验操作矩阵
	│   │   ├── storage_control_panel.tscn
	│   │   └── storage_control_panel.gd
	│   ├── inspector/                                          # [区域面板] 磁盘物理文件实时透视镜（对比 .sav 密文与 .json 明文）
	│   │   ├── storage_inspector_panel.tscn
	│   │   └── storage_inspector_panel.gd
	│   └── report/                                             # [区域面板] 9 项自动化断言报告与操作时间线
	│       ├── storage_report_panel.tscn
	│       └── storage_report_panel.gd
	└── scene/
		└── playground/                                         # [主场景单元] 顶层路由舞台
			├── storage_playground_scene.tscn
			├── storage_playground_scene.gd
			└── storage_playground_view.gd
```

---

## 二、 9 项自动化契约验证清单

1. **`[1/9]` `env_*.tres` 多环境资源装载与安全开关解析**（`local/dev/staging` 兼容旧明文升级，`prod` 关闭防降级）。
2. **`[2/9]` `GameEnvService.setup_and_activate()` 启动期一次性幂等注册激活**。
3. **`[3/9]` `StorageItem.for_save` 零配置自动 `FWKE` 认证加密 + ZSTD 压缩 + 解密往返一致性**。
4. **`[4/9]` `StorageItem.for_config` 设备偏好自动豁免加密，保持可读明文 JSON**。
5. **`[5/9]` 同机器跨槽位拷贝重放拦截**（按 `key_id` 独立加盐派生密钥，将 A 档覆盖 B 档返回 `Storage.DecryptFailed`）。
6. **`[6/9]` 硬件设备指纹绑定拦截**（跨机器或指纹不匹配返回 `Storage.DecryptFailed`）。
7. **`[7/9]` 单文件字节篡改 `.sav.bak` 自动容灾自愈**。
8. **`[8/9]` 主备双文件篡改防离线云端吞错**（即使绑定离线 Steam Cloud 仍严格返回 `Storage.DecryptFailed`）。
9. **`[9/9]` 环境开关动态关闭写明文、开发期平滑升级密文与生产期防明文降级拦截**。

---

## 三、 运行方式

- **编辑器交互体验**：在 Godot 编辑器中打开 `res://src/test/storage/storage_test.tscn`，按 **`F6`** 直接运行，可实时点击开关对比磁盘上的十六进制 `FWKE` 密文与明文 JSON。
- **命令行无头自检**：
  ```powershell
  & "D:/software/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe" --headless --path . res://src/test/storage/storage_test.tscn -- --storage-test-auto-quit
  ```
