# Feature · Battle (战斗功能模块)

> 游戏核心局内战斗系统。遵循清晰的 MSVP 架构进行子模块划分。

```text
src/game/features/battle/
├── _doc_battle.md                     # 本文档
├── battle_scene.gd                    # 战斗场景生命周期管理 (继承 BaseScene)
├── battle_scene.tscn                  # 战斗主场景
├── hud/                               # [子模块 1] 战斗 HUD (MSVP 架构)
│   ├── battle_hud_model.gd            # [M] 战斗数据模型 (生命值、经验、等级、时间、杀敌数)
│   ├── battle_hud_service.gd          # [S] 业务服务 (伤害结算、经验累加、升级判定公式)
│   ├── battle_hud_view.gd             # [V] 界面视图 (继承 BaseUIView，血条、经验条、数字)
│   └── battle_hud_presenter.gd        # [P] 表现调度 (中介者同步 Model 与 View)
└── upgrade_selection/                 # [子模块 2] 肉鸽升级选卡弹窗 (MSVP 架构)
    ├── upgrade_selection_model.gd     # [M] 选卡数据模型 (3 张待选技能卡数据、刷新次数)
    ├── upgrade_selection_service.gd   # [S] 业务服务 (卡池洗牌、权重抽取、被动技能注入)
    ├── upgrade_selection_dialog.gd    # [V] 弹窗视图 (继承 BaseDialog，卡牌排版与选择事件)
    ├── upgrade_selection_dialog.tscn  # 弹窗场景文件
    └── upgrade_selection_presenter.gd # [P] 表现调度 (处理选卡与关闭弹窗流程)
```

## 子模块协作机制
1. **经验积累与升级触发**：
   - 击杀怪物获取经验时调用 `BattleHudService.add_experience(exp)`；
   - 经验达标升级，Service 触发事件 `Bus.emit(GameEvents.BATTLE_LEVEL_UP)`；
2. **弹窗激活与 Presenter 组装**：
   - `BattleScene` 监听该事件，调用 `DialogManager.open()` 打开 `UpgradeSelectionDialog`；
   - 动态装配 `UpgradeSelectionPresenter`，驱动选卡并自动应用卡牌加成。
