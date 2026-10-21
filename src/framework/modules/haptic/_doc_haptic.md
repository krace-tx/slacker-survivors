# Framework · Haptic

> 跨平台触觉反馈调度服务。采用**「统一语义输入，三端硬件差异化翻译」**架构，集中管理玩家振动总开关、高低优先级防打断、高频节流防抖，以及手机/手柄/电脑键鼠三端的差异化物理与视觉触觉体验。

```text
src/framework/modules/haptic/
├── _doc_haptic.md           # 本文档
├── base_haptic_feedback.gd  # 公开门面契约 BaseHapticFeedback (App.haptic，详尽注释)
├── types/                   # [公开契约]
│   └── haptic_intensity.gd  # 触觉强度与抢占优先级枚举 HapticIntensity (LIGHT / MEDIUM / HEAVY)
└── impl/                    # [私有实现收敛]
    └── haptic_feedback.gd   # 门面实现：三端硬件参数翻译、优先级抢占、高频节流与后台急停
```

---

## 一、 三端硬件差异化体验映射

业务层无需判断当前运行在什么终端，只需调用语义化接口（`light` / `medium` / `heavy`），`HapticFeedback` 自动按当前设备物理特性翻译为最佳硬件参数：

| 门面方法 | 优先级 (`HapticIntensity`) | 典型游戏场景 | 📱 手机端（单通道脉冲 + 振幅） | 🎮 手柄端（Weak 高频小转子 / Strong 低频大配重） | 💻 电脑键鼠端 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `App.haptic.light()` | `LIGHT (1)` | 按钮点击、拾取经验宝石、高频微反馈 | `12ms`, 振幅 `0.35`（清脆点触） | `40ms` 起振补偿，`Weak: 0.35`, `Strong: 0.00`（纯高频，不启动笨重大转子） | 物理静默（防闲置手柄空震）+ 发射 `LIGHT` 脉冲信号 |
| `App.haptic.medium()` | `MEDIUM (2)` | 精英怪击杀、技能进化、普通受击 | `28ms`, 振幅 `0.70`（短促肉感） | `75ms`，`Weak: 0.70`, `Strong: 0.45`（高频主导 + 中度低频） | 物理静默 + 发射 `MEDIUM` 脉冲信号 |
| `App.haptic.heavy()` | `HEAVY (3)` | 玩家受重创、Boss 登场/砸地、宝箱暴击 | `[40ms, 35ms, 60ms]`，振幅 `1.0 -> 0.85`（快慢双脉冲，不麻手） | `[110ms, 40ms, 130ms]`，`Weak: 0.85->0.50`, `Strong: 1.0->0.80`（低频满载双波轰鸣） | 物理静默 + 发射 `HEAVY` 脉冲信号 |
| `App.haptic.stop()` | — | 退出关卡、跳过演出、切后台、关闭开关 | 立即终止后续脉冲序列 | 立即终止序列 + `stop_joy_vibration` 马达急停 | 立即终止序列 |

---

## 二、 核心工程保护机制

1. **高优防打断保护（Priority Preemption）**：
   当高优先级震动（如 `HEAVY` 受重创双脉冲）正在执行时，期间到来的低优先级请求（如 `LIGHT` 拾取经验球）会被自动忽略，绝不掐断重击反馈；仅同级或更高优先级请求可重置序列。
2. **高频怪潮节流窗（Throttle Guard）**：
   内置 `25ms` 最小节流时间窗。幸存者玩法同帧拾取数十颗宝石或高频连击时，同级请求自动合并防抖，杜绝马达嗡鸣过载与计时器泛滥。
3. **跨模态视觉触觉桥接（`haptic_pulsed` 信号）**：
   每次有效脉冲均广播 `haptic_pulsed(intensity, amplitude, duration_ms)`，战斗相机可在 PC 键鼠端（或全平台）订阅该信号，将 `MEDIUM / HEAVY` 级触觉自动转化为微小的镜头震屏冲量。
4. **后台与失焦自动急停**：
   自动监听 `Bus.app_paused`，应用切后台或桌面窗口失焦时立即终止所有震动序列并停止手柄马达。

---

## 三、 使用范式

```gdscript
# 1. 语义化三档触觉反馈（推荐优先使用，内部自动适配手机/手柄/PC）
App.haptic.light()   # UI 点击 / 拾取宝石
App.haptic.medium()  # 精英击杀 / 普通受击
App.haptic.heavy()   # 玩家受重创 / Boss 技能 / 宝箱暴击

# 2. 自定义时长与振幅（支持指定抢占优先级）
App.haptic.vibrate(30, 0.8, HapticIntensity.MEDIUM)

# 3. 自定义节奏序列（偶数下标为震动毫秒，奇数下标为停顿毫秒）
App.haptic.pattern([50, 40, 80], 0.9, HapticIntensity.HEAVY)

# 4. 手柄高低频双马达精细控制（Weak 右握把高频 + Strong 左握把低频）
App.haptic.rumble_joypad(0.4, 0.9, 120, HapticIntensity.HEAVY)

# 5. 立即急停
App.haptic.stop()
```
