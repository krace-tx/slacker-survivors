class_name GraphicsSettingsData
extends BaseParams

## 画质与视口渲染设置子数据块（位于 src/game/shared/model/data/）。[br]
##
## [b]核心职责：[/b][br]
## 1. 承载全局画质预设档位、3D 渲染缩放倍率、2D/3D MSAA、屏幕空间抗锯齿（FXAA/SMAA）、2D 纹理过滤、特效密度与阴影质量；[br]
## 2. 内聚定义画质预设枚举 [enum QualityPreset] 与阴影质量枚举 [enum ShadowQuality]；[br]
## 3. 作为 [GameSettingsModel] 的内嵌子结构（`*Data`），提供一键展开预设档位 `apply_preset()` 与独立 `sanitize()` / `reset()`。


#region 枚举定义

## 全局画质预设档位枚举
enum QualityPreset {
	LOW = 0,     ## 省电/低配流畅（0.75x 渲染倍率，关闭抗锯齿与阴影，50% 特效密度）
	MEDIUM = 1,  ## 均衡标准（1.0x 渲染倍率，开启 FXAA，低阴影，75% 特效密度）
	HIGH = 2,    ## 高清画质（1.0x 渲染倍率，2X MSAA + FXAA，中阴影，100% 特效密度）
	ULTRA = 3,   ## 极致画质（1.0x 渲染倍率，4X MSAA + SMAA，高阴影，100% 特效密度）
	CUSTOM = 4,  ## 自定义微调（单独修改任一渲染管线参数后自动切入此档位）
}


## 阴影质量档位枚举
enum ShadowQuality {
	DISABLED = 0, ## 关闭阴影
	LOW = 1,      ## 低质量阴影
	MEDIUM = 2,   ## 中等质量阴影
	HIGH = 3,     ## 高质量阴影
}

#endregion


#region 成员属性

## 全局画质预设档位（对应 [enum QualityPreset]：0=LOW, 1=MEDIUM, 2=HIGH, 3=ULTRA, 4=CUSTOM）
var quality_preset: int = QualityPreset.HIGH

## 3D 渲染分辨率缩放倍率 `[0.50, 2.00]`（默认 1.0）
var render_scale: float = 1.0

## 2D 多重采样抗锯齿等级（对应 [enum Viewport.MSAA]：0=Disabled, 1=2X, 2=4X, 3=8X）
var msaa_2d: int = Viewport.MSAA_2X

## 3D 多重采样抗锯齿等级（对应 [enum Viewport.MSAA]：0=Disabled, 1=2X, 2=4X, 3=8X）
var msaa_3d: int = Viewport.MSAA_2X

## 屏幕空间后处理抗锯齿（对应 [enum Viewport.ScreenSpaceAA]：0=Disabled, 1=FXAA, 2=SMAA）
var screen_space_aa: int = Viewport.SCREEN_SPACE_AA_FXAA

## 2D 画布默认纹理过滤模式（对应 [enum Viewport.DefaultCanvasItemTextureFilter]：1=Linear, 0=Nearest）
var canvas_texture_filter: int = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR

## 特效与粒子密度比例 `[0.25, 1.00]`（低配减少同屏非核心粒子防掉帧）
var effect_quality: float = 1.0

## 阴影质量档位（对应 [enum ShadowQuality]：0=关闭, 1=低, 2=中, 3=高）
var shadow_quality: int = ShadowQuality.HIGH

#endregion


#region 公开方法

## 对画质与渲染参数执行合法范围钳制自愈，返回自身支持链式调用。
func sanitize() -> GraphicsSettingsData:
	quality_preset = clampi(
		quality_preset,
		QualityPreset.LOW,
		QualityPreset.CUSTOM
	)
	render_scale = clampf(render_scale, 0.50, 2.00)
	msaa_2d = clampi(msaa_2d, Viewport.MSAA_DISABLED, Viewport.MSAA_8X)
	msaa_3d = clampi(msaa_3d, Viewport.MSAA_DISABLED, Viewport.MSAA_8X)
	screen_space_aa = clampi(
		screen_space_aa,
		Viewport.SCREEN_SPACE_AA_DISABLED,
		Viewport.SCREEN_SPACE_AA_MAX - 1
	)
	canvas_texture_filter = clampi(
		canvas_texture_filter,
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST,
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_MAX - 1
	)
	effect_quality = clampf(effect_quality, 0.25, 1.00)
	shadow_quality = clampi(
		shadow_quality,
		ShadowQuality.DISABLED,
		ShadowQuality.HIGH
	)
	return self


## 根据给定的画质预设档位一键展开底层视口渲染参数。
func apply_preset(preset: int) -> void:
	match preset:
		QualityPreset.LOW:
			quality_preset = QualityPreset.LOW
			render_scale = 0.75
			msaa_2d = Viewport.MSAA_DISABLED
			msaa_3d = Viewport.MSAA_DISABLED
			screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			effect_quality = 0.50
			shadow_quality = ShadowQuality.DISABLED
		QualityPreset.MEDIUM:
			quality_preset = QualityPreset.MEDIUM
			render_scale = 1.0
			msaa_2d = Viewport.MSAA_DISABLED
			msaa_3d = Viewport.MSAA_DISABLED
			screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			effect_quality = 0.75
			shadow_quality = ShadowQuality.LOW
		QualityPreset.HIGH:
			quality_preset = QualityPreset.HIGH
			render_scale = 1.0
			msaa_2d = Viewport.MSAA_2X
			msaa_3d = Viewport.MSAA_2X
			screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			effect_quality = 1.0
			shadow_quality = ShadowQuality.MEDIUM
		QualityPreset.ULTRA:
			quality_preset = QualityPreset.ULTRA
			render_scale = 1.0
			msaa_2d = Viewport.MSAA_4X
			msaa_3d = Viewport.MSAA_4X
			screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
			effect_quality = 1.0
			shadow_quality = ShadowQuality.HIGH
		_:
			quality_preset = QualityPreset.CUSTOM


## 重置当前画质数据块为出厂默认值。
func reset() -> void:
	var defaults := GraphicsSettingsData.new()
	from_dict(defaults.to_dict())

#endregion
