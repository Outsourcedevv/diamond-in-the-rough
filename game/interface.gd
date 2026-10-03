extends CanvasLayer
class_name RoughInterface

signal request_start(mode: String, address: String, port: int, new_save: bool)
signal request_resume
signal request_action(kind: String, args: Dictionary)
signal setting_changed(key: String, value: Variant)

const INK := Color("202426")
const CREAM := Color("f2efe7")
const MUTED := Color("b0b3ae")
const MINT := Color("d8b06b")
const ORANGE := Color("d8b06b")
const PANEL := Color(0.105, 0.12, 0.125, 0.97)

var menu_visible: bool = true
var inspecting: bool = false
var _game: Node
var _root: Control
var _menu: Control
var _hud: Control
var _modal: Control
var _modal_title: Label
var _modal_subtitle: Label
var _modal_body: VBoxContainer
var _inspection: Control
var _inspection_title: Label
var _inspection_tag: Label
var _inspection_body: VBoxContainer
var _money: Label
var _network: Label
var _objective: Label
var _tool: Label
var _capacity: Label
var _tool_card: PanelContainer
var _objective_card: PanelContainer
var _prompt: Label
var _toast: Label
var _toast_panel: PanelContainer
var _toast_clock: float = 0.0
var _resume_button: Button
var _save_button: Button
var _return_button: Button
var _new_button: Button
var _continue_button: Button
var _coop_button: Button
var _menu_title: Label
var _address: LineEdit
var _port: SpinBox
var _font: SystemFont
var _bold: SystemFont
var _session_text: String = "Solo"
var _last_state: Variant
var _modal_return_title: bool = false
var _modal_kind: String = ""
var _voice_badge: Label
var _voice_meter: ProgressBar
var _voice_status: Label
var _voice_enabled: CheckButton
var _mic_muted: CheckButton
var _input_devices: OptionButton
var _voice_text: String = ""
var _voice_level: float = 0.0
var _voice_transmitting: bool = false
var _update_status: Dictionary = {}
var _update_version: Label
var _update_message: Label
var _update_details: Label
var _update_progress: ProgressBar
var _update_primary: Button
var _update_check: Button
var _update_auth: Control
var _update_token: LineEdit
var _update_cli: Button
var _update_auto_check: CheckButton
var _modal_panel: PanelContainer
var _inspection_panel: PanelContainer
var _menu_brand: VBoxContainer
var _menu_actions: ScrollContainer
var _menu_footer: Label
var _money_panel: PanelContainer
var _network_panel: VBoxContainer
var _prompt_panel: PanelContainer
var _reticle: Control
var _tutorial_panel: PanelContainer
var _tutorial_step: Label
var _tutorial_title: Label
var _tutorial_instruction: Label
var _tutorial_key: Label
var _tutorial_target: Label
var _tutorial_data: Dictionary = {}
var _viewport_size := Vector2.ZERO

func build(game: Node) -> void:
	_game = game
	layer = 20
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Segoe UI", "Arial", "sans-serif"])
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 600
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", CREAM)
	for kind in ["Button","OptionButton"]:
		theme.set_color("font_color", kind, CREAM)
		theme.set_color("font_hover_color", kind, CREAM)
		theme.set_color("font_pressed_color", kind, INK)
		theme.set_color("font_disabled_color", kind, Color("717773"))
		theme.set_stylebox("normal", kind, _style(Color("303536"),0,14,10))
		theme.set_stylebox("hover", kind, _style(Color("414746"),0,14,10))
		theme.set_stylebox("pressed", kind, _style(MINT,0,14,10))
		theme.set_stylebox("disabled", kind, _style(Color("262b2c"),0,14,10))
		theme.set_stylebox("focus", kind, _style(Color(0,0,0,0),0,14,10,MINT))
	theme.set_color("font_color", "LineEdit", CREAM)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", MINT)
	theme.set_stylebox("normal", "LineEdit", _style(Color("15191a"),0,12,10,Color("464d49")))
	theme.set_stylebox("focus", "LineEdit", _style(Color("15191a"),0,12,10,MINT))
	theme.set_stylebox("slider", "HSlider", _style(Color("505752"),0,0,2))
	theme.set_stylebox("grabber_area", "HSlider", _style(MINT,0,0,2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _style(CREAM,0,0,2))
	theme.set_stylebox("separator", "HSeparator", _style(Color("464d49"),0,0,0))
	theme.set_color("font_color", "CheckButton", CREAM)
	theme.set_color("font_hover_color", "CheckButton", CREAM)
	theme.set_color("font_pressed_color", "CheckButton", CREAM)
	theme.set_color("font_hover_pressed_color", "CheckButton", CREAM)
	for kind in ["normal","pressed","disabled"]:
		theme.set_stylebox(kind,"CheckButton",_style(Color(0,0,0,0),0,0,8))
	for kind in ["hover","hover_pressed"]:
		theme.set_stylebox(kind,"CheckButton",_style(Color("303536"),0,0,8))
	_root.theme = theme
	_build_hud()
	_build_menu()
	_build_modal()
	_build_inspection()
	_root.resized.connect(_layout)
	_layout()
	show_menu(false)

func _style(color: Color, _radius: int = 0, horizontal: int = 18, vertical: int = 14, border: Color = Color(0,0,0,0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	if border.a > 0:
		style.border_color = border
		style.set_border_width_all(1)
	return style

func _label(text: String, size: int = 16, color: Color = CREAM, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	if bold:
		label.add_theme_font_override("font",_bold)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _wrapped(text: String, size: int = 16, color: Color = MUTED) -> Label:
	var label := _label(text,size,color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Seed a sensible measure before containers arrange newly created text.
	# A zero-width wrapped label otherwise asks for a very tall initial panel.
	label.size.x = 300
	return label

func _box(spacing: int = 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",spacing)
	return box

func _button(text: String, callable: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(110,42)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(callable)
	if primary:
		button.add_theme_stylebox_override("normal",_style(MINT,0,14,10))
		button.add_theme_color_override("font_color",INK)
		button.add_theme_font_override("font",_bold)
	return button

func _hud_panel(parent: Node, dark: bool = true) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(Color(0.08,0.095,0.10,0.83) if dark else Color(0,0,0,0),0,14,10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)
	_money_panel = _hud_panel(_hud)
	_money = _label("Funds  $22",16,CREAM,true)
	_money_panel.add_child(_money)
	_network_panel = _box(4)
	_network_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_network_panel)
	_network = _wrapped("Solo",13,CREAM)
	_network.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_network_panel.add_child(_network)
	_voice_badge = _wrapped("",12,MUTED)
	_voice_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_network_panel.add_child(_voice_badge)
	_reticle = Control.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_reticle)
	for rect in [Rect2(-5,-0.5,10,1),Rect2(-0.5,-5,1,10)]:
		var line := ColorRect.new()
		line.color = Color(1,1,0.96,0.72)
		line.position = rect.position
		line.size = rect.size
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_reticle.add_child(line)
	_prompt_panel = _hud_panel(_hud)
	_prompt = _wrapped("",16,CREAM)
	_prompt.max_lines_visible = 4
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt)
	_objective_card = _hud_panel(_hud)
	var objective_box := _box(5)
	_objective_card.add_child(objective_box)
	objective_box.add_child(_label("CURRENT TASK",10,MUTED,true))
	_objective = _wrapped("Walk to the mountain and hold left click to mine ore.",14,CREAM)
	_objective.max_lines_visible = 3
	objective_box.add_child(_objective)
	_tool_card = _hud_panel(_hud)
	var tool_box := _box(3)
	_tool_card.add_child(tool_box)
	_tool = _label("Old pickaxe",16,CREAM,true)
	_capacity = _label("Satchel 0 / 30 ore",13,MUTED)
	tool_box.add_child(_tool)
	tool_box.add_child(_capacity)
	tool_box.add_child(_label("1 Pick   2–4 Explosives   Tab Journal   Esc Pause",11,MUTED))
	_tutorial_panel = _hud_panel(_hud)
	_tutorial_panel.add_theme_stylebox_override("panel",_style(PANEL,0,16,14,Color("5e6254")))
	var tutorial_box := _box(5)
	_tutorial_panel.add_child(tutorial_box)
	_tutorial_step = _label("TUTORIAL",10,MINT,true)
	_tutorial_title = _wrapped("",18,CREAM)
	_tutorial_title.add_theme_font_override("font",_bold)
	_tutorial_instruction = _wrapped("",15,CREAM)
	_tutorial_instruction.max_lines_visible = 5
	_tutorial_key = _wrapped("",12,MUTED)
	_tutorial_target = _wrapped("",12,MINT)
	tutorial_box.add_child(_tutorial_step)
	tutorial_box.add_child(_tutorial_title)
	tutorial_box.add_child(_tutorial_instruction)
	tutorial_box.add_child(_tutorial_key)
	tutorial_box.add_child(_tutorial_target)
	_tutorial_panel.hide()
	_toast_panel = _hud_panel(_root)
	_toast_panel.add_theme_stylebox_override("panel",_style(PANEL,0,18,12))
	_toast_panel.z_index = 50
	_toast = _wrapped("",14,CREAM)
	_toast.max_lines_visible = 3
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast)
	_toast_panel.hide()

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu)
	var shade := ColorRect.new()
	shade.color = Color(0.025,0.035,0.04,0.3)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(shade)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.08,0.095,0.1,0.90)
	backdrop.name = "MenuBackdrop"
	_menu.add_child(backdrop)
	_menu_brand = _box(10)
	_menu.add_child(_menu_brand)
	_menu_brand.add_child(_label("MOUNTAIN CLAIM",11,MINT,true))
	_menu_title = _label("DIAMOND\nIN THE ROUGH",42,CREAM,true)
	_menu_brand.add_child(_menu_title)
	_menu_actions = ScrollContainer.new()
	_menu_actions.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu.add_child(_menu_actions)
	var actions := _box(6)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_actions.add_child(actions)
	_resume_button = _button("Resume",_resume,true)
	actions.add_child(_resume_button)
	_new_button = _button("New game",func(): request_start.emit("solo","",_port_number(),true),true)
	actions.add_child(_new_button)
	_continue_button = _button("Continue",func(): request_start.emit("solo","",_port_number(),false))
	actions.add_child(_continue_button)
	_coop_button = _button("Co-op",_show_coop)
	actions.add_child(_coop_button)
	_save_button = _button("Save game",func(): request_action.emit("save",{}))
	actions.add_child(_save_button)
	actions.add_child(_button("Settings",_show_settings))
	actions.add_child(_button("How to play",_show_controls))
	actions.add_child(_button("Updates",_open_updates))
	_return_button = _button("Return to title",func(): request_action.emit("menu",{}))
	actions.add_child(_return_button)
	actions.add_child(_button("Quit",func(): get_tree().quit()))
	_menu_footer = _label("Solo or 4-player co-op",12,MUTED)
	_menu.add_child(_menu_footer)

func _port_number() -> int:
	return int(_port.value) if is_instance_valid(_port) else 24680

func _show_coop() -> void:
	_open_modal("Co-op","Work the same claim with up to four players.")
	_modal_body.add_child(_button("Host game",func(): request_start.emit("host","",_port_number(),false),true))
	_modal_body.add_child(_wrapped("The host owns the save. To join, enter their IP address and port. Use the same game version.",14,MUTED))
	_modal_body.add_child(HSeparator.new())
	_modal_body.add_child(_label("Join a game",18,CREAM,true))
	var network_row := HBoxContainer.new()
	network_row.add_theme_constant_override("separation",10)
	_modal_body.add_child(network_row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host IP address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.custom_minimum_size.y = 42
	network_row.add_child(_address)
	_port = SpinBox.new()
	_port.min_value = 1
	_port.max_value = 65535
	_port.value = 24680
	_port.custom_minimum_size.x = 112
	_port.tooltip_text = "UDP port"
	network_row.add_child(_port)
	_modal_body.add_child(_button("Join game",func(): request_start.emit("join",_address.text.strip_edges(),_port_number(),false)))
	_modal_body.add_child(_wrapped("Hold V to speak to players near you. Press M to mute your microphone.",14,MUTED))

func _build_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_modal)
	var shade := ColorRect.new()
	shade.color = Color(0.025,0.035,0.04,0.64)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(shade)
	_modal_panel = PanelContainer.new()
	_modal_panel.add_theme_stylebox_override("panel",_style(PANEL,0,24,20,Color("464d49")))
	_modal.add_child(_modal_panel)
	var box := _box(12)
	_modal_panel.add_child(box)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",16)
	box.add_child(heading)
	_modal_title = _wrapped("Journal",26,CREAM)
	_modal_title.add_theme_font_override("font",_bold)
	heading.add_child(_modal_title)
	heading.add_child(_button("Close",_close_modal))
	_modal_subtitle = _wrapped("",14,MUTED)
	box.add_child(_modal_subtitle)
	box.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_modal_body = _box(14)
	_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_modal_body)
	_modal.hide()

func _build_inspection() -> void:
	_inspection = Control.new()
	_inspection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_inspection)
	_inspection_panel = _hud_panel(_inspection)
	_inspection_panel.add_theme_stylebox_override("panel",_style(PANEL,0,20,18,Color("464d49")))
	var box := _box(10)
	_inspection_panel.add_child(box)
	_inspection_tag = _wrapped("Inspection",11,MINT)
	box.add_child(_inspection_tag)
	_inspection_title = _wrapped("Uncertified stone",23,CREAM)
	_inspection_title.add_theme_font_override("font",_bold)
	box.add_child(_inspection_title)
	box.add_child(_wrapped("Move the mouse to rotate. Ctrl + wheel to zoom.",13,MUTED))
	box.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_inspection_body = _box(12)
	_inspection_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspection_body)
	box.add_child(_wrapped("Right-click  Finish     Q  Drop",12,MINT))
	_inspection.hide()

func _layout() -> void:
	if not is_instance_valid(_root) or not is_instance_valid(_modal_panel):
		return
	_viewport_size = _root.size
	if _viewport_size.x < 1 or _viewport_size.y < 1:
		_viewport_size = get_viewport().get_visible_rect().size
	var width: float = _viewport_size.x
	var height: float = _viewport_size.y
	var margin: float = clampf(width * 0.025,18,48)
	var menu_width: float = clampf(width * 0.29,290,360)
	var compact: bool = height < 700
	var title_size: int = 34 if compact else 42
	_menu_title.add_theme_font_size_override("font_size",title_size)
	_menu_brand.position = Vector2(margin + 14,margin + 14)
	_menu_brand.size = Vector2(menu_width,_menu_brand.get_combined_minimum_size().y)
	var menu_top: float = _menu_brand.position.y+_menu_brand.get_combined_minimum_size().y+18
	_menu_actions.position = Vector2(margin + 14,menu_top)
	_menu_actions.size = Vector2(menu_width,height - menu_top - margin - 44)
	_menu_footer.position = Vector2(margin + 14,height-margin-24)
	_menu_footer.size = Vector2(menu_width,20)
	var backdrop: ColorRect = _menu.get_node("MenuBackdrop")
	backdrop.size = Vector2(menu_width+margin*2+28,height)
	var modal_width: float = minf(740,width-margin*2)
	var modal_height: float = minf(680,height-margin*2)
	_modal_panel.position = Vector2((width-modal_width)*0.5,(height-modal_height)*0.5)
	_modal_panel.size = Vector2(modal_width,modal_height)
	var inspection_width: float = clampf(width*0.28,310,380)
	var inspection_height: float = minf(580,height-margin*2-50)
	_inspection_panel.position = Vector2(width-margin-inspection_width,(height-inspection_height)*0.5)
	_inspection_panel.size = Vector2(inspection_width,inspection_height)
	_money_panel.position = Vector2(margin,margin)
	_money_panel.size = Vector2(160,42)
	_network_panel.position = Vector2(width-margin-300,margin+8)
	_network_panel.size = Vector2(300,44)
	_reticle.position = Vector2(width*0.5,height*0.5)
	var prompt_width: float = minf(600,width-margin*2-40)
	_prompt_panel.position = Vector2((width-prompt_width)*0.5,height*0.5+24)
	_prompt_panel.size = Vector2(prompt_width,clampf(_prompt.get_minimum_size().y+20,42,104))
	var task_width: float = minf(340,width*0.43)
	_objective_card.position = Vector2(margin,height-margin-112)
	_objective_card.size = Vector2(task_width,112)
	var tool_height: float = maxf(96,_tool_card.get_combined_minimum_size().y)
	_tool_card.position = Vector2(width-margin-290,height-margin-tool_height)
	_tool_card.size = Vector2(290,tool_height)
	var tutorial_height: float = maxf(210,_tutorial_panel.get_combined_minimum_size().y)
	_tutorial_panel.position = Vector2(margin,margin+66 if compact else height-margin-tutorial_height)
	_tutorial_panel.size = Vector2(task_width,tutorial_height)
	var toast_width: float = minf(560,width-margin*2-330)
	toast_width = maxf(toast_width,280)
	_toast_panel.position = Vector2((width-toast_width)*0.5,margin+66)
	_toast_panel.size = Vector2(toast_width,clampf(_toast.get_minimum_size().y+24,44,86))
	if compact and _tutorial_panel.visible:
		toast_width = minf(toast_width,width-task_width-margin*3)
		_toast_panel.position.x = width-margin-toast_width
		_toast_panel.size.x = toast_width

func show_menu(in_game: bool = false) -> void:
	_clear_update_token()
	menu_visible = true
	inspecting = false
	_menu.show()
	_modal.hide()
	_inspection.hide()
	_hud.hide()
	_resume_button.visible = in_game
	_save_button.visible = in_game
	_return_button.visible = in_game
	_new_button.visible = not in_game
	_continue_button.visible = not in_game
	_coop_button.visible = not in_game
	_menu_title.text = "Paused" if in_game else "DIAMOND\nIN THE ROUGH"
	_menu_brand.get_child(0).visible = not in_game
	_menu_footer.text = "Esc to resume" if in_game else "Solo or 4-player co-op"
	_layout()

func hide_menu() -> void:
	_clear_update_token()
	menu_visible = false
	_menu.hide()
	_modal.hide()
	_hud.show()
	_tool_card.show()
	_reticle.show()
	_modal_kind = ""
	_sync_tutorial_visibility()

func _resume() -> void:
	hide_menu()
	request_resume.emit()

func _close_modal() -> void:
	if _modal_return_title:
		show_menu(false)
	else:
		_resume()

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _open_modal(title: String, subtitle: String) -> void:
	_clear_update_token()
	_modal_return_title = not bool(_read(_game,"active",false))
	_modal_kind = ""
	menu_visible = true
	inspecting = false
	_inspection.hide()
	_menu.hide()
	_hud.hide()
	_clear(_modal_body)
	_modal_title.text = title
	_modal_subtitle.text = subtitle
	_modal.show()
	_layout()
	call_deferred("_layout")

func _read(state: Variant, key: String, fallback: Variant = null) -> Variant:
	if state is Dictionary:
		return state.get(key,fallback)
	if state is Object:
		for property in state.get_property_list():
			if str(property.name) == key:
				var value: Variant = state.get(key)
				return value if value != null else fallback
	return fallback

func update_hud(state: Variant, tool_name: String, capacity: int, prompt: String, objective: String, carry_text: String = "") -> void:
	_last_state = state
	_money.text = "Funds  $%s" % str(_read(state,"money",0))
	_tool.text = tool_name
	var held_count: int = 0
	if state is Object and state.has_method("held_ids"):
		held_count = state.held_ids().size()
	else:
		var held: Variant = _read(state,"held",[])
		if held is Array:
			held_count = held.size()
	_capacity.text = carry_text if not carry_text.is_empty() else "%d / %d carried" % [held_count,capacity]
	_prompt.text = prompt
	_prompt_panel.visible = not prompt.is_empty() and not inspecting
	_objective.text = objective

func update_network(text: String) -> void:
	_session_text = text
	_network.text = text.replace("SOLO","Solo").replace("HOST","Host").replace("JOIN","Co-op")

func update_voice_status(text: String, level: float, transmitting: bool) -> void:
	_voice_text = text
	_voice_level = clampf(level,0.0,1.0)
	_voice_transmitting = transmitting
	var accent: Color = MINT if transmitting else MUTED
	if is_instance_valid(_voice_badge):
		_voice_badge.text = text if transmitting or not text.to_lower().contains("solo") else ""
		_voice_badge.add_theme_color_override("font_color",accent)
	if _modal_kind != "settings" or not _modal.visible:
		return
	if is_instance_valid(_voice_status):
		_voice_status.text = text
		_voice_status.add_theme_color_override("font_color",accent)
	if is_instance_valid(_voice_meter):
		_voice_meter.value = _voice_level
		_voice_meter.add_theme_stylebox_override("fill",_style(accent,0,0,0))
	var settings: Variant = _read(_game,"settings",{})
	if is_instance_valid(_voice_enabled):
		_voice_enabled.set_pressed_no_signal(bool(_read(settings,"voice_enabled",true)))
	if is_instance_valid(_mic_muted):
		_mic_muted.set_pressed_no_signal(bool(_read(settings,"mic_muted",false)))

func set_tutorial(data: Dictionary) -> void:
	_tutorial_data = data.duplicate(true)
	var measure: float = minf(340,_root.size.x*0.43)-32
	for label in [_tutorial_title,_tutorial_instruction,_tutorial_key,_tutorial_target]:
		label.size.x = maxf(200,measure)
	_tutorial_title.text = str(data.get("title",""))
	_tutorial_instruction.text = str(data.get("instruction",""))
	var current: int = int(data.get("current",0))
	var total: int = int(data.get("total",0))
	_tutorial_step.text = "TUTORIAL  %d / %d" % [current,total] if total > 0 else "TUTORIAL"
	_tutorial_key.text = str(data.get("key",""))
	_tutorial_key.visible = not _tutorial_key.text.is_empty()
	var target_label: String = str(data.get("target_label",""))
	_tutorial_target.visible = not target_label.is_empty()
	_tutorial_target.text = target_label
	if not target_label.is_empty() and data.has("target_distance_metres"):
		_tutorial_target.text += "  ·  %d m %s" % [roundi(float(data.target_distance_metres)),str(data.get("direction","ahead"))]
	_sync_tutorial_visibility()
	_layout()
	call_deferred("_layout")

func _sync_tutorial_visibility() -> void:
	var tutorial_active: bool = not _tutorial_data.is_empty() and bool(_tutorial_data.get("visible",true))
	_tutorial_panel.visible = tutorial_active and not inspecting
	_objective_card.visible = not tutorial_active and not inspecting

func layout_regions() -> Dictionary:
	var regions := {}
	var panels := {
		"menu_title":_menu_brand, "menu_actions":_menu_actions,
		"modal":_modal_panel, "inspection":_inspection_panel,
		"funds":_money_panel, "network":_network_panel,
		"tool":_tool_card, "objective":_objective_card,
		"tutorial":_tutorial_panel, "prompt":_prompt_panel, "toast":_toast_panel
	}
	for key in panels:
		var panel: Control = panels[key]
		if is_instance_valid(panel) and panel.is_visible_in_tree():
			regions[key] = panel.get_global_rect()
	return regions

func toast(text: String) -> void:
	_toast.text = text
	_toast_clock = clampf(2.4+text.length()*0.025,3.0,6.0)
	_toast_panel.modulate.a = 1.0
	_toast_panel.show()
	_layout()

func _process(delta: float) -> void:
	if _root.size != _viewport_size:
		_layout()
	if _toast_clock > 0.0:
		_toast_clock -= delta
		_toast_panel.modulate.a = minf(1.0,maxf(0.0,_toast_clock*2.5))
		if _toast_clock <= 0.0:
			_toast_panel.hide()

func show_inspection(gem: Dictionary, has_loupe: bool) -> void:
	_clear_update_token()
	inspecting = true
	menu_visible = false
	_menu.hide()
	_modal.hide()
	_hud.show()
	_tool_card.hide()
	_objective_card.hide()
	_tutorial_panel.hide()
	_reticle.hide()
	_prompt_panel.hide()
	_inspection.show()
	_clear(_inspection_body)
	var kind: String = str(gem.get("kind","glass"))
	var candidate: bool = kind in ["diamond","suspect","moissanite"]
	_inspection_title.text = "Uncertified stone" if candidate else str(gem.get("name","Find"))
	_inspection_tag.text = "Loupe and lamp" if has_loupe else "Naked-eye inspection"
	for clue in _clues(gem,has_loupe):
		_inspection_body.add_child(_wrapped(clue,15,CREAM))
	if not has_loupe and kind in ["diamond","suspect","glass","crystal","moissanite"]:
		_inspection_body.add_child(_wrapped("For more detail, buy the loupe and lamp at the equipment display.",13,MUTED))
	if candidate:
		_inspection_body.add_child(_wrapped("Keep this stone. The certification bench can test it.",13,MINT))
	else:
		_inspection_body.add_child(_wrapped("Clean value  $%s" % str(gem.get("value",0)),14,MINT))
		if kind in ["collectible","oddity"]:
			_inspection_body.add_child(_wrapped("C  Add to your collection",13,MINT))
	_layout()
	call_deferred("_layout")

func _clues(gem: Dictionary, loupe: bool) -> Array[String]:
	var kind: String = str(gem.get("kind","glass"))
	var result: Array[String] = []
	match kind:
		"diamond":
			result = ["Breath mist clears almost immediately.","A point behind the stone breaks into a soft haze."]
			if loupe:
				result.append("Razor-clean facet junctions, even up close.")
				result.append("No trapped round bubbles beneath the surface.")
		"suspect", "moissanite":
			result = ["Breath mist clears quickly. A promising sign.","The point behind the stone becomes difficult to read."]
			if loupe:
				var variant: int = abs(int(gem.get("id",0))) % 3
				if variant == 0:
					result.append("Very sharp facet junctions. A tiny doubled edge at the back.")
					result.append("No obvious bubbles. A fine internal seam catches the light.")
				elif variant == 1:
					result.append("Mostly clean edges, with one rounded junction.")
					result.append("A small circular inclusion hides near the base.")
				else:
					result.append("Crisp facets. Back facets split into paired reflections.")
					result.append("No visible bubbles. Bright flashes carry a rainbow fringe.")
		"glass":
			result = ["Breath mist lingers on the surface.","A point behind the stone stays surprisingly readable."]
			if loupe:
				result.append("Slightly rounded facet edges.")
				result.append("A round trapped bubble glints inside.")
		"crystal":
			result = ["Cool and clear. Breath mist clears fairly quickly.","The point behind the stone softens and shifts."]
			if loupe:
				result.append("Fine parallel growth lines run beneath a facet.")
				result.append("A natural-looking seam follows an internal plane.")
		"metal", "scrap":
			result = ["Dense metal with scratched plating.","Suitable for the exchange."]
		"cash":
			result = ["Marked coins and notes.","Trade these at the exchange."]
		"collectible":
			result = ["A decorative imitation.","Keep this piece for your collection, or sell it."]
		"oddity", "junk":
			result = ["Worn surface. No visible crystal structure.","This material has no gem-like optical clues."]
		_:
			result = [str(gem.get("clue","Turn it under the light and watch the surface.")),"Look carefully before deciding what to keep."]
	return result

func hide_inspection() -> void:
	inspecting = false
	_inspection.hide()
	_tool_card.show()
	_reticle.show()
	_sync_tutorial_visibility()

func show_shop(state: Variant) -> void:
	# Compatibility for old callers; purchases happen at the physical displays.
	_last_state = state
	toast("Look at an equipment display and press E to buy it.")

func show_collection(state: Variant) -> void:
	_last_state = state
	_open_modal("Journal","Your finds and progress on the claim.")
	var collection: Variant = _read(state,"collection",_read(state,"collections",[]))
	var count: int = collection.size() if collection is Array or collection is Dictionary else int(collection)
	_modal_body.add_child(_label("Collection",20,CREAM,true))
	_modal_body.add_child(_wrapped("%d finds kept on the display shelf." % count,15,MUTED))
	var names: Array[String] = []
	var gems: Variant = _read(state,"gems",{})
	if collection is Array and gems is Dictionary:
		for item in collection:
			if item is String:
				names.append(str(item))
				continue
			var gem: Variant = gems.get(int(item),{})
			if gem is Dictionary:
				names.append(str(gem.get("name","Find")))
	if not names.is_empty():
		_modal_body.add_child(_wrapped("\n".join(names),14,CREAM))
	_modal_body.add_child(HSeparator.new())
	_modal_body.add_child(_label("The diamond",20,CREAM,true))
	var certified: bool = bool(_read(state,"certified",false))
	_modal_body.add_child(_wrapped("Certified and saved." if certified else "Still buried deep in the mountain's core, hidden among clear quartz crystals. Mine crystal veins, then test promising stones at the certification bench.",15,MUTED))
	_modal_body.add_child(HSeparator.new())
	_modal_body.add_child(_label("Satchel & ore prices",20,CREAM,true))
	var satchel: Dictionary = {}
	var blocks: int = 0
	if state is Object and state.has_method("ore_of"):
		satchel = state.ore_of()
		blocks = state.blocks_mined()
	var lines: Array[String] = []
	var MountainScript: Script = load("res://game/mountain.gd")
	for kind in MountainScript.ORE_ORDER:
		lines.append("%s  $%d   ·   carrying %d" % [MountainScript.ORE_NAMES[kind],int(MountainScript.ORE_VALUES[kind]),int(satchel.get(kind,0))])
	_modal_body.add_child(_wrapped("\n".join(lines),14,CREAM))
	_modal_body.add_child(_wrapped("%d blocks mined so far." % blocks,14,MUTED))
	_modal_body.add_child(HSeparator.new())
	for entry in [{"label":"Save game","action":"save"},{"label":"Recover lost finds","action":"recover"},{"label":"Return to solid ground","action":"unstuck"}]:
		var action: String = str(entry.action)
		_modal_body.add_child(_button(str(entry.label),func(): request_action.emit(action,{})))

func _show_controls() -> void:
	_open_modal("How to play","Mine and blast the mountain, sell ore, and keep clear crystals for the bench.")
	_modal_body.add_child(_button("Start guided tutorial",func(): request_action.emit("tutorial_restart",{}),true))
	if bool(_tutorial_data.get("visible",false)):
		_modal_body.add_child(_button("Skip tutorial",func(): request_action.emit("tutorial_skip",{})))
	_modal_body.add_child(HSeparator.new())
	var rows := [
		["WASD / Mouse","Move and look"],
		["E","Use a station, pick up a find or buy displayed equipment"],
		["Left click (hold)","Mine with your pickaxe or drill, or throw an explosive"],
		["Space","Jump · climb the mountain one block at a time"],
		["Right click","Inspect; move the mouse to rotate"],
		["Mouse wheel","Select a carried find or change storage tray"],
		["Ctrl + wheel","Zoom during inspection"],
		["Q","Drop the selected find"],
		["1 / 2 / 3 / 4","Pickaxe / dynamite / TNT / Mountain Buster"],
		["Tab / Esc","Journal / pause"],
		["V / M","Hold to talk / mute microphone"],
		["C / R","Shelve a fossil / gift a crystal"],
		["F / G / H","Label / foam / hat"]
	]
	for entry in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",20)
		var key := _wrapped(str(entry[0]),13,MINT)
		key.custom_minimum_size.x = 140
		key.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(key)
		row.add_child(_wrapped(str(entry[1]),15,CREAM))
		_modal_body.add_child(row)

func _show_settings() -> void:
	_open_modal("Settings","Preferences are saved on this computer.")
	_modal_kind = "settings"
	var settings: Variant = _read(_game,"settings",{})
	_setting_slider("Mouse sensitivity","sensitivity",float(_read(settings,"sensitivity",0.0025)),0.0005,0.008,0.0001,"%.4f")
	_setting_slider("Field of view","fov",float(_read(settings,"fov",78)),60,110,1,"%.0f°")
	_setting_slider("Master volume","volume",float(_read(settings,"volume",0.65)),0,1,0.01,"%.0f%%",100.0)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = bool(_read(settings,"fullscreen",false))
	fullscreen.toggled.connect(func(value: bool): setting_changed.emit("fullscreen",value))
	_modal_body.add_child(fullscreen)
	_modal_body.add_child(_wrapped("Resize the window or use fullscreen to fit your display.",13,MUTED))
	_modal_body.add_child(HSeparator.new())
	_build_voice_settings(settings)
	_modal_body.add_child(_button("Game updates",_open_updates))

func _open_updates() -> void:
	var updater: Variant = _read(_game,"updater")
	var status: Dictionary = _update_status
	if updater is Object:
		var latest: Variant = _read(updater,"status",status)
		if latest is Dictionary:
			status = latest
	show_updates(status)

func show_updates(status: Dictionary = {}) -> void:
	_open_modal("Game updates","Check, download and install the latest version.")
	_modal_kind = "updates"
	_update_version = _label("",16,MINT,true)
	_modal_body.add_child(_update_version)
	_update_auto_check = CheckButton.new()
	_update_auto_check.text = "Check automatically for updates"
	var settings: Variant = _read(_game,"settings",{})
	_update_auto_check.button_pressed = bool(_read(settings,"auto_updates",true))
	_update_auto_check.toggled.connect(func(value: bool): setting_changed.emit("auto_updates",value))
	_modal_body.add_child(_update_auto_check)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",_style(Color("272b2d"),9,18,16))
	_modal_body.add_child(card)
	var box := _box(12)
	card.add_child(box)
	_update_message = _wrapped("",18,CREAM)
	box.add_child(_update_message)
	_update_progress = ProgressBar.new()
	_update_progress.min_value = 0.0
	_update_progress.max_value = 1.0
	_update_progress.step = 0.001
	_update_progress.show_percentage = false
	_update_progress.custom_minimum_size.y = 12
	_update_progress.add_theme_stylebox_override("background",_style(Color("424747"),4,0,0))
	_update_progress.add_theme_stylebox_override("fill",_style(MINT,4,0,0))
	box.add_child(_update_progress)
	_update_details = _wrapped("",14,MUTED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",10)
	box.add_child(actions)
	_update_check = _button("Check for updates",func(): request_action.emit("updates_check",{}))
	_update_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_update_check)
	_update_primary = _button("Download update",_update_primary_action,true)
	_update_primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_update_primary)
	box.add_child(_update_details)
	_update_auth = PanelContainer.new()
	_update_auth.add_theme_stylebox_override("panel",_style(Color("272b2d"),9,18,16))
	_modal_body.add_child(_update_auth)
	var auth_box := _box(10)
	_update_auth.add_child(auth_box)
	auth_box.add_child(_label("Private repository access",11,ORANGE,true))
	auth_box.add_child(_wrapped("Use an existing GitHub CLI sign-in, or enter a token with read access to this repository. The token is kept in memory for this game session.",13,MUTED))
	_update_cli = _button("Use GitHub CLI sign-in",func(): request_action.emit("updates_use_cli",{}))
	auth_box.add_child(_update_cli)
	var token_row := HBoxContainer.new()
	token_row.add_theme_constant_override("separation",10)
	auth_box.add_child(token_row)
	_update_token = LineEdit.new()
	_update_token.secret = true
	_update_token.context_menu_enabled = false
	_update_token.max_length = 512
	_update_token.placeholder_text = "GitHub repository-read token"
	_update_token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_token.custom_minimum_size.y = 43
	_update_token.text_submitted.connect(func(_text: String): _submit_update_token())
	token_row.add_child(_update_token)
	token_row.add_child(_button("Use token",_submit_update_token))
	_modal_body.add_child(_wrapped("Installing saves your progress and restarts the game. Co-op players need the same version.",13,MUTED))
	_modal_body.add_child(_button("Open GitHub repository",func(): request_action.emit("updates_open_repo",{})))
	update_updates(status)

func _submit_update_token() -> void:
	if not is_instance_valid(_update_token):
		return
	var session_token: String = _update_token.text.strip_edges()
	_update_token.clear()
	if not session_token.is_empty():
		request_action.emit("updates_token",{"token":session_token})
		session_token = ""

func _clear_update_token() -> void:
	if is_instance_valid(_update_token):
		_update_token.clear()

func _update_primary_action() -> void:
	var phase: String = str(_update_status.get("phase","idle"))
	if phase == "available":
		request_action.emit("updates_download",{})
	elif phase == "ready":
		request_action.emit("updates_install",{})

func update_updates(status: Dictionary) -> void:
	_update_status = status.duplicate(true)
	if _modal_kind != "updates" or not _modal.visible or not is_instance_valid(_update_message):
		return
	var phase: String = str(status.get("phase","idle"))
	var busy: bool = phase in ["checking","downloading","installing"]
	var installed: String = str(status.get("installed_version",""))
	var available: String = str(status.get("available_version",""))
	_update_version.text = "Installed: %s" % (installed if not installed.is_empty() else "local build")
	if not available.is_empty():
		_update_version.text += "    ·    Latest: %s" % available
	var messages: Dictionary = {
		"idle":"Check GitHub for the newest workshop build.",
		"checking":"Checking for a new workshop build…",
		"auth_required":"Sign in to access this private repository.",
		"available":"A new workshop build is ready to download.",
		"downloading":"Downloading the update…",
		"ready":"Download verified. Ready to install.",
		"error":"The update could not be completed. You can try again.",
		"current":"Your workshop is up to date.",
		"installing":"Saving your workshop and restarting to install…"
	}
	_update_message.text = str(status.get("message",messages.get(phase,messages.idle)))
	_update_message.add_theme_color_override("font_color",ORANGE if phase in ["error","auth_required"] else CREAM)
	_update_details.text = str(status.get("details",""))
	_update_details.visible = not _update_details.text.is_empty() and phase != "auth_required"
	_update_progress.visible = phase in ["downloading","ready","installing"]
	_update_progress.value = clampf(float(status.get("progress",0.0)),0.0,1.0)
	_update_check.disabled = busy
	_update_primary.visible = phase in ["available","downloading","ready","installing"]
	_update_primary.disabled = phase not in ["available","ready"]
	_update_primary.text = "Save & restart to install" if phase in ["ready","installing"] else "Downloading…" if phase == "downloading" else "Download update"
	_update_auth.visible = not bool(status.get("authenticated",false)) and phase in ["idle","auth_required","error"]
	_update_cli.disabled = busy
	_update_token.editable = not busy

func _build_voice_settings(settings: Variant) -> void:
	_modal_body.add_child(_label("Voice chat",11,ORANGE,true))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(Color("272b2d"),9,18,14))
	_modal_body.add_child(panel)
	var box := _box(10)
	panel.add_child(box)
	var toggles := _box(2)
	toggles.add_theme_constant_override("separation",22)
	box.add_child(toggles)
	_voice_enabled = CheckButton.new()
	_voice_enabled.text = "Enable proximity voice"
	_voice_enabled.button_pressed = bool(_read(settings,"voice_enabled",true))
	_voice_enabled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_enabled.toggled.connect(func(value: bool): setting_changed.emit("voice_enabled",value))
	toggles.add_child(_voice_enabled)
	_mic_muted = CheckButton.new()
	_mic_muted.text = "Mute microphone"
	_mic_muted.button_pressed = bool(_read(settings,"mic_muted",false))
	_mic_muted.toggled.connect(func(value: bool): setting_changed.emit("mic_muted",value))
	toggles.add_child(_mic_muted)
	box.add_child(_label("Microphone",10,MINT,true))
	var device_row := HBoxContainer.new()
	device_row.add_theme_constant_override("separation",10)
	box.add_child(device_row)
	_input_devices = OptionButton.new()
	_input_devices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_devices.custom_minimum_size.y = 43
	_input_devices.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_input_devices.item_selected.connect(func(index: int):
		setting_changed.emit("input_device",_input_devices.get_item_text(index))
	)
	device_row.add_child(_input_devices)
	device_row.add_child(_button("Refresh",_refresh_input_devices))
	_refresh_input_devices()
	var meter_row := _box(5)
	meter_row.add_theme_constant_override("separation",14)
	box.add_child(meter_row)
	_voice_status = _label(_voice_text,12,MUTED,true)
	_voice_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_row.add_child(_voice_status)
	_voice_meter = ProgressBar.new()
	_voice_meter.min_value = 0.0
	_voice_meter.max_value = 1.0
	_voice_meter.step = 0.001
	_voice_meter.show_percentage = false
	_voice_meter.custom_minimum_size = Vector2(160,9)
	_voice_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_voice_meter.tooltip_text = "Microphone input level while holding V in co-op."
	_voice_meter.add_theme_stylebox_override("background",_style(Color("424747"),3,0,0))
	_voice_meter.add_theme_stylebox_override("fill",_style(MINT,3,0,0))
	meter_row.add_child(_voice_meter)
	box.add_child(_wrapped("Hold V to talk; M mutes your mic. Voices get quieter with distance and stop at 12 metres. Headphones help keep game sound out of your mic.",13,MUTED))
	_setting_slider("Nearby voice volume","voice_volume",float(_read(settings,"voice_volume",0.85)),0,1,0.01,"%.0f%%",100.0)
	_setting_slider("Microphone gain","mic_gain",float(_read(settings,"mic_gain",1.0)),0.25,3.0,0.05,"%.2f×")
	_modal_body.add_child(HSeparator.new())
	update_voice_status(_voice_text,_voice_level,_voice_transmitting)

func _refresh_input_devices() -> void:
	if not is_instance_valid(_input_devices):
		return
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	var voice: Variant = _read(_game,"voice")
	if voice is Object and voice.has_method("input_devices"):
		devices = voice.input_devices()
	if not "Default" in devices:
		devices.insert(0,"Default")
	var settings: Variant = _read(_game,"settings",{})
	var selected: String = str(_read(settings,"input_device","Default"))
	_input_devices.clear()
	for device in devices:
		_input_devices.add_item(device)
		if device == selected:
			_input_devices.select(_input_devices.item_count-1)

func _setting_slider(title: String, key: String, value: float, minimum: float, maximum: float, step: float, format: String, scale: float = 1.0) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(Color("272b2d"),9,18,17))
	_modal_body.add_child(panel)
	var box := _box(12)
	panel.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := _label(title,17,CREAM,true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var current := _label(format % (value * scale),15,MINT,true)
	row.add_child(current)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 24
	slider.value_changed.connect(func(new_value: float):
		current.text = format % (new_value * scale)
		setting_changed.emit(key,new_value)
	)
	box.add_child(slider)

func show_ending() -> void:
	_open_modal("Diamond certified","You found the real diamond.")
	_modal_body.add_child(_label("Certificate of authenticity",20,MINT,true))
	_modal_body.add_child(_wrapped("The stone passed all three tests. Your discovery, collection and equipment remain saved.",17,CREAM))
	_modal_body.add_child(_button("Continue exploring",_resume,true))
	_modal_body.add_child(_button("Save game",func(): request_action.emit("save",{})))
	_modal_body.add_child(_button("Return to title",func(): request_action.emit("menu",{})))
