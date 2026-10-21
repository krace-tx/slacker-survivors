@abstract
class_name BaseAssetSystem
extends RefCounted

## 资产加载与缓存系统门面契约（Asset System Facade Contract）。[br]
##
## 本抽象基类作为业务层与底层资源加载器交互的唯一规范入口，核心职责：[br]
## - 异步非阻塞加载：封装引擎底层 [ResourceLoader] 并发加载逻辑；[br]
## - 请求合并（In-flight Merging）：对同一资源的重复并发加载请求自动合并，杜绝重复磁盘 I/O；[br]
## - 预算感知缓存：基于 LRU 与内存容量上限自动管理常驻内存资源；[br]
## - 纯 RefCounted 实现，轻量、无需挂载场景树。[br]
##
## 业务代码应统一通过 [code]App.asset[/code] 访问本契约提供的方法。


#region Public Asset APIs
## 异步加载指定路径的资源文件（PackedScene / Texture2D / AudioStream / Resource 等）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
## 加载成功后会自动缓存在内存中；若资源已在缓存中，将直接命中返回零延迟结果。[br]
##
## [param path] 资源文件的绝对路径（必须以 [code]res://[/code] 开头）。[br]
## @return 返回 [Result] 对象：[br]
##   - 成功时：[code]result.is_ok()[/code] 为 true，[code]result.value[/code] 为加载好的 [Resource] 实例；[br]
##   - 失败时：[code]result.is_err()[/code] 为 true，包含文件不存在或加载失败原因。
@abstract
func load(path: String) -> Result


## 从当前内存缓存池中释放指定路径的资源引用。[br]
##
## 仅解除框架内部的持有缓存；若外部场景仍在引用该资源实例，其生命周期遵循 Godot 引用计数正常释放。[br]
##
## [param path] 要释放的资源路径（[code]res://[/code] 开头）。
@abstract
func release(path: String) -> void


## 清空当前管理的所有内存资产缓存。[br]
##
## 通常在关卡切换、大版本重载或内存警告时由框架统一调用。
@abstract
func clear() -> void
#endregion
