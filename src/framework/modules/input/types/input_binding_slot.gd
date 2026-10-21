class_name InputBindingSlot
extends RefCounted

## 键位绑定槽位枚举（Input Binding Slot）。[br]
##
## 每个逻辑动作在单种设备轨道（键鼠轨 / 手柄轨）下均支持主、副两个独立绑定槽位：[br]
## 例如键盘移动可同时在 [constant Slot.PRIMARY] 绑定 [code]WASD[/code]，在 [constant Slot.SECONDARY] 绑定 [code]方向键[/code]。

enum Slot {
	PRIMARY = 0,   ## 主键位槽
	SECONDARY = 1, ## 备选副键位槽
}


## 生成用于持久化字典或内部索引的复合槽位键名（如 "kb_0", "kb_1", "joy_0", "joy_1"）
static func make_slot_key(device_type: int, slot: int) -> String:
	var prefix := "joy" if device_type == InputDeviceType.Type.JOYPAD else "kb"
	return "%s_%d" % [prefix, slot]
