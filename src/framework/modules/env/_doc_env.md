# Framework · Env

> 运行环境诊断与判定服务。区分 LOCAL / EMULATOR / DEV / TEST / PROD 运行环境。

```text
src/framework/modules/env/
├── _doc_env.md             # 本文档
├── base_runtime_environment.gd # 公开门面契约 BaseRuntimeEnvironment (App.env，详尽注释)
└── impl/                   # 私有实现收敛
    ├── runtime_environment.gd  # 门面实现：只读环境查询
    └── env_detector.gd     # 平台与 Feature Tag 特征探测器
```

---

## 使用范式

```gdscript
if App.env.is_dev():
    App.log.debug("DebugTool", "Dev mode enabled.")

var env_name := App.env.get_name() # "LOCAL" / "DEV" / "PROD"
```
