class_name StorageReadMode
extends RefCounted

## 读取调度策略（定义数据拉取的优先级与降级路径）。[br]
## 作为枚举命名空间使用，调用形如 [code]StorageReadMode.CACHE_FIRST[/code]。

enum {
	CACHE_FIRST,     ## 【默认】缓存优先：内存 ➔ 磁盘 ➔ 远端网络（层层穿透并自动回灌各级缓存）
	REMOTE_FIRST,    ## 远端优先：优先拉取云端最新数据；弱网/断网失败时，自动降级回退到本地缓存
	LOCAL_ONLY,      ## 仅本地介质：内存 ➔ 磁盘（完全离线模式，绝对不发起网络请求）
	REMOTE_ONLY,     ## 仅远端网络：强制直接请求云端，绕过本地旧数据（成功后仍会自动刷新本地缓存）
	MEMORY_ONLY,     ## 仅极速内存：只查询内存池，不触发任何磁盘 I/O 和网络请求
}
