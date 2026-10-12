class_name StorageWriteMode
extends RefCounted

## 写入调度策略（定义数据落地的范围、顺序与一致性保证）。[br]
## 作为枚举命名空间使用，调用形如 [code]StorageWriteMode.LOCAL_FIRST[/code]。

enum {
	LOCAL_FIRST,     ## 【默认】本地优先：写内存 ➔ 写磁盘 ➔ 异步推送到远端云端
	LOCAL_ONLY,      ## 仅写本地：写内存 ➔ 写磁盘（单机离线持久化，不推送至云端）
	REMOTE_FIRST,    ## 远端优先：先阻塞推送云端，成功后再落盘并更新内存
	MEMORY_ONLY,     ## 仅写内存：只更新内存（适合战斗中每秒状态等高频临时数据）
}
