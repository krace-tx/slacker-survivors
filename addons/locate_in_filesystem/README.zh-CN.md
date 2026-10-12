# Locate in FileSystem

[English](README.md)

Godot 4 编辑器插件：正在编的场景 / 脚本，一键落到 FileSystem 里的真实位置；选中目录，整枝展开或收起。

**需要 Godot 4.0+。** 无额外依赖。

## 功能

大型项目中，FileSystem 面板的深层目录（10+ 级）让文件很难定位，靠滚动效率极低。现有搜索能快速对上文件名，却无法同时展示它在项目树里的具体路径，上下文缺失严重。

本插件把正在编辑的场景 / 脚本一键落到 FileSystem 的真实位置，再配合整枝展开 / 收起，路径和结构一次看清。

### 定位

打开当前场景或脚本，点顶栏 Filesystem 按钮，或按 **Ctrl+Shift+L**（macOS：**Cmd+Shift+L**）。左侧会选中那个文件。

- **2D / 3D**：优先当前场景，没有再落到当前脚本。
- **脚本屏**：优先当前脚本，没有再落到当前场景。
- 内置脚本（`scene.tscn::xxx`）定位到所属的 `.tscn`。

2D 顶栏：

![2D 顶栏定位按钮](imgs/screenshot-2D.png)

3D 顶栏：

![3D 顶栏定位按钮](imgs/screenshot-3D.png)

脚本顶栏（没有官方工具栏槽，按钮挂在脚本编辑器菜单栏）：

![脚本编辑器定位按钮](imgs/screenshot-script.png)

也可从项目菜单 → **Locate in FileSystem**。

### 展开 / 收起

FileSystem 里 **Sort Files** 旁边的按钮。以选中的文件夹为根（选中文件则用父目录）：

1. 文件夹是收起的 → 展开自身和已生成的子孙
2. 下面还有展开的子目录 → 只收子孙
3. 只有一层摊开 → 收起这个文件夹

未点开过的深层目录还没有 `TreeItem`，只会改已经实例化的节点。

![Sort 旁整枝展开 / 收起](imgs/screenshot-folder.png)

## 结构

`plugin.gd` 是门面：持有服务、挂工具栏、转发编辑器生命周期。具体逻辑在 `core/` 和 `ui/`。

```
plugin.gd                 门面
core/
  file_service.gd         定位当前场景 / 脚本
  folder_service.gd       选中目录整枝展开 / 收起
  editor_utils.gd         查找编辑器未公开的控件（图标 / metadata，不靠翻译文案）
ui/
  file_toolbar.gd         2D / 3D / 脚本顶栏定位按钮
  folder_toolbar.gd       Sort Files 旁的折叠按钮
```

## 安装

1. 把 `addons/locate_in_filesystem` 拷进项目。
2. 项目 → 项目设置 → 插件 → 启用 **Locate in FileSystem**。

## 示例

独立示例工程的 `example/` 里有多层场景和脚本，可用来试定位和整枝收起。
