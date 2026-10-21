class_name InputDeviceType
extends RefCounted

## 输入设备大类与手柄硬件品牌类型定义（Input Device & Joypad Brand Types）。[br]
##
## 用于区分当前活跃的物理输入设备（键鼠 vs 手柄），并识别具体手柄型号以驱动差异化按键图标（Xbox / PlayStation / Switch / SteamDeck）。

## 物理输入设备大类枚举
enum Type {
	KEYBOARD_MOUSE = 0, ## 电脑键盘与鼠标
	JOYPAD = 1,         ## 游戏手柄控制器
}

## 手柄硬件品牌细分枚举（用于动态映射按键提示图标：如 A/B/X/Y vs ×/○/□/△）
enum JoyBrand {
	GENERIC = 0,     ## 通用标准手柄（默认回退为 Xbox 布局）
	XBOX = 1,        ## 微软 Xbox 系列手柄 (A / B / X / Y / LB / RB / LT / RT)
	PLAYSTATION = 2, ## 索尼 DualShock / DualSense 系列手柄 (× / ○ / □ / △ / L1 / R1 / L2 / R2)
	NINTENDO = 3,    ## 任天堂 Switch Pro / Joy-Con 系列手柄 (B / A / Y / X / L / R / ZL / ZR)
	STEAM_DECK = 4,  ## Valve Steam Deck 掌机控制器
}


## 将设备大类枚举转换为可读名称
static func type_to_string(device_type: int) -> String:
	match device_type:
		Type.KEYBOARD_MOUSE:
			return "KEYBOARD_MOUSE"
		Type.JOYPAD:
			return "JOYPAD"
		_:
			return "UNKNOWN"


## 将手柄品牌枚举转换为可读名称
static func brand_to_string(brand: int) -> String:
	match brand:
		JoyBrand.XBOX:
			return "XBOX"
		JoyBrand.PLAYSTATION:
			return "PLAYSTATION"
		JoyBrand.NINTENDO:
			return "NINTENDO"
		JoyBrand.STEAM_DECK:
			return "STEAM_DECK"
		_:
			return "GENERIC"


## 根据 Godot [method Input.get_joy_name] 与 [method Input.get_joy_guid] 自动嗅探手柄品牌
static func detect_joy_brand(joy_name: String, joy_guid: String = "") -> JoyBrand:
	var combined := (joy_name + " " + joy_guid).to_lower()
	if "steam" in combined or "deck" in combined or "neptune" in combined:
		return JoyBrand.STEAM_DECK
	if "ps5" in combined or "ps4" in combined or "playstation" in combined or "dualsense" in combined or "dualshock" in combined or "sony" in combined or "054c" in combined:
		return JoyBrand.PLAYSTATION
	if "nintendo" in combined or "switch" in combined or "joy-con" in combined or "pro controller" in combined or "057e" in combined:
		return JoyBrand.NINTENDO
	if "xbox" in combined or "xinput" in combined or "microsoft" in combined or "045e" in combined:
		return JoyBrand.XBOX
	return JoyBrand.XBOX
