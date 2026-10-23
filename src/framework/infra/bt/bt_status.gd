class_name BTStatus
extends RefCounted

## 行为树节点执行状态三态枚举契约（Behavior Tree Execution Status Contract）。

#region Status Enum
enum Status {
	SUCCESS = 0, ## 节点执行成功
	FAILURE = 1, ## 节点条件不满足或执行失败
	RUNNING = 2, ## 节点正在跨帧持续执行中
}
#endregion


#region Helpers
static func to_string_name(status: int) -> StringName:
	match status:
		Status.SUCCESS: return &"SUCCESS"
		Status.FAILURE: return &"FAILURE"
		Status.RUNNING: return &"RUNNING"
		_: return &"FAILURE"


static func invert(status: int) -> int:
	if status == Status.SUCCESS:
		return Status.FAILURE
	if status == Status.FAILURE:
		return Status.SUCCESS
	return Status.RUNNING
#endregion
