@tool
class_name FlowGraphContracts
extends RefCounted

## FlowGraph 编辑器全局路径与配置键契约表（Centralized Resource Path & Setting Contracts）。[br]
##
## [b]架构职责：[/b][br]
## 统一收敛 `addons/flow_graph/` 下全部场景、脚本与矢量图标的 `res://` 静态路径常量及编辑器配置键；[br]
## 所有模块执行 `preload(...)` 时统一引用本契约常量（如 `preload(FlowGraphContracts.SCRIPT_GRAPH_MODEL)`），严禁散落硬编码相对路径字符串。


#region 编辑器配置键与协议常量

const SETTING_EDITOR_LANGUAGE: String = "flow_graph/editor/language"
const SETTING_INPUT_OVERRIDES: String = "flow_graph/editor/input_overrides"
const SETTING_GODOT_LOCALE: String = "interface/editor/editor_language"
const SETTING_GAME_EMBED_MODE: String = "run/window_placement/game_embed_mode"

const METHOD_TO_FG_IR: StringName = &"to_flow_graph_ir"
const METHOD_APPLY_FG_IR: StringName = &"apply_flow_graph_ir"
const METHOD_TO_MG_IR: StringName = &"to_mermaid_ir"
const METHOD_APPLY_MG_IR: StringName = &"apply_mermaid_ir"

const SCHEMA_FSM: StringName = &"fsm"
const SCHEMA_BT: StringName = &"bt"
const SCHEMA_OTHER: StringName = &"other"

## 跨进程调试器 IPC 消息与下行控制命令契约
const IPC_CAPTURE_PREFIX: String = "flow_graph"
const IPC_MSG_REGISTER: String = "flow_graph:register"
const IPC_MSG_UNREGISTER: String = "flow_graph:unregister"
const IPC_MSG_TOPOLOGY: String = "flow_graph:topology"
const IPC_MSG_FRAME: String = "flow_graph:frame"
const IPC_MSG_EDGE_FLOW: String = "flow_graph:edge_flow"

const IPC_SEND_SYNC_ALL: String = "flow_graph:sync_all"
const IPC_SEND_WINDOW_TOPMOST: String = "flow_graph:window_topmost"
const IPC_SEND_CMD: String = "flow_graph:cmd"
const IPC_SEND_HOT_RELOAD: String = "flow_graph:hot_reload_resource"

const DBG_CMD_SET_PAUSE: StringName = &"set_pause"
const DBG_CMD_STEP_ONCE: StringName = &"step_once"
const DBG_CMD_SET_BREAKPOINT: StringName = &"set_breakpoint"
const DBG_CMD_CLEAR_BREAKPOINTS: StringName = &"clear_breakpoints"
const DBG_CMD_FORCE_NODE: StringName = &"force_node"
const DBG_CMD_SET_VAR: StringName = &"set_var"
const DBG_CMD_FIRE_EVENT: StringName = &"fire_event"

## 目录索引与算子扫描统一跳过的目录前缀（跳过 `.godot` 缓存与全部插件目录 `res://addons`）
const SCAN_SKIP_DIR_PREFIXES: PackedStringArray = ["res://.godot", "res://addons"]

## 内置图蓝图资源脚本回退路径（仅当全局类表 `get_global_class_list()` 尚未建立缓存时兜底）
const SCRIPT_RUNTIME_FSM_DEF: String = "res://addons/flow_graph/runtime/fsm/ast/fsm_graph_def.gd"
const SCRIPT_RUNTIME_BT_DEF: String = "res://addons/flow_graph/runtime/bt/ast/bt_graph_def.gd"


## 判断 `dir_path` 是否属于扫描跳过目录（严格按路径段边界匹配，若 `scan_root` 显式位于该前缀内则放行）。
static func is_skipped_scan_dir(dir_path: String, scan_root: String = "res://") -> bool:
	var clean_dir: String = dir_path.trim_suffix("/")
	var clean_root: String = scan_root.trim_suffix("/")
	for prefix: String in SCAN_SKIP_DIR_PREFIXES:
		var clean_prefix: String = prefix.trim_suffix("/")
		if clean_root == clean_prefix or clean_root.begins_with(clean_prefix + "/"):
			continue
		if clean_dir == clean_prefix or clean_dir.begins_with(clean_prefix + "/"):
			return true
	return false

#endregion


#region 场景与国际化脚本路径

const SCENE_WORKBENCH: String = "res://addons/flow_graph/editor/ui/workbench/mermaid_workbench.tscn"

const SCRIPT_I18N_ZH: String = "res://addons/flow_graph/editor/i18n/flow_i18n_zh.gd"
const SCRIPT_I18N_EN: String = "res://addons/flow_graph/editor/i18n/flow_i18n_en.gd"
const SCRIPT_INPUT_BINDINGS: String = "res://addons/flow_graph/editor/input/flow_input_bindings.gd"

#endregion


#region 核心模型、编解码、校验、桥接与布局脚本路径

const SCRIPT_GRAPH_MODEL: String = "res://addons/flow_graph/editor/model/mermaid_graph_model.gd"
const SCRIPT_CODEC: String = "res://addons/flow_graph/editor/codec/mermaid_codec.gd"
const SCRIPT_UNDO_STACK: String = "res://addons/flow_graph/editor/command/flow_undo_stack.gd"
const SCRIPT_LINTER: String = "res://addons/flow_graph/editor/lint/flow_graph_linter.gd"

const SCRIPT_RESOURCE_BRIDGE: String = "res://addons/flow_graph/editor/bridge/mermaid_resource_bridge.gd"
const SCRIPT_RESOURCE_CATALOG: String = "res://addons/flow_graph/editor/bridge/mermaid_resource_catalog.gd"
const SCRIPT_OPERATOR_SCANNER: String = "res://addons/flow_graph/editor/bridge/flow_operator_scanner.gd"

const SCRIPT_LAYOUT: String = "res://addons/flow_graph/editor/layout/mermaid_layout.gd"
const SCRIPT_METRICS: String = "res://addons/flow_graph/editor/layout/mermaid_metrics.gd"
const SCRIPT_TOPOLOGY_ANALYZER: String = "res://addons/flow_graph/editor/layout/mermaid_topology_analyzer.gd"
const SCRIPT_LAYOUT_FSM_HUB: String = "res://addons/flow_graph/editor/layout/algorithms/fsm_hub_layout.gd"
const SCRIPT_LAYOUT_BT_CONTOUR: String = "res://addons/flow_graph/editor/layout/algorithms/bt_contour_layout.gd"
const SCRIPT_LAYOUT_SUGIYAMA_DAG: String = "res://addons/flow_graph/editor/layout/algorithms/sugiyama_dag_layout.gd"

#endregion


#region 调试器与四态会话仓库脚本路径

const SCRIPT_EDITOR_DEBUGGER: String = "res://addons/flow_graph/editor/debugger/mermaid_editor_debugger.gd"
const SCRIPT_SESSION_STORE: String = "res://addons/flow_graph/editor/debugger/mermaid_session_store.gd"
const SCRIPT_SESSION_DISK_WATCHER: String = "res://addons/flow_graph/editor/debugger/session_disk_watcher.gd"
const SCRIPT_SESSION_FRAME_BUFFER: String = "res://addons/flow_graph/editor/debugger/session_frame_ring_buffer.gd"
const SCRIPT_SESSION_SOURCE_APPLIER: String = "res://addons/flow_graph/editor/debugger/session_source_applier.gd"
const SCRIPT_SESSION_LIVE_TRACKER: String = "res://addons/flow_graph/editor/debugger/session_live_tracker.gd"

#endregion


#region 主题、画布、检视器与工作台 UI 脚本路径

const SCRIPT_THEME_TOKENS: String = "res://addons/flow_graph/editor/ui/theme/mermaid_theme_tokens.gd"
const SCRIPT_THEME_SERVICE: String = "res://addons/flow_graph/editor/ui/theme/mermaid_theme_service.gd"
const SCRIPT_WORKBENCH_STYLER: String = "res://addons/flow_graph/editor/ui/theme/mermaid_workbench_styler.gd"

const SCRIPT_CANVAS: String = "res://addons/flow_graph/editor/ui/canvas/mermaid_graph_canvas.gd"
const SCRIPT_CANVAS_GEOMETRY: String = "res://addons/flow_graph/editor/ui/canvas/canvas_geometry.gd"
const SCRIPT_CANVAS_PALETTE: String = "res://addons/flow_graph/editor/ui/canvas/canvas_theme_palette.gd"
const SCRIPT_CANVAS_EDGE_ROUTER: String = "res://addons/flow_graph/editor/ui/canvas/canvas_edge_router.gd"
const SCRIPT_CANVAS_PAINTER: String = "res://addons/flow_graph/editor/ui/canvas/canvas_painter.gd"
const SCRIPT_CANVAS_OVERLAY_PAINTER: String = "res://addons/flow_graph/editor/ui/canvas/canvas_overlay_painter.gd"
const SCRIPT_CANVAS_CONTEXT_MENU: String = "res://addons/flow_graph/editor/ui/canvas/canvas_context_menu.gd"
const SCRIPT_CANVAS_QUICK_PICKER: String = "res://addons/flow_graph/editor/ui/canvas/canvas_quick_node_picker.gd"
const SCRIPT_CANVAS_INLINE_RENAMER: String = "res://addons/flow_graph/editor/ui/canvas/canvas_inline_renamer.gd"
const SCRIPT_CANVAS_SELECTION: String = "res://addons/flow_graph/editor/ui/canvas/canvas_selection_model.gd"
const SCRIPT_CANVAS_INPUT_CTRL: String = "res://addons/flow_graph/editor/ui/canvas/canvas_input_controller.gd"
const SCRIPT_CANVAS_TELEMETRY: String = "res://addons/flow_graph/editor/ui/canvas/canvas_telemetry_state.gd"

const SCRIPT_ROUTE_OBSTACLE: String = "res://addons/flow_graph/editor/ui/canvas/routing/edge_obstacle_avoidance.gd"
const SCRIPT_ROUTE_FSM_HUB: String = "res://addons/flow_graph/editor/ui/canvas/routing/fsm_hub_edge_router.gd"
const SCRIPT_ROUTE_BT_BUS: String = "res://addons/flow_graph/editor/ui/canvas/routing/bt_bus_edge_router.gd"
const SCRIPT_ROUTE_DAG_CHANNEL: String = "res://addons/flow_graph/editor/ui/canvas/routing/dag_channel_edge_router.gd"

const SCRIPT_INSPECTOR_STYLE_KIT: String = "res://addons/flow_graph/editor/ui/inspector/inspector_style_kit.gd"
const SCRIPT_INSPECTOR_KPI_CARD: String = "res://addons/flow_graph/editor/ui/inspector/inspector_kpi_card.gd"
const SCRIPT_INSPECTOR_NODE_CARD: String = "res://addons/flow_graph/editor/ui/inspector/inspector_node_editor_card.gd"
const SCRIPT_INSPECTOR_EDGE_SUBCARD: String = "res://addons/flow_graph/editor/ui/inspector/inspector_edge_editor_subcard.gd"
const SCRIPT_INSPECTOR_OUTLINE_CARD: String = "res://addons/flow_graph/editor/ui/inspector/inspector_outline_card.gd"
const SCRIPT_INSPECTOR_BB_CARD: String = "res://addons/flow_graph/editor/ui/inspector/inspector_blackboard_card.gd"

const SCRIPT_NODE_CATALOG: String = "res://addons/flow_graph/editor/ui/palette/flow_node_catalog.gd"
const SCRIPT_NODE_DRAWER_ITEM: String = "res://addons/flow_graph/editor/ui/palette/node_drawer_item_row.gd"
const SCRIPT_NODE_DRAWER: String = "res://addons/flow_graph/editor/ui/palette/mermaid_node_drawer.gd"

const SCRIPT_WORKBENCH: String = "res://addons/flow_graph/editor/ui/workbench/mermaid_workbench.gd"
const SCRIPT_FLOATING_HOST: String = "res://addons/flow_graph/editor/ui/workbench/mermaid_floating_host.gd"
const SCRIPT_INSPECTOR_PANEL: String = "res://addons/flow_graph/editor/ui/workbench/mermaid_inspector_panel.gd"
const SCRIPT_RESOURCE_BROWSER: String = "res://addons/flow_graph/editor/ui/workbench/mermaid_resource_browser.gd"
const SCRIPT_SYNTAX_HIGHLIGHTER: String = "res://addons/flow_graph/editor/ui/workbench/mermaid_syntax_highlighter.gd"
const SCRIPT_WB_NAV_BAR: String = "res://addons/flow_graph/editor/ui/workbench/workbench_nav_scrubber_bar.gd"
const SCRIPT_WB_MUTATION_CTRL: String = "res://addons/flow_graph/editor/ui/workbench/workbench_mutation_controller.gd"
const SCRIPT_WB_DEBUG_CTRL: String = "res://addons/flow_graph/editor/ui/workbench/workbench_debug_session_controller.gd"
const SCRIPT_WB_DPI_SCALER: String = "res://addons/flow_graph/editor/ui/workbench/workbench_dpi_scaler.gd"
const SCRIPT_WB_CHROME_CTRL: String = "res://addons/flow_graph/editor/ui/workbench/workbench_chrome_controller.gd"

#endregion


#region 矢量图标资源路径

const ICON_PLUGIN_MAIN: String = "res://addons/flow_graph/editor/assets/plugin/ico_mermaid_main.svg"

const ICON_STATUS_LIVE: String = "res://addons/flow_graph/editor/assets/status/ico_mg_status_live.svg"
const ICON_STATUS_OFFLINE: String = "res://addons/flow_graph/editor/assets/status/ico_mg_status_offline.svg"
const ICON_STATUS_PAUSE: String = "res://addons/flow_graph/editor/assets/status/ico_mg_pause.svg"
const ICON_STATUS_PLAY: String = "res://addons/flow_graph/editor/assets/status/ico_mg_play.svg"
const ICON_STATUS_STEP: String = "res://addons/flow_graph/editor/assets/status/ico_mg_step.svg"
const ICON_STATUS_BOLT: String = "res://addons/flow_graph/editor/assets/status/ico_mg_bolt_trigger.svg"

const ICON_TB_AUTO_LAYOUT: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_auto_layout.svg"
const ICON_TB_CODE_DSL: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_code_dsl.svg"
const ICON_TB_DIR_SWITCH: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_dir_switch.svg"
const ICON_TB_FIT_VIEW: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_fit_view.svg"
const ICON_TB_LABELS: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_labels.svg"
const ICON_TB_MINIMAP: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_minimap.svg"
const ICON_TB_RESOURCE_LIST: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_resource_list.svg"
const ICON_TB_LEFT_DRAWER: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_left_drawer.svg"
const ICON_TB_SIDEBAR: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_sidebar.svg"
const ICON_TB_SNAP: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_snap.svg"
const ICON_TB_TELEMETRY: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_telemetry.svg"
const ICON_TB_WINDOW_FLOAT: String = "res://addons/flow_graph/editor/assets/toolbar/ico_mg_window_float.svg"

const ICON_NODE_ENTRY: String = "res://addons/flow_graph/editor/assets/node/ico_mg_entry_origin.svg"
const ICON_NODE_ANY: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_any.svg"
const ICON_NODE_FINAL: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_final.svg"
const ICON_NODE_SELECTOR: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_selector.svg"
const ICON_NODE_UTILITY: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_utility.svg"
const ICON_NODE_SEQUENCE: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_sequence.svg"
const ICON_NODE_PARALLEL: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_parallel.svg"
const ICON_NODE_INVERTER: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_inverter.svg"
const ICON_NODE_COOLDOWN: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_cooldown.svg"
const ICON_NODE_DECORATOR: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_decorator.svg"
const ICON_NODE_CONDITION: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_condition.svg"
const ICON_NODE_ACTION: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_action.svg"
const ICON_NODE_WAIT: String = "res://addons/flow_graph/editor/assets/node/ico_mg_kind_wait.svg"

#endregion
