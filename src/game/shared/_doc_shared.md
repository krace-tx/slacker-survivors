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
├── events/
│   └── game_events.gd            # 跨模块解耦事件字符串常量
└── components/                   # 业务通用可复用控件库 (UI / 交互组件)
    └── ui/
        ├── base_texture_button.gd # 通用贴图按钮 (缩放/音效/震动/滑动中继)
        ├── base_dialog.gd         # 模态弹窗业务基类 (进退场补间/点击背景遮罩自闭)
        ├── dialog_manager.gd      # 模态弹窗调度器 (暗色遮罩/LIFO堆栈/返回键监听)
        └── toast_manager.gd       # 轻量飘字提示组件 (居中浮动与渐变销毁)
```

## 核心设计要点
1. **MSVP 纯净抽象**：
   - 规定 `GameModel` 绝不能引用 UI 节点；
   - 规定 `GameService` 绝不能直接修改 View 控件；
   - 规定 `GamePresenter` 负责粘合并保持生命周期安全。
2. **跨模块弱依赖**：
   - 模块与模块之间杜绝直接交叉 import 对方的内部类，统一通过 `Bus.emit(GameEvents.XXX, payload)` 通讯。
