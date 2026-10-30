@tool
extends RefCounted

## Mermaid DSL 语法高亮构建器（Godot 4 Script Editor Color-Matched Highlighter）。[br]
##
## 直接复用用户当前 Godot 4 脚本编辑器的语法配色（`text_editor/theme/highlighting/*`）：[br]
## 图类型声明使用流程控制关键字色、结构关键字使用关键字色、流向常量使用引擎类型色，字符串 / 数字 / 符号 / `%%` 注释与 GDScript 完全一致。

const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)

const DIAGRAM_WORDS: Array[String] = ["stateDiagram", "v2", "flowchart", "graph"]
const STRUCTURE_WORDS: Array[String] = ["state", "as", "direction", "subgraph", "end", "note", "classDef", "class"]
const DIRECTION_WORDS: Array[String] = ["LR", "RL", "TD", "TB", "BT"]


static func create() -> CodeHighlighter:
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var hl := CodeHighlighter.new()
	hl.number_color = t.code_number
	hl.symbol_color = t.code_symbol
	hl.function_color = t.code_function
	hl.member_variable_color = t.code_member
	for w: String in DIAGRAM_WORDS:
		hl.add_keyword_color(w, t.code_control_flow)
	for w2: String in STRUCTURE_WORDS:
		hl.add_keyword_color(w2, t.code_keyword)
	for w3: String in DIRECTION_WORDS:
		hl.add_keyword_color(w3, t.code_engine_type)
	hl.add_color_region("\"", "\"", t.code_string, true)
	hl.add_color_region("%%", "", t.code_comment, true)
	return hl
