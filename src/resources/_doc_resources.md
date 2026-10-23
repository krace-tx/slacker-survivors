# Resources · 静态配置、策划表与引擎预设架构规范 (Resource & Configuration Standard)

> **适用范围**：`res://src/resources/` 下全部非视听媒体的静态配置、多语言字典、引擎系统预设、批量策划导表、游戏实体定义与关卡波次编排资源。
> **核心目标**：按**「配置生命周期（从冷启动到单局加载） × 职能用途」**六层正交划分，彻底解决传统 `configs + data` 语义重叠、导表与手调 `.tres` 混放、以及常驻配置与按需关卡资源生命周期不清的问题。
> **上位规范**：[`docs/godot_coding_standards.md`](../../docs/godot_coding_standards.md)（单复数黄金法则）、[`src/game/_doc_game.md`](../game/_doc_game.md)（业务层 `*Config` 数据后缀规范）、[`src/assets/_doc_assets.md`](../assets/_doc_assets.md)（视听媒体资产边界）。

---

## 一、 三大静态/动态数据域的顶层正交边界

| 顶层域 | 核心定性 | 生产者 | 运行期读写 | 承载内容 |
| :--- | :--- | :--- | :--- | :--- |
| **[`src/assets/`](../assets/_doc_assets.md)** | **视听感官媒体 (Look & Feel)** | 美术 / 动效 / 音频 | PCK 只读 | 贴图、Spine、3D 模型、材质、Shader、字体、Theme、音视频（替换它们不改变玩法规则与数值） |
| **`src/resources/`** | **规则、配表与预设 (Rules, Data & Presets)** | 策划 / 系统 / 本地化 | PCK 只读 | 环境配置、多语言包、引擎系统预设、二维策划导表、自定义 `Resource` 实体定义、关卡波次编排 |
| **[`user://`](../framework/modules/storage/_doc_storage.md)** | **玩家运行时状态 (Runtime Persistence)** | 玩家运行期产生 | 沙盒可读写 | 本地硬件偏好（`user://config/`）、玩家进度存档与云同步（`user://saves/`） |

---

## 二、 六大生命周期目录拓扑 (`src/resources/`)

`src/resources/` 按游戏运行生命周期从早到晚划分为 **6 个复数职能容器**：

```text
src/resources/
├── _doc_resources.md                # 本规范文档
│
├── envs/                            # [阶段 1 · 环境配置] 决定连哪个服、开不开调试、渠道与网关参数
│   ├── env_local.tres               #   本机开发配置
│   ├── env_staging.tres             #   预发测试服配置
│   └── env_prod.tres                #   正式生产环境配置
│
├── locales/                         # [阶段 2 · 多语言 i18n] 决定全局文案翻译 (对接 App.locale)
│   ├── loc_locale_config.tres       #   LocaleConfig 实例 (默认语言 + 主 CSV 引用)
│   ├── loc_ui_common.csv            #   通用 UI 多语言源表 (及引擎导入生成的 .translation)
│   └── loc_battle_skills.csv        #   战斗与技能多语言词条表
│
├── presets/                         # [阶段 3 · 引擎与全局系统预设] 决定引擎底层管线、曲线与全局平衡常数
│   ├── prs_audio_bus_layout.tres    #   全局音频总线布局 (Master / BGM / SFX / VOX / AMB)
│   ├── prs_shader_warmup_boot.tres  #   首屏 ShaderWarmupConfig 预热清单 (对接 WarmupAssetsTask)
│   ├── prs_world_environment.tres   #   全局 2D/3D 渲染环境预设 (Glow / Tonemap)
│   └── prs_global_consts.tres       #   游戏全局平衡性常数 (如基础暴击倍率、同屏怪上限、金币换算系数)
│
├── tables/                          # [阶段 4 · 批量策划导表] Excel/Luban 导出的一表多行数据 (LoadConfigTask 装载)
│   ├── tbl_player_level_exp.json    #   等级经验曲线表 (按 level 索引)
│   ├── tbl_enemy_stats.json         #   怪物基础数值总表 (按 enemy_id 索引)
│   ├── tbl_shop_catalog.json        #   商店商品与价格表
│   └── tbl_drop_pools.json          #   掉落池与权重表
│
├── defs/                            # [阶段 5 · 游戏实体定义] Inspector 可视化组装的单体 Resource (一文件一实体)
│   ├── heroes/                      #   角色实体定义 (def_hero_intern.tres：绑定立绘、初始武器、被动)
│   ├── weapons/                     #   武器实体定义 (def_weapon_stapler.tres：绑定图标、投射物、伤害曲线)
│   ├── buffs/                       #   状态效果/遗物定义 (def_buff_overtime.tres)
│   └── talents/                     #   局外天赋树节点定义 (def_talent_coffee_mastery.tres)
│
└── stages/                          # [阶段 6 · 关卡与波次编排] 进入具体章节/单局时按需加载的复合编排数据
	├── stg_chapter_01_office.tres   #   第一章关卡元数据与场地 TileSet/地图规则引用
	└── stg_chapter_01_waves.json    #   第一章 15 分钟刷怪时间轴与 Boss 出场序列
```

---

## 三、 六大容器职责、文件格式与命名规范

| 容器目录 | 生命周期与内存策略 | 允许扩展名 | 强制前缀 | 粒度与职责边界 |
| :--- | :--- | :--- | :--- | :--- |
| **`envs/`** | **Stage 1：进程冷启动**<br>*(激活即常驻)* | `tres` `json` | `env_` | 按 `EnvType`（`local` / `dev` / `staging` / `prod`）区分的部署环境参数，供 [`App.env`](../framework/modules/env/_doc_env.md) 与 [`SyncSessionTask`](../game/features/splash/service/tasks/sync_session_task.gd) 读取。 |
| **`locales/`** | **Stage 2：首屏语言初始化**<br>*(引擎 TranslationServer 托管)* | `csv` `po` `translation` `tres` | `loc_` | 多语言源表（`.csv`）、引擎编译产物（`.translation`）及 [`LocaleConfig`](../framework/modules/locale/types/locale_config.gd) `.tres` 实例，对接 [`App.locale`](../framework/modules/locale/_doc_locale.md)。 |
| **`presets/`** | **Stage 3：系统初始化与闪屏预热**<br>*(全局单例常驻)* | `tres` | `prs_` | 全局唯一的系统级预设：`AudioBusLayout`、`WorldEnvironment`、[`ShaderWarmupConfig`](../game/shared/model/config/shader_warmup_config.gd)、通用采样曲线 `Curve` 及全局平衡常数资源。 |
| **`tables/`** | **Stage 4：闪屏配表装载**<br>*(内存只读字典常驻)* | `json` `csv` `bin` | `tbl_` | **一表多行（Row-based）**：由 Excel / Luban 导出的纯数值二维表，在 [`LoadConfigTask`](../game/features/splash/service/tasks/load_config_task.gd) 中一次性读入内存构建索引。 |
| **`defs/`** | **Stage 5：业务模块/战斗进场**<br>*(按领域分组，按需预载)* | `tres` | `def_` | **一文件一实体（Object-based）**：在 Godot Inspector 中可视化组装并拖拽绑定了贴图、预制体、曲线的自定义 `*Config` 资源实例（按 `heroes/`、`weapons/`、`buffs/` 等子域归类）。 |
| **`stages/`** | **Stage 6：单局关卡加载**<br>*(单局驻留，退局释放)* | `tres` `json` | `stg_` `tls_` | 章节关卡配置（`stg_`）、刷怪波次时间轴、随机事件脚本以及关卡专属 `TileSet`（`tls_`）。 |

---

## 四、 核心架构红线

1. **脚本类定义（`.gd`）与资源数据实例（`.tres` / `.json`）严格分离**：
   - **数据结构类定义（`class_name XxxConfig extends Resource`）** 属于代码契约，必须放在 `src/game/shared/model/config/` 或 `src/game/features/<feature>/model/` 下；
   - **`src/resources/` 下严禁存放 `.gd` 脚本或 `.tscn` 场景**，只存放序列化后的 `.tres`、`.json`、`.csv`、`.translation`、`.bin` 数据资产。
2. **「二维导表进 `tables/`，复合对象进 `defs/`，全局预设进 `presets/`」**：
   - 凡是成百上千行纯数值成长阶梯、掉落权重、商品价格，统一导出为 `.json` / `.csv` 放入 `tables/`；
   - 凡是需要利用 Godot Inspector 拖拽关联 `Texture2D`、`PackedScene`、`Curve`、子 `Resource` 数组的玩法对象，统一保存为 `.tres` 放入 `defs/<domain>/`；
   - 凡是全游戏全局只有一份的引擎配置或平衡常数，统一放入 `presets/`。
3. **只读契约铁律（Immutable at Runtime）**：
   - `src/resources/` 下的所有配置与资源在运行期一律视为**只读静态资产（Read-Only）**；
   - 业务代码在运行期严禁直接原地修改从 `defs/` 或 `presets/` 加载出来的 `Resource` 成员变量（若单局内需叠加强化 Buff，应在 `*State` 运行时状态类中计算，或调用 `.duplicate()` 克隆副本），防止污染 `App.asset` 全局内存缓存。
