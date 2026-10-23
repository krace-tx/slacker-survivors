class_name AuthProviderType
extends RefCounted

## 多平台登录渠道标识常量定义（Authentication Provider Identifiers）。[br]
##
## 采用 [StringName] 常量以便零分配比对，同时支持业务扩展自定义第三方渠道（如 WeGame / Epic）。

## 自动按当前运行宿主与平台择优选择（Desktop 优先 Steam -> iOS 优先 Apple -> Android 优先 Google -> 兜底 Guest）
const AUTO: StringName = &"auto"

## Valve Steam 平台（通过 GodotSteam 单例反射桥接）
const STEAM: StringName = &"steam"

## Apple 生态登录（iOS / macOS Sign in with Apple & GameCenter）
const APPLE: StringName = &"apple"

## Google Play Games Services 登录（Android GPGS v2）
const GOOGLE: StringName = &"google"

## TapTap / 第三方通行证与自建账号令牌登录
const CUSTOM: StringName = &"custom"

## 本机硬件设备指纹派生游客登录（100% 离线可用保底）
const GUEST: StringName = &"guest"
