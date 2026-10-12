# Game · Bootstrap (两阶段启动与加载管线)

> 游戏端唯一启动入口。负责呈现 Splash 动画、总控**两阶段启动流水线 (Two-Phase Pipeline)**，完成后平滑路由至大厅主选单。

```text
src/game/bootstrap/
├── _doc_bootstrap.md            # 本架构与流程规范文档
├── game_bootstrapper.gd         # [总控门面] 两阶段启动总调度器 (GameBootstrapper)
│
├── pipeline/                    # [启动管线域] 纯逻辑执行引擎 (可脱离 UI 独立运行)
│   ├── boot_context.gd          # 启动共享上下文 (BootContext: 数据传递与毫秒级耗时指标)
│   └── phases/                  # [启动阶段集合] 遵从单复数黄金法则
│       ├── base_boot_phase.gd   # 阶段抽象基类 (BaseBootPhase)
│       │
│       ├── core/                # 阶段一：内核启动域 (单数)
│       │   └── core_boot_phase.gd # Framework 12 大底层技术服务装配
│       │
│       └── business/            # 阶段二：业务启动域 (单数)
│           ├── business_boot_phase.gd # 业务启动编排器
│           └── steps/           # [业务子任务切片] 链式单一职责微任务
│               ├── base_boot_step.gd      # 步骤抽象基类 (BaseBootStep)
│               ├── load_config_step.gd    # 步骤 1: 静态策划数值配置载入
│               ├── load_profile_step.gd   # 步骤 2: 玩家存档解析与自愈
│               ├── apply_settings_step.gd # 步骤 3: 系统偏好与音频生效
│               └── init_state_step.gd     # 步骤 4: 全局业务状态广播
│
└── scene/                       # [表现层] 闪屏与加载画面 (对齐项目 Scene 规范)
	├── splash_scene.gd          # 场景控制器 (继承 BaseScene，生命周期驱动)
	└── splash_scene.tscn        # 场景排版文件 (设置为主场景 run/main_scene)
```

---

## 核心设计：两阶段流水线架构 (Two-Phase Pipeline)

为了将**纯技术基建**与**上层玩法业务**彻底解耦，系统将启动过程严格切分为两大离散阶段，并由 `BootContext` 进行状态与性能指标串联：

```mermaid
flowchart TD
	Splash[SplashScene 启动] --> Boot[GameBootstrapper.start_boot_sequence]
	
	subgraph Phase1 ["【阶段一】游戏内核组件加载 (CoreBootPhase - 权重 50%)"]
		P1Start[触发 App.bootstrap] --> P1Steps[顺序装配 12 大底层技术服务]
		P1Steps --> P1Order["Env → Logger → Time → Asset → Haptic<br>→ Network → Storage → Locale<br>→ Scene → UI → Audio → Video"]
		P1Order --> P1Done[纯技术基建底座完全就绪]
	end
	
	subgraph Phase2 ["【阶段二】游戏业务启动加载 (BusinessBootPhase - 权重 50%)"]
		P2Step1["1. LoadConfigStep<br>(静态策划数值配置载入)"] --> P2Step2["2. LoadProfileStep<br>(玩家本地/云端存档解析自愈)"]
		P2Step2 --> P2Step3["3. ApplySettingsStep<br>(系统偏好与音频生效)"]
		P2Step3 --> P2Step4["4. InitStateStep<br>(全局业务就绪广播)"]
	end

	Boot --> Phase1
	Phase1 --> Phase2
	Phase2 --> Route[平滑路由至主场景 App.scene.replace(LOBBY)]
```

---

## 架构优势与设计原则

1. **引擎逻辑与视图展现物理隔离**：
   - `pipeline/` 下的启动管线不依赖任何特定 UI 控件，可被 **CI/CD 无头测试**、**自动化单元测试** 或 **游戏内注销切换账号** 随时调用；
   - 闪屏场景收敛在 `scene/`，未来替换节日主题闪屏或精简加载条时，管线核心代码零侵入。
2. **微任务切片（Steps 模式）抵御业务膨胀**：
   - 阶段二被拆解为 `steps/` 目录下独立的无状态微任务；
   - 每个步骤支持记录微秒级执行耗时指标（存入 `BootContext`），未来新增“版本热更检查”、“敏感词库拉取”仅需新增对应 Step 文件，完全符合开闭原则（OCP）。
3. **单复数黄金法则自洽**：
   - 系统域 `pipeline/`、`scene/`、`core/`、`business/` 为单数；
   - 集合容器 `phases/`、`steps/` 为复数。

---

## 接口与信号契约

`GameBootstrapper` 对外提供标准化进度与阶段信号：

| 信号 | 参数 | 说明 |
| :--- | :--- | :--- |
| `phase_started` | `(phase: int, phase_name: String)` | 某个启动阶段正式开启 |
| `phase_step` | `(phase: int, step_name: String, phase_progress: float)` | 当前阶段内的微观子步骤递进 |
| `progress_updated` | `(overall_progress: float, current_phase: int, status_text: String)` | 全局归一化进度（0.0 ~ 1.0）及展示文案 |
| `phase_completed` | `(phase: int, phase_name: String)` | 阶段执行完毕 |
| `boot_completed` | `(metrics: Dictionary)` | 两阶段全部执行完毕，回传各阶段毫秒耗时指标 |
