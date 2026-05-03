extends Node

#region Constants
const JC := preload("res://src/JournalConsts.gd")
const SAVE_DIR := "user://JournalMod"
const SAVE_FILE := "user://JournalMod/journal.json"
const SAVE_DEBOUNCE_SEC := 0.42
const INPUT_WAIT_FRAMES := 600
const LAYER_ORDER := 256
const VIEWPORT_MARGIN := 8.0
const HEADER_CLOSE_BTN_SIZE := Vector2(32, 32)

const PANEL_MIN_SIZE := Vector2(620, 460)
const BODY_MIN_HEIGHT := 120
const RESIZE_STRIP := 7.0
const RESIZE_CORNER := 12.0
const HEADER_RESIZE_SKIP := 52.0

const RZ_RIGHT := 1
const RZ_BOTTOM := 2
const RZ_LEFT := 4

const UI_BG := Color(20.0 / 255.0, 20.0 / 255.0, 22.0 / 255.0, 0.92)
const UI_LINE := Color(1, 1, 1, 0.065)
const UI_MUTED := Color(1, 1, 1, 0.48)
const BACKDROP_COLOR := Color(0.02, 0.02, 0.03, 0.82)
#endregion

#region State
var _layer: CanvasLayer
var _body: TextEdit
var _save_timer: Timer
var _panel_drag_root: Control

var _dragging: bool = false
var _drag_pointer_offset: Vector2
var _resizing: bool = false
var _resize_edge: int = 0
var _resize_begin_mouse: Vector2
var _resize_begin_root_size: Vector2
var _resize_begin_root_global: Vector2

var _journal_open: bool = false
var _mouse_mode_before_journal := Input.MOUSE_MODE_VISIBLE
var _tree_paused_for_journal: bool = false
var _freeze_before_journal: bool = false
var _note_text: String = ""
var _syncing_body: bool = false
#endregion

#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _await_input_action_ready()
	_load_save_or_default()
	_build_ui()
	_sync_body_from_model()
	_layer.hide()
	call_deferred("_center_journal_panel")
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(_delta: float) -> void:
	if not _dragging and not _resizing:
		set_process(false)
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_clear_drag_resize()
		return
	if _resizing:
		_apply_panel_resize_frame()
		return
	_panel_drag_root.global_position = _viewport_mouse() - _drag_pointer_offset
	_clamp_panel_to_viewport()


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	_save_timer.stop()
	_save_to_disk()
	if not _journal_open:
		return
	Input.set_mouse_mode(_mouse_mode_before_journal)
	if _tree_paused_for_journal:
		get_tree().paused = false
		_tree_paused_for_journal = false
	var gd := _game_data_resource()
	if gd:
		gd.set("freeze", _freeze_before_journal)
#endregion

#region Persistence
func _load_save_or_default() -> void:
	_note_text = ""
	if not FileAccess.file_exists(SAVE_FILE):
		return
	var file := FileAccess.open(SAVE_FILE, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data := parsed as Dictionary
	var ver := int(data.get(JC.KEY_JSON_VERSION, 0))
	if ver == JC.SAVE_FORMAT_VERSION:
		_note_text = str(data.get(JC.KEY_JSON_TEXT, ""))
	elif ver == JC.SAVE_FORMAT_VERSION_TABS:
		_note_text = _merge_legacy_tabs(data)
	else:
		_note_text = ""


func _merge_legacy_tabs(data: Dictionary) -> String:
	var raw: Variant = data.get(JC.KEY_JSON_TABS, [])
	if typeof(raw) != TYPE_ARRAY:
		return ""
	var chunks: PackedStringArray = []
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d := item as Dictionary
		var title: String = str(d.get(JC.KEY_LEGACY_TAB_TITLE, "")).strip_edges()
		var body: String = str(d.get(JC.KEY_LEGACY_TAB_TEXT, ""))
		if title.is_empty():
			chunks.append(body)
		else:
			chunks.append("%s\n%s" % [title, body])
	if chunks.is_empty():
		return ""
	var merged := chunks[0]
	for i in range(1, chunks.size()):
		merged += "\n\n" + chunks[i]
	return merged.strip_edges()


func _save_to_disk() -> void:
	if _body:
		_note_text = _body.text
	var payload := {
		JC.KEY_JSON_VERSION: JC.SAVE_FORMAT_VERSION,
		JC.KEY_JSON_TEXT: _note_text,
	}
	var mkdir_err := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SAVE_DIR)
	)
	if mkdir_err != OK:
		push_warning("[Journal] mkdir failed: %s" % str(mkdir_err))
	var writer := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if writer == null:
		push_warning(
			"[Journal] write failed %s (%s)"
			% [SAVE_FILE, str(FileAccess.get_open_error())]
		)
		return
	writer.store_string(JSON.stringify(payload, "\t"))
#endregion

#region UI — build
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = LAYER_ORDER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	_layer.add_child(_make_backdrop())
	_layer.add_child(_make_journal_shell())

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SEC
	_save_timer.timeout.connect(_save_to_disk)
	add_child(_save_timer)


func _make_backdrop() -> ColorRect:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_left = 0
	backdrop.offset_top = 0
	backdrop.offset_right = 0
	backdrop.offset_bottom = 0
	backdrop.color = BACKDROP_COLOR
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	return backdrop


func _make_journal_shell() -> Control:
	var shell := Control.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.custom_minimum_size = PANEL_MIN_SIZE
	root.size = PANEL_MIN_SIZE
	shell.add_child(root)
	_panel_drag_root = root

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_equipment_shell(panel)
	root.add_child(panel)

	var theme := _load_game_theme()
	var column := _make_column()
	panel.add_child(column)
	_build_header(column, theme)
	column.add_child(_make_horizontal_rule())
	_build_body_area(column, theme)
	column.add_child(_make_horizontal_rule())
	_build_footer(column, theme)
	_add_resize_grips(root)
	return shell


func _make_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	return column


func _build_header(column: VBoxContainer, theme: Theme) -> void:
	var head_margin := MarginContainer.new()
	_set_margin(head_margin, 18, 16, 14, 10)
	column.add_child(head_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_margin.add_child(header)

	var header_lead := Control.new()
	header_lead.custom_minimum_size = HEADER_CLOSE_BTN_SIZE
	header_lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(header_lead)

	var title := Label.new()
	title.text = "Journal"
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_font(theme, title, 20, Color.WHITE)
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.gui_input.connect(_on_title_bar_gui_input)
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = HEADER_CLOSE_BTN_SIZE
	close_btn.tooltip_text = "Close"
	close_btn.pressed.connect(_close_modal)
	_apply_font(theme, close_btn, 24, Color(0.95, 0.95, 0.95, 1))
	close_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	close_btn.add_theme_color_override("font_pressed_color", Color(0.75, 0.75, 0.75, 1))
	header.add_child(close_btn)


func _build_body_area(column: VBoxContainer, theme: Theme) -> void:
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_set_margin(body_margin, 16, 12, 16, 12)
	column.add_child(body_margin)

	_body = TextEdit.new()
	_body.custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body.scroll_fit_content_height = false
	_body.placeholder_text = "Start writing…"
	_body.text_changed.connect(_on_body_text_changed)
	_style_note_field(_body, theme)
	body_margin.add_child(_body)


func _build_footer(column: VBoxContainer, theme: Theme) -> void:
	var pad := MarginContainer.new()
	_set_margin(pad, 16, 8, 16, 10)
	column.add_child(pad)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(row)

	var hint := Label.new()
	hint.text = "Autosaves while you type"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(theme, hint, 13, UI_MUTED)
	row.add_child(hint)


func _make_horizontal_rule() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.color = UI_LINE
	return line


func _set_margin(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)


func _apply_font(theme: Theme, control: Control, font_size: int, color: Color) -> void:
	if theme and theme.default_font:
		control.add_theme_font_override("font", theme.default_font)
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)


func _style_equipment_shell(panel: PanelContainer) -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI_BG
	panel_style.set_border_width_all(1)
	panel_style.border_color = UI_LINE
	panel_style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", panel_style)


func _style_note_field(te: TextEdit, theme: Theme) -> void:
	te.context_menu_enabled = false
	te.shortcut_keys_enabled = true
	te.middle_mouse_paste_enabled = false
	te.drag_and_drop_selection_enabled = false
	if theme and theme.default_font:
		te.add_theme_font_override("font", theme.default_font)
	te.add_theme_font_size_override("font_size", 16)
	te.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	te.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.set_border_width_all(1)
	focus.border_color = UI_LINE
	focus.set_content_margin_all(0)
	te.add_theme_stylebox_override("focus", focus)
	te.add_theme_constant_override("line_spacing", 2)
	te.add_theme_color_override("font_color", Color.WHITE)
	te.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.38))
	te.add_theme_color_override("caret_color", Color(1, 1, 1, 0.92))
	te.add_theme_color_override(
		"selection_color",
		Color(0.5, 0.55, 0.52, 0.35)
	)
	te.gui_input.connect(func(ev: InputEvent) -> void: _swallow_right_click(te, ev))


func _load_game_theme() -> Theme:
	if not ResourceLoader.exists(JC.GAME_THEME_PATH):
		return null
	var loaded := load(JC.GAME_THEME_PATH)
	return loaded as Theme
#endregion

#region UI — resize grips
func _add_resize_grips(root: Control) -> void:
	var strip := RESIZE_STRIP
	var corner := RESIZE_CORNER
	var skip := HEADER_RESIZE_SKIP

	_add_resize_grip(
		root, RZ_LEFT, Control.CURSOR_HSIZE, Control.PRESET_LEFT_WIDE,
		0.0, skip, strip, -corner
	)
	_add_resize_grip(
		root, RZ_RIGHT, Control.CURSOR_HSIZE, Control.PRESET_RIGHT_WIDE,
		-strip, skip, 0.0, -corner
	)
	_add_resize_grip(
		root, RZ_BOTTOM, Control.CURSOR_VSIZE, Control.PRESET_BOTTOM_WIDE,
		corner, -strip, -corner, 0.0
	)
	_add_resize_grip(
		root, RZ_LEFT | RZ_BOTTOM, Control.CURSOR_BDIAGSIZE, Control.PRESET_BOTTOM_LEFT,
		0.0, -corner, corner, 0.0
	)
	_add_resize_grip(
		root, RZ_RIGHT | RZ_BOTTOM, Control.CURSOR_FDIAGSIZE, Control.PRESET_BOTTOM_RIGHT,
		-corner, -corner, 0.0, 0.0
	)


func _add_resize_grip(
	root: Control,
	edge: int,
	cursor_shape: Control.CursorShape,
	preset,
	offset_left: float,
	offset_top: float,
	offset_right: float,
	offset_bottom: float
) -> void:
	var grip := Control.new()
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = cursor_shape
	grip.gui_input.connect(func(ev: InputEvent) -> void: _on_resize_grip_gui_input(ev, edge))
	grip.set_anchors_preset(preset)
	grip.offset_left = offset_left
	grip.offset_top = offset_top
	grip.offset_right = offset_right
	grip.offset_bottom = offset_bottom
	root.add_child(grip)
#endregion

#region Panel geometry
func _viewport_mouse() -> Vector2:
	return get_viewport().get_mouse_position()


func _max_panel_extents_from(top_left_global: Vector2) -> Vector2:
	var vr := get_viewport().get_visible_rect()
	return Vector2(
		maxf(vr.end.x - top_left_global.x - VIEWPORT_MARGIN, PANEL_MIN_SIZE.x),
		maxf(vr.end.y - top_left_global.y - VIEWPORT_MARGIN, PANEL_MIN_SIZE.y)
	)


func _center_journal_panel() -> void:
	if _panel_drag_root == null:
		return
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect()
	var panel_size := _panel_drag_root.size
	if panel_size.x < 1.0 or panel_size.y < 1.0:
		panel_size = _panel_drag_root.get_combined_minimum_size()
	_panel_drag_root.position = Vector2(
		vp.position.x + (vp.size.x - panel_size.x) * 0.5,
		vp.position.y + (vp.size.y - panel_size.y) * 0.5
	)
	_clamp_panel_to_viewport()


func _clamp_panel_to_viewport() -> void:
	if _panel_drag_root == null:
		return
	var vr := get_viewport().get_visible_rect()
	var sz := _panel_drag_root.size
	var p := _panel_drag_root.global_position
	var min_x := vr.position.x + VIEWPORT_MARGIN
	var min_y := vr.position.y + VIEWPORT_MARGIN
	var max_x := vr.end.x - sz.x - VIEWPORT_MARGIN
	var max_y := vr.end.y - sz.y - VIEWPORT_MARGIN
	if max_x < min_x:
		max_x = min_x
	if max_y < min_y:
		max_y = min_y
	p.x = clampf(p.x, min_x, max_x)
	p.y = clampf(p.y, min_y, max_y)
	_panel_drag_root.global_position = p


func _on_viewport_size_changed() -> void:
	_clamp_panel_to_viewport()


func _apply_panel_resize_frame() -> void:
	var root := _panel_drag_root
	var delta := _viewport_mouse() - _resize_begin_mouse
	var begin_size := _resize_begin_root_size
	var begin_global := _resize_begin_root_global
	var min_sz := PANEL_MIN_SIZE

	var new_x := begin_global.x
	var new_y := begin_global.y
	var new_w := begin_size.x
	var new_h := begin_size.y

	if _resize_edge & RZ_LEFT:
		var cand_w := begin_size.x - delta.x
		cand_w = maxf(cand_w, min_sz.x)
		var try_x := begin_global.x + begin_size.x - cand_w
		var max_w := _max_panel_extents_from(Vector2(try_x, begin_global.y)).x
		new_w = minf(cand_w, max_w)
		new_x = begin_global.x + begin_size.x - new_w
	else:
		new_x = begin_global.x
		if _resize_edge & RZ_RIGHT:
			new_w = clampf(
				begin_size.x + delta.x,
				min_sz.x,
				_max_panel_extents_from(begin_global).x
			)

	if _resize_edge & RZ_BOTTOM:
		new_h = clampf(
			begin_size.y + delta.y,
			min_sz.y,
			_max_panel_extents_from(Vector2(new_x, begin_global.y)).y
		)
	else:
		new_h = begin_size.y

	root.global_position = Vector2(new_x, new_y)
	root.size = Vector2(new_w, new_h)
	_clamp_panel_to_viewport()
#endregion

#region Input
func _on_title_bar_gui_input(event: InputEvent) -> void:
	if _panel_drag_root == null or _resizing:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_pointer_offset = _viewport_mouse() - _panel_drag_root.global_position
				set_process(true)
			else:
				_dragging = false
				if not _resizing:
					set_process(false)


func _on_resize_grip_gui_input(event: InputEvent, edge: int) -> void:
	if _panel_drag_root == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_dragging = false
		_resizing = true
		_resize_edge = edge
		_resize_begin_mouse = _viewport_mouse()
		_resize_begin_root_size = _panel_drag_root.size
		_resize_begin_root_global = _panel_drag_root.global_position
		set_process(true)
	else:
		_resizing = false
		_resize_edge = 0
		if not _dragging:
			set_process(false)


func _clear_drag_resize() -> void:
	_dragging = false
	_resizing = false
	_resize_edge = 0
	set_process(false)


func _swallow_right_click(te: TextEdit, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			te.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(JC.INPUT_ACTION_TOGGLE):
		return
	if Input.is_action_just_pressed(JC.INPUT_ACTION_TOGGLE):
		_toggle_modal()
		get_viewport().set_input_as_handled()
		return
	if (
		_journal_open
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		_close_modal()
		get_viewport().set_input_as_handled()
#endregion

#region Modal & game integration
func _await_input_action_ready() -> void:
	var action := JC.INPUT_ACTION_TOGGLE
	var waited := 0
	while not InputMap.has_action(action) and waited < INPUT_WAIT_FRAMES:
		await get_tree().process_frame
		waited += 1
	if not InputMap.has_action(action):
		push_warning("[Journal] Missing InputMap action %s" % action)


func _sync_body_from_model() -> void:
	if _body == null:
		return
	_syncing_body = true
	_body.text = _note_text
	_syncing_body = false


func _focus_body() -> void:
	if not _journal_open or _body == null or not is_instance_valid(_body):
		return
	_body.grab_focus()


func _on_body_text_changed() -> void:
	if _syncing_body:
		return
	_note_text = _body.text
	_save_timer.start()


func _pause_entire_tree_while_open_enabled() -> bool:
	var cfg := get_node_or_null("/root/JournalConfig")
	if cfg and cfg.has_method("is_pause_game_while_open"):
		return cfg.is_pause_game_while_open()
	return true


func _game_data_resource() -> Resource:
	if not ResourceLoader.exists(JC.GAME_DATA_PATH):
		return null
	return load(JC.GAME_DATA_PATH) as Resource


func _set_modal_open(opened: bool) -> void:
	if opened == _journal_open:
		return
	_journal_open = opened
	if opened:
		_mouse_mode_before_journal = Input.mouse_mode
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		var gd_open := _game_data_resource()
		if gd_open:
			_freeze_before_journal = bool(gd_open.get("freeze"))
			gd_open.set("freeze", true)
		_sync_body_from_model()
		_layer.show()
		_tree_paused_for_journal = _pause_entire_tree_while_open_enabled()
		if _tree_paused_for_journal:
			get_tree().paused = true
		call_deferred("_focus_body")
	else:
		_clear_drag_resize()
		Input.set_mouse_mode(_mouse_mode_before_journal)
		_save_timer.stop()
		_save_to_disk()
		_layer.hide()
		if _tree_paused_for_journal:
			get_tree().paused = false
			_tree_paused_for_journal = false
		var gd_close := _game_data_resource()
		if gd_close:
			gd_close.set("freeze", _freeze_before_journal)


func _close_modal() -> void:
	_set_modal_open(false)


func _toggle_modal() -> void:
	_set_modal_open(not _journal_open)
#endregion
