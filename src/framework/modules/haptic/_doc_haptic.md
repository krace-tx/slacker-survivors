# Framework · Haptic

> 触觉振动统一调度服务。集中管理设备振动总开关裁决与节奏模式。

```text
src/framework/modules/haptic/
├── _doc_haptic.md          # 本文档
├── base_haptic_feedback.gd # 公开门面契约 BaseHapticFeedback (App.haptic，详尽注释)
└── impl/                   # 私有实现收敛
    └── haptic_feedback.gd  # 门面实现：触觉振动总控与节奏模式
```

---

## 使用范式

```gdscript
# 1. 默认轻量级振动反馈 (15ms)
App.haptic.vibrate()

# 2. 自定义振动时长
App.haptic.vibrate(30)

# 3. 预设节奏模式 (连续/重击)
App.haptic.pattern(HapticFeedback.HEAVY)
```
