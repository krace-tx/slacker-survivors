# Infra · Spine (骨骼动画流式控制、享元对象池与分频错峰调度基建)

## 核心

全框架统一的 Spine 骨骼动画高性能运行时基建（彻底取代旧版过程式 `SpineUtils`）。
通过 **[`SpineController`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/spine/spine_controller.gd)（强类型适配器 + 流式控制器 + 租约句柄）** 与 **[`SpinePool`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/spine/spine_pool.gd)（享元对象池 + 视口内全管线真预热 + 奇偶帧错峰步进调度器）** 协同配合，既提供优雅的面向对象链式控制 API，又从物理根源彻底解决 Godot 4 + `spine-godot` 在复杂骨骼动画下的**「瞬时掉帧卡顿（Frame Spike / Hitch）」**通病。

```text
src/framework/infra/spine/
├── _doc_spine.md         # 本文档
├── spine_controller.gd   # 核心类 SpineController (适配器 + 流式链式控制 + 租约归还句柄)
└── spine_pool.gd         # 核心类 SpinePool (享元对象池 + 视口内真预热 + 奇偶帧错峰步进)
```

---

## 一、 四大核心设计模式与防卡顿机制

| 设计模式 | 核心载体 | 解决的工程与性能问题 |
| :--- | :--- | :--- |
| **1. 适配器与流式接口模式**<br>(Adapter & Fluent Interface) | [`SpineController`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/spine/spine_controller.gd) | 隔离 `spine-godot` C++ 扩展反射细节（无插件时安全降级），支持 `ctrl.set_skin("v2").set_time_scale(1.2).play("attack").queue("idle", true)` 链式编排、骨骼挂点世界坐标查询与带超时兜底的 `await_completed`。 |
| **2. 享元对象池与租约句柄模式**<br>(Flyweight Pool & Lease Handle) | [`SpinePool`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/spine/spine_pool.gd) + [`SpineController.release()`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/spine/spine_controller.gd#L371) | 消除战斗期新建 `SpineSprite` 时在主线程深拷贝 C++ `spine::Skeleton` 树与分配 `MeshAttachment` 蒙皮缓冲的瞬时卡顿；借出返回 `SpineController` 租约句柄，调用 `ctrl.release()` 或 `play_oneshot` 播完自动归还休眠池，实现 **0ms C++ 构造开销**。 |
| **3. 视口内全管线真预热模式**<br>(In-Frustum Pipeline Warmup) | [`SpinePool.warmup()`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/spine/spine_pool.gd#L105) | 摒弃会被视口裁剪器（Frustum Culler）剔除的 `(-9999, -9999)` 假预热，在视口安全角（`Vector2(2, 2)`，配合 `0.001` 微缩放与 `0.005` 微透明度）遍历该骨骼**全部动画**执行首帧步进采样并渲染 1 帧，强制 GPU 提前编译 `Normal / Additive / Multiply` 混合管线，预热完直接入池待命。 |
| **4. 奇偶帧错峰与降频步进模式**<br>(Staggered Frame Decimation) | [`SpinePool.register_staggered()`](file:///Users/krace/Code/GodotProject/slacker-survivors/src/framework/infra/spine/spine_pool.gd#L285) | 将同屏复杂 Spine 切换为 `UpdateMode_Manual`，按目标帧率（如美术标准 `30 FPS`）与奇偶帧相位桶（Bucket）自动错峰调用 `update_skeleton`，**砍掉 50%~75% CPU 蒙皮变形与剪裁遮罩算力，彻底削平单帧尖峰**。 |

---

## 二、 使用范式

```gdscript
# 1. 在关卡场景 (BaseScene) 中创建绑定当前场景生命周期的 SpinePool（场景退出时自动 dispose 零泄漏）
var _spine_pool: SpinePool

func _on_enter(_params: Dictionary = {}) -> void:
	_spine_pool = SpinePool.new(self)

	# 2. 结合 App.asset 异步加载骨骼资源，并执行视口内真预热（预热完直接入池待命）
	var boss_skel := (await App.asset.load("res://src/assets/spines/enemy/spn_enemy_boss_auditor_data.tres")).value as Resource
	var hit_vfx_skel := (await App.asset.load("res://src/assets/spines/battle/spn_battle_hit_burst_data.tres")).value as Resource

	await _spine_pool.warmup_batch({
		boss_skel: 1,
		hit_vfx_skel: 8,
	})

	# 3. 零分配借出 Boss 控制器句柄，链式换肤播放，并开启 30FPS 奇偶帧错峰步进防卡顿
	var boss_ctrl := _spine_pool.acquire(boss_skel, $World/BossRoot, Vector2(600, 400)).value as SpineController
	_spine_pool.register_staggered(boss_ctrl, 30.0)
	boss_ctrl.set_skin("phase_1") \
		.play("appear", false) \
		.queue("idle", true)

# 4. 战斗中高频触发复杂一次性受击/爆炸特效（0ms 借出，播完自动归还休眠池，绝不销毁重建）
func _on_enemy_hit(hit_pos: Vector2, hit_vfx_skel: Resource) -> void:
	_spine_pool.play_oneshot(hit_vfx_skel, $World/VfxContainer, hit_pos, "hit_burst")

# 5. 对 .tscn 场景中预先摆放的静态 SpineSprite 节点直接包装控制
func _on_chest_open() -> void:
	var chest_ctrl := SpineController.wrap($UI/ChestSpine).value as SpineController
	chest_ctrl.play("open", false)
	await chest_ctrl.await_completed("open", 0, task_scope.get_token())
```
