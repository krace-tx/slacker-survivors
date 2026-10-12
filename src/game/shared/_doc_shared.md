# Game · Shared (跨模块共享基础层)

> 游戏业务层全模块通用的基础设施、领域基类、常量字典与跨模块事件总线规范。

```text
src/game/shared/
├── _doc_shared.md                # 本文档
├── msvp/                         # MSVP 架构通用抽象基类
│   ├── game_model.gd             # Model 基类 (状态存储与数据变更信号)
│   ├── game_service.gd           # Service 基类 (业务逻辑、规则校验与存储读写)
│   ├── game_presenter.gd         # Presenter 基类 (View <-> Model/Service 调度中介)
│   └── game_view_contract.gd     # View 规范契约
├── constants/
│   └── game_constants.gd         # 全局静态场景路径、存档 Key、音频分组常量
└── events/
    └── game_events.gd            # 跨模块解耦事件字符串常量
```

## 核心设计要点
1. **MSVP 纯净抽象**：
   - 规定 `GameModel` 绝不能引用 UI 节点；
   - 规定 `GameService` 绝不能直接修改 View 控件；
   - 规定 `GamePresenter` 负责粘合并保持生命周期安全。
2. **跨模块弱依赖**：
   - 模块与模块之间杜绝直接交叉 import 对方的内部类，统一通过 `Bus.emit(GameEvents.XXX, payload)` 通讯。
