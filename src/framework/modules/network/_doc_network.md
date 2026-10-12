# Framework · Network

> HTTP 网络通信门面。封装请求队列调度、指数退避重试、Token 鉴权注入与结果封装。

```text
src/framework/modules/network/
├── _doc_network.md             # 本文档
├── base_network_client.gd      # 公开门面契约 BaseNetworkClient (App.network / App.net，详尽注释)
│
├── types/                      # [公开契约]
│   └── network_request.gd      # 数据对象：单次请求配置与策略参数 (NetworkRequest)
│
└── impl/                       # [私有收敛]
    ├── network_client.gd       # 门面实现：请求、上传、下载
    └── request_queue.gd        # 队列调度：HTTPRequest 节点池、超时控制与指数退避重试
```

> 模块名保持完整的 `network`；`App.net` 只是访问别名，内部实现类为 `NetworkClient`。

---

## 核心设计特性

1. **请求配置抽象**：`NetworkRequest` 封装单次请求的 URL、方法、消息体、自定义 Header 与重试参数。
2. **队列与节点复用**：`RequestQueue` 维护 `HTTPRequest` 节点池，统一调度请求生命周期。
3. **鉴权透传**：支持设置全局 Bearer Token，后续外发请求自动注入 Header。
4. **指数退避重试**：针对 5xx 服务端错误或网络波动自动进行阶梯重试；4xx 立即失败。
5. **统一结果包装**：所有网络接口必须 `await` 并返回 `Result`，消除回调地狱。

---

## 使用范式

```gdscript
# 发送 GET 请求
var res := await App.net.get_request("https://api.game.com/config")
if res.is_ok():
    var data: Dictionary = res.value
else:
    App.log.error("Network", "Request failed: %s" % res.error_message())
```
