@tool
extends RefCounted

## 检视器卡片 5：实时黑板原位热改与 60 帧历史回放只读快照表（Inspector Live & Scrubbable Blackboard Card）。[br]
##
## - `LIVE` 实时跟随态：`bool` 提供开关直切，`int / float / String` 提供带焦点保护（输入中跳过 60ms 覆盖）的紧凑输入框，回车/失焦发射 [signal live_var_edit_requested]；[br]
## - 历史帧回放态（`_is_scrubbing == true`）或 `SNAPSHOT` 定格态：顶部醒目琥珀色徽章提示 `⏪ 历史帧 #X/Y 快照`，并以斑马纹只读展示。

const MermaidSessionStore = preload(FlowGraphContracts.SCRIPT_SESSION_STORE)
const MermaidThemeService = preload(FlowGraphContracts.SCRIPT_THEME_SERVICE)
const MermaidThemeTokens = preload(FlowGraphContracts.SCRIPT_THEME_TOKENS)
const InspectorStyleKit = preload(FlowGraphContracts.SCRIPT_INSPECTOR_STYLE_KIT)

signal live_var_edit_requested(var_key: String, raw_value: Variant, type_hint: String)

var _kit_ref: InspectorStyleKit = null
var _hdr_lbl: Label = null
var _vars_count_lbl: Label = null
var _scrub_banner: PanelContainer = null
var _scrub_banner_lbl: Label = null
var _vars_list_vbox: VBoxContainer = null
var _var_keys_sig: String = ""
## `{String (key): {"kind": String, "ctrl": Control, "state": Dictionary}}`
var _row_widgets: Dictionary = {}


#region 公开构建与原位刷新

func clear_refs() -> void:
	_kit_ref = null
	_hdr_lbl = null
	_vars_count_lbl = null
	_scrub_banner = null
	_scrub_banner_lbl = null
	_vars_list_vbox = null
	_var_keys_sig = ""
	_row_widgets.clear()


func build(kit: InspectorStyleKit, store: MermaidSessionStore, frame: Dictionary) -> PanelContainer:
	clear_refs()
	_kit_ref = kit
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var card: PanelContainer = kit.make_card(false)
	var vbox: VBoxContainer = kit.make_vbox(7.0)
	card.add_child(vbox)

	var hdr_row: HBoxContainer = kit.make_hbox(6.0)
	vbox.add_child(hdr_row)
	var hdr_lbl: Label = kit.make_label("", kit.fs_body, t.success)
	hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_child(hdr_lbl)
	_hdr_lbl = hdr_lbl

	var cnt_lbl: Label = kit.make_label(FlowEditorI18n.t(&"insp.bb_zero"), kit.fs_sub, t.font_faint)
	hdr_row.add_child(cnt_lbl)
	_vars_count_lbl = cnt_lbl

	var banner := PanelContainer.new()
	banner.visible = false
	var banner_lbl: Label = kit.make_label("", kit.fs_sub, t.warning)
	banner.add_child(banner_lbl)
	vbox.add_child(banner)
	_scrub_banner = banner
	_scrub_banner_lbl = banner_lbl

	var table_panel := PanelContainer.new()
	table_panel.add_theme_stylebox_override("panel", kit.sb_recessed)
	vbox.add_child(table_panel)

	var list_vbox: VBoxContainer = kit.make_vbox(2.0)
	table_panel.add_child(list_vbox)
	_vars_list_vbox = list_vbox

	refresh_live(store, frame)
	return card


func refresh_live(store: MermaidSessionStore, frame: Dictionary) -> void:
	if _kit_ref == null or _vars_list_vbox == null or store == null:
		return
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var is_scrub: bool = bool(frame.get("_is_scrubbing", false))
	var editable_live: bool = store.is_live_selected() and not is_scrub

	if _hdr_lbl != null:
		if is_scrub:
			_hdr_lbl.text = FlowEditorI18n.t(&"insp.bb_hdr_scrub")
			_hdr_lbl.add_theme_color_override("font_color", t.warning)
		elif store.is_snapshot_selected():
			_hdr_lbl.text = FlowEditorI18n.t(&"insp.bb_hdr_snap")
			_hdr_lbl.add_theme_color_override("font_color", t.warning)
		else:
			_hdr_lbl.text = FlowEditorI18n.t(&"insp.bb_hdr_live")
			_hdr_lbl.add_theme_color_override("font_color", t.success)

	if _scrub_banner != null and _scrub_banner_lbl != null:
		_scrub_banner.visible = is_scrub
		if is_scrub:
			var s_idx: int = int(frame.get("_scrub_index", 0)) + 1
			var s_tot: int = maxi(1, int(frame.get("_scrub_total", 1)))
			_kit_ref.apply_status_pill_theme(_scrub_banner, _scrub_banner_lbl, FlowEditorI18n.t(&"insp.bb_banner_scrub", [s_idx, s_tot]), t.warning)

	var raw_vars: Variant = frame.get("vars", {})
	var vdict: Dictionary = raw_vars as Dictionary if raw_vars is Dictionary else {}
	_sync_rows_in_place(vdict, editable_live)

#endregion


#region O(N) 零抖动行同步与焦点保护

func _sync_rows_in_place(vdict: Dictionary, editable_live: bool) -> void:
	var kit: InspectorStyleKit = _kit_ref
	var t: MermaidThemeTokens = MermaidThemeService.tokens()
	var keys_arr: PackedStringArray = PackedStringArray()
	var type_parts: PackedStringArray = PackedStringArray()
	for k: Variant in vdict.keys():
		var ks: String = str(k)
		keys_arr.append(ks)
		type_parts.append("%s:%d" % [ks, typeof(vdict[k])])
	var sig: String = "%s::%s" % ["RW" if editable_live else "RO", "|".join(type_parts)]

	if _vars_count_lbl != null:
		_vars_count_lbl.text = FlowEditorI18n.t(&"insp.bb_count_fmt", [keys_arr.size()])

	if sig == _var_keys_sig and not keys_arr.is_empty():
		for k_str: String in keys_arr:
			if not _row_widgets.has(k_str):
				continue
			var wrec: Dictionary = _row_widgets[k_str] as Dictionary
			var wkind: String = str(wrec["kind"])
			var cur_val: Variant = vdict[k_str]
			if wkind == "bool":
				var cb: CheckBox = wrec["ctrl"] as CheckBox
				var bv: bool = bool(cur_val)
				cb.set_pressed_no_signal(bv)
				cb.text = "true" if bv else "false"
			elif wkind == "edit":
				var ed: LineEdit = wrec["ctrl"] as LineEdit
				if not ed.has_focus():
					var formatted_s: String = _editable_string(cur_val)
					ed.text = formatted_s
					(wrec["state"] as Dictionary)["base"] = formatted_s
			else:
				var lbl: Label = wrec["ctrl"] as Label
				var fmt: Dictionary = InspectorStyleKit.format_watch_value(cur_val)
				lbl.text = str(fmt["text"])
				lbl.add_theme_color_override("font_color", fmt["color"] as Color)
		return

	_var_keys_sig = sig
	_row_widgets.clear()
	for child: Node in _vars_list_vbox.get_children():
		_vars_list_vbox.remove_child(child)
		child.free()

	if keys_arr.is_empty():
		_vars_list_vbox.add_child(kit.make_label(FlowEditorI18n.t(&"insp.bb_empty"), kit.fs_sub, t.font_faint))
		return

	for i: int in range(keys_arr.size()):
		var k_name: String = keys_arr[i]
		var val: Variant = vdict[k_name]
		var stripe := PanelContainer.new()
		stripe.add_theme_stylebox_override("panel", kit.sb_row_stripe_odd if (i % 2 == 1) else kit.sb_row_stripe_even)

		var row: HBoxContainer = kit.make_hbox(8.0)
		stripe.add_child(row)

		var k_lbl: Label = kit.make_label(k_name, kit.fs_body, t.font_dim)
		k_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(k_lbl)

		if editable_live and typeof(val) == TYPE_BOOL:
			var b_init: bool = bool(val)
			var cb: CheckBox = kit.make_check_box("true" if b_init else "false", b_init, func(on: bool) -> void:
				live_var_edit_requested.emit(k_name, on, "bool")
			)
			row.add_child(cb)
			_row_widgets[k_name] = {"kind": "bool", "ctrl": cb, "state": {}}
		elif editable_live and typeof(val) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
			var thint: String = _type_hint_for(val)
			var init_txt: String = _editable_string(val)
			var st_dict: Dictionary = {"base": init_txt}
			var ed: LineEdit = kit.make_line_edit(init_txt, _placeholder_for_type(thint))
			ed.size_flags_horizontal = Control.SIZE_SHRINK_END
			ed.custom_minimum_size = Vector2(roundf(108.0 * kit.s), roundf(22.0 * kit.s))
			ed.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var submit_fn: Callable = func() -> void:
				var raw_s: String = ed.text.strip_edges()
				if raw_s != str(st_dict["base"]):
					st_dict["base"] = raw_s
					live_var_edit_requested.emit(k_name, raw_s, thint)
			ed.text_submitted.connect(func(_s: String) -> void:
				submit_fn.call()
				ed.release_focus()
			)
			ed.focus_exited.connect(submit_fn)
			row.add_child(ed)
			_row_widgets[k_name] = {"kind": "edit", "ctrl": ed, "state": st_dict}
		else:
			var fmt_v: Dictionary = InspectorStyleKit.format_watch_value(val)
			var val_lbl: Label = kit.make_label(str(fmt_v["text"]), kit.fs_body, fmt_v["color"] as Color)
			val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(val_lbl)
			_row_widgets[k_name] = {"kind": "ro", "ctrl": val_lbl, "state": {}}

		_vars_list_vbox.add_child(stripe)


static func _type_hint_for(val: Variant) -> String:
	match typeof(val):
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		_: return "String"


static func _placeholder_for_type(thint: String) -> String:
	match thint:
		"int": return FlowEditorI18n.t(&"insp.ph_int")
		"float": return FlowEditorI18n.t(&"insp.ph_float")
		_: return FlowEditorI18n.t(&"insp.ph_string")


static func _editable_string(val: Variant) -> String:
	if typeof(val) == TYPE_FLOAT:
		return "%.2f" % float(val)
	return str(val)

#endregion
