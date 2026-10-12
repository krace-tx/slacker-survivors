# Game · Bootstrap (游戏启动与加载管线)

> 游戏端唯一启动入口。负责呈现 Splash 动画、调度 Framework 底层装配、读入玩家本地存档、预热音频并路由至大厅主选单。

```text
src/game/bootstrap/
├── _doc_bootstrap.md        # 本文档
├── game_bootstrapper.gd     # 启动调度器 (GameBootstrapper)
├── splash_scene.gd          # 闪屏场景脚本 (继承 BaseScene)
└── splash_scene.tscn        # 闪屏场景文件 (设置为主场景 run/main_scene)
```

## 启动流水线顺序
```text
[SplashScene._on_enter]
	│
	▼
[GameBootstrapper.start_boot_sequence()]
	├── 1. await App.bootstrap() (Framework 11 大模块依赖装配)
	├── 2. _load_user_profile()   (App.storage 读写本地存档)
	├── 3. _warmup_systems()      (音频、事件总线预热)
	└── 4. progress_updated 信号驱动进度条动效
	│
	▼
[App.scene.replace(GameConstants.SCENE_LOBBY)] (进入游戏主大厅)
```
