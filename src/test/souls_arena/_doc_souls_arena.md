# Test · SoulsArena (3D 魂系演练场)

## 一、 模块结构 (MSVP)

```text
src/test/souls_arena/
├── _doc_souls_arena.md                                             # 模块架构文档
├── assets/
│   └── textures/                                                   # 暗黑金纹 SVG 图标与边框资产
├── model/                                                          # [Model] 纯数据与配置
│   ├── souls_combat_config.gd                                      #   数值与状态常量
│   ├── souls_fighter_stats.gd                                      #   角色属性、架势与多段连招模型
│   └── souls_arena_state.gd                                        #   响应式 HUD 与弹窗状态快照
├── service/                                                        # [Service] 享元 AI、音效合成与契约自检
│   ├── souls_boss_ai_controller.gd                                 #   Boss 9 分支享元行为树控制器
│   ├── souls_sound_service.gd                                      #   程序化物理建模音效服务 (App.audio)
│   ├── souls_verification_runner.gd                                #   6 项自动化契约自检执行器
│   └── souls_arena_service.gd                                      #   战场主循环、碰撞分离与胜负裁决
├── presenter/                                                      # [Presenter] 视图与输入协调
│   └── souls_arena_presenter.gd                                    #   连接 View、CameraRig3D 与 Service
└── view/                                                           # [View] 纯 .tscn 装配视图与子组件
	├── component/
	│   ├── stage/souls_arena_stage_3d.{gd,tscn}                    #   哥特古战场 3D 舞台
	│   ├── camera/souls_camera_rig_3d.{gd,tscn}                    #   第三人称跟随与锁定相机
	│   ├── fighter/                                                #   3D 骑士关节 Rig、飘字与实体
	│   │   ├── souls_knight_rig_3d.gd
	│   │   ├── souls_overhead_hud_3d.gd
	│   │   └── souls_fighter_actor.{gd,tscn}
	│   ├── hud/souls_combat_hud_bar.{gd,tscn}                      #   极简战斗 HUD
	│   ├── help_dialog/souls_keybind_help_dialog.{gd,tscn}         #   指南弹窗 [H]
	│   └── blueprint_dialog/                                       #   AST 蓝图与自检弹窗 [B / Tab]
	│       ├── souls_ast_blueprint_view.{gd,tscn}
	│       └── souls_blueprint_dialog.{gd,tscn}
	└── scene/arena/souls_arena_{view.gd,scene.gd,scene.tscn}       #   主场景入口
```

## 二、 核心机制摘要

- **3D 操控与三段连击**：`WASD` 3D 走位，`Space` 8 向翻滚（`0.30s` 无敌帧，支持后摇取消），`右键 / K` `0.18s` 弹反与举盾格挡，`左键 / J` 三段进阶连击（斜斩 -> 反手斩 -> 黄金霸体破军劈，支持预输入缓冲）及破防处决。
- **Boss 享元行为树 (`BTGraphDef`)**：涵盖响应式闪避、振刀格挡、三连狂斩、突进跳劈、霸体快慢刀悬停二连、红光不可防旋风斩与收刀后撤步对峙。
- **纯净 `.tscn` 视图**：所有 UI 节点与 SVG 纹理均直接在 `.tscn` 场景树内静态装配，通过 `%UniqueName` 绑定。
