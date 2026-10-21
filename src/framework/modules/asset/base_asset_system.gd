@abstract
class_name BaseAssetSystem
extends RefCounted

## 资产加载与缓存系统门面契约（Asset System Facade Contract）。[br]
##
## 本抽象基类作为业务层与底层资源加载器交互的唯一规范入口，核心职责：[br]
## - 同步缓存快路径（[method get_cached]）：已缓存资源零协程分配、零帧延迟同步读取；[br]
## - 异步非阻塞加载（[method load]）：封装引擎底层 [ResourceLoader] 并发加载逻辑；[br]
## - 信号驱动请求合并（Signal-Driven In-flight Merging）：同一资源并发请求自动合并，零轮询唤醒；[br]
## - 真并发批量预加载（[method preload_batch]）：双阶段打满底层多线程 I/O 队列；[br]
## - 预算感知缓存：基于 LRU、TTL 与内存水位上限自动管理常驻内存资源，支持核心资产钉住（Pin）。[br]
##
## 业务代码应统一通过 [code]App.asset[/code] 访问本契约提供的方法。


#region Public Asset APIs
## 同步获取已缓存在内存中的资源实例（零协程分配、零磁盘 I/O）。[br]
##
## 若资源已在框架缓存或引擎底层 C++ 缓存中命中，立即返回该 [Resource] 并自动续期 TTL；[br]
## 若未命中则返回 [code]null[/code]（不触发阻塞式磁盘读取）。高频场景（如音效播放、特效生成）应优先调用此快路径。[br]
##
## [param path] 资源路径（[code]res://[/code] 开头）。
@abstract
func get_cached(path: String) -> Resource


## 异步加载指定路径的资源文件（PackedScene / Texture2D / AudioStream / Resource 等）。[br]
##
## [b]注意：[/b]本方法为异步方法，调用端必须使用 [code]await[/code] 等待结果。[br]
## 加载成功后会自动缓存在内存中；若资源已在缓存中，将直接命中返回。[br]
##
## [param path] 资源文件的绝对路径（必须以 [code]res://[/code] 开头）。[br]
## @return 返回 [Result] 对象：[br]
##   - 成功时：[code]result.is_ok()[/code] 为 true，[code]result.value[/code] 为加载好的 [Resource] 实例；[br]
##   - 失败时：[code]result.is_err()[/code] 为 true，携带 [code]Asset.*[/code] 标准错误码。
@abstract
func load(path: String) -> Result


## 真并发批量预加载一组资源路径至内存缓存中。[br]
##
## 第一阶段同步向引擎底层多线程队列派发全部未缓存路径的加载请求，第二阶段统一等待汇总结果。[br]
##
## [param paths] 待预加载的 [code]res://[/code] 资源路径列表。[br]
## @return 返回 [Result] 对象：成功时 [code]result.value[/code] 为成功加载的 [Dictionary]（[code]path -> Resource[/code]）；若任一资源加载失败则返回首个错误。
@abstract
func preload_batch(paths: Array[String]) -> Result


## 查询指定路径的资源当前是否已在内存缓存池中命中（未过期，不续期访问时间）。[br]
##
## [param path] 资源路径（[code]res://[/code] 开头）。
@abstract
func has_cached(path: String) -> bool


## 钉住指定路径的缓存资源，使其在解除钉住（[method unpin]）或显式释放（[method release]）前不被 TTL 过期或 LRU 水位淘汰。[br]
##
## [param path] 资源路径（[code]res://[/code] 开头）。
@abstract
func pin(path: String) -> void


## 解除指定路径缓存资源的钉住状态，恢复正常的 TTL 与 LRU 水位淘汰机制。[br]
##
## [param path] 资源路径（[code]res://[/code] 开头）。
@abstract
func unpin(path: String) -> void


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
