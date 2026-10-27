@tool
class_name FlowGraphIcons
extends RefCounted

## FlowGraph 编辑器矢量图标预加载契约表（Preloaded SVG Texture Registry）。[br]
##
## 统一基于 [`FlowGraphContracts`](flow_graph_contracts.gd) 预加载单实例 `Texture2D`，供插件主栏、画布调色板、检视器与工作台共享引用。

const PLUGIN_MAIN: Texture2D = preload(FlowGraphContracts.ICON_PLUGIN_MAIN)

const STATUS_LIVE: Texture2D = preload(FlowGraphContracts.ICON_STATUS_LIVE)
const STATUS_OFFLINE: Texture2D = preload(FlowGraphContracts.ICON_STATUS_OFFLINE)
const STATUS_PAUSE: Texture2D = preload(FlowGraphContracts.ICON_STATUS_PAUSE)
const STATUS_PLAY: Texture2D = preload(FlowGraphContracts.ICON_STATUS_PLAY)
const STATUS_STEP: Texture2D = preload(FlowGraphContracts.ICON_STATUS_STEP)
const STATUS_BOLT: Texture2D = preload(FlowGraphContracts.ICON_STATUS_BOLT)

const TB_AUTO_LAYOUT: Texture2D = preload(FlowGraphContracts.ICON_TB_AUTO_LAYOUT)
const TB_CODE_DSL: Texture2D = preload(FlowGraphContracts.ICON_TB_CODE_DSL)
const TB_DIR_SWITCH: Texture2D = preload(FlowGraphContracts.ICON_TB_DIR_SWITCH)
const TB_FIT_VIEW: Texture2D = preload(FlowGraphContracts.ICON_TB_FIT_VIEW)
const TB_LABELS: Texture2D = preload(FlowGraphContracts.ICON_TB_LABELS)
const TB_MINIMAP: Texture2D = preload(FlowGraphContracts.ICON_TB_MINIMAP)
const TB_RESOURCE_LIST: Texture2D = preload(FlowGraphContracts.ICON_TB_RESOURCE_LIST)
const TB_SIDEBAR: Texture2D = preload(FlowGraphContracts.ICON_TB_SIDEBAR)
const TB_SNAP: Texture2D = preload(FlowGraphContracts.ICON_TB_SNAP)
const TB_TELEMETRY: Texture2D = preload(FlowGraphContracts.ICON_TB_TELEMETRY)
const TB_WINDOW_FLOAT: Texture2D = preload(FlowGraphContracts.ICON_TB_WINDOW_FLOAT)

const NODE_ENTRY: Texture2D = preload(FlowGraphContracts.ICON_NODE_ENTRY)
const NODE_ANY: Texture2D = preload(FlowGraphContracts.ICON_NODE_ANY)
const NODE_FINAL: Texture2D = preload(FlowGraphContracts.ICON_NODE_FINAL)
const NODE_SELECTOR: Texture2D = preload(FlowGraphContracts.ICON_NODE_SELECTOR)
const NODE_SEQUENCE: Texture2D = preload(FlowGraphContracts.ICON_NODE_SEQUENCE)
const NODE_PARALLEL: Texture2D = preload(FlowGraphContracts.ICON_NODE_PARALLEL)
const NODE_INVERTER: Texture2D = preload(FlowGraphContracts.ICON_NODE_INVERTER)
const NODE_COOLDOWN: Texture2D = preload(FlowGraphContracts.ICON_NODE_COOLDOWN)
const NODE_DECORATOR: Texture2D = preload(FlowGraphContracts.ICON_NODE_DECORATOR)
const NODE_CONDITION: Texture2D = preload(FlowGraphContracts.ICON_NODE_CONDITION)
const NODE_ACTION: Texture2D = preload(FlowGraphContracts.ICON_NODE_ACTION)
const NODE_WAIT: Texture2D = preload(FlowGraphContracts.ICON_NODE_WAIT)
