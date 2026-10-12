extends Node
## 全局领域事件总线 (Autoload / EventBus)
## 只广播已发生的事实，不承载命令；做事走 App.xxx。
## 本文件只声明信号；发出与订阅在各自模块。

@warning_ignore_start("unused_signal") ## 信号按设计在外部 emit/connect

#region App
## 已切后台。由 App 发出。
signal app_paused

## 已回前台。由 App 发出。
signal app_resumed

## 硬件返回键 / 侧滑返回 / ESC 按下。由 App 发出。
signal app_back_pressed
#endregion

#region Service
## 语言已切换。由 LocaleService 发出。
signal locale_changed
#endregion

#region Scene
## 顶层场景切换完成。由 SceneService 发出。[param path] 为 tscn 路径。
signal scene_changed(path: String)

## 顶层场景切换失败。由 SceneService 发出。[param path] 为当时请求的路径。
signal scene_change_failed(path: String)
#endregion
