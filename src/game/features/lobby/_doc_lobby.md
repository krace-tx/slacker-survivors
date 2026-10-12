# Feature · Lobby (大厅模块)

> 游戏主城与大厅入口。采用严格的 MSVP 架构进行子模块划分。

```text
src/game/features/lobby/
├── _doc_lobby.md                # 本文档
└── main_menu/                   # 主选单子模块 (MSVP 架构)
    ├── lobby_menu_model.gd      # [M] 数据模型 (金币、等级、最高存活时间)
    ├── lobby_menu_service.gd    # [S] 业务服务 (开始战斗检查、存档同步、补给领取)
    ├── lobby_menu_view.gd       # [V] 界面视图 (继承 BaseUIView，UI 节点与点击事件)
    ├── lobby_menu_presenter.gd  # [P] 表现调度 (胶水层连接 View 与 Service/Model)
    ├── lobby_scene.gd           # 场景脚本 (继承 BaseScene，生命周期管理与 MSVP 组装)
    └── lobby_scene.tscn         # 场景文件
```

## 数据与事件流 (MSVP Flow)
```text
[用户点击开始战斗] 
       │
       ▼
1. View: lobby_menu_view.start_battle_pressed 信号发出
       │
       ▼
2. Presenter: lobby_menu_presenter 接收信号，调用 Service
       │
       ▼
3. Service: lobby_menu_service.request_start_battle() 校验规则并路由场景
       │
       ▼
[进入战斗场景 battle_scene]
```
