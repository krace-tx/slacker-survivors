class_name FileCodecType
extends RefCounted

## 可供 [FileCodecUtils] 编解码的引擎内置类型。[br]
## 作为枚举命名空间使用，调用形如 [code]FileCodecType.IMAGE[/code]。[br]
## 枚举表示 decode 要拿回的对象，不表示磁盘扩展名；[Image] 与 [Texture2D] 落盘可以是同一份 png / jpg / webp。

enum {
	IMAGE, ## CPU 像素缓冲 [Image]，用于改像素、合图后再编码。
	TEXTURE_2D, ## 渲染用 [Texture2D]（含 [ImageTexture] 等子类），用于上屏显示。
}
