class_name InputError
extends RefCounted

## 输入模块标准化错误码常量定义（Input Error Codes）。[br]
##
## 严格遵循 Framework [code]{Module}.{Reason}[/code] 错误码规范，配合 [Result] 使用。

## 指定的 Action 名称未在 InputMap 或输入系统中注册
const ACTION_NOT_FOUND: String = "Input.ActionNotFound"

## 指定的 Action 被标记为系统锁定（不可改键）
const ACTION_LOCKED: String = "Input.ActionLocked"

## 传入的 InputEvent 或 InputChord 非法、为空或与目标设备轨道不匹配
const INVALID_EVENT: String = "Input.InvalidEvent"

## 改键时与同一上下文作用域内的其它 Action 发生按键冲突（在 REJECT 策略下触发）
const BINDING_CONFLICT: String = "Input.BindingConflict"

## 当前已处于交互式按键录制状态中，拒绝并发重入
const REBIND_BUSY: String = "Input.RebindBusy"

## 玩家按下取消键（如 ESC）或主动调用 cancel_rebind() 中止了按键录制
const REBIND_CANCELED: String = "Input.RebindCanceled"

## 交互式按键录制等待超时
const REBIND_TIMEOUT: String = "Input.RebindTimeout"

## 反序列化用户键位配置字典失败（格式损坏或版本不兼容）
const DESERIALIZE_FAILED: String = "Input.DeserializeFailed"
