extends CanvasLayer
class_name RoughInterface

signal request_start(mode: String, address: String, port: int, new_save: bool)
signal request_resume
signal request_action(kind: String, args: Dictionary)
signal setting_changed(key: String, value: Variant)

const INK := Color("162b30")
const CREAM := Color("f4edda")
const MUTED := Color("a6b7ae")
const MINT := Color("b9e9ca")
const ORANGE := Color("f6ae70")
const PANEL := Color(0.055, 0.105, 0.116, 0.95)
const PURCHASES := [
	{"id":"scoop", "name":"Bigger scoop", "price":70, "benefit":"Move 9 objects at a time. Less picking. More pouring.", "tag":"01 / HAND TOOLS"},
	{"id":"trays", "name":"Sorting trays", "price":100, "benefit":"Carry 14 finds and expand your organised candidate storage.", "tag":"02 / ORGANISATION"},
	{"id":"loupe", "name":"Loupe + inspection lamp", "price":145, "benefit":"Read facet junctions, inclusions and optical clues clearly.", "tag":"03 / A CLOSER LOOK"},
	{"id":"wash", "name":"Washing station", "price":180, "benefit":"Wash away dirt. Clean recyclables sell for 60% more.", "tag":"04 / CLEAN RETURNS"},
	{"id":"sorter", "name":"Sorting machine", "price":330, "benefit":"Process 18 finds per pull. Suspicious stones go to the tray.", "tag":"05 / BIG BATCHES"},
	{"id":"vacuum", "name":"Workshop vacuum", "price":440, "benefit":"Gather loose finds over a wider area or pull a batch from the pile.", "tag":"06 / SUCK IT UP"},
	{"id":"conveyor", "name":"Conveyor belt", "price":560, "benefit":"Double machine throughput: process 36 objects per pull.", "tag":"07 / KEEP IT MOVING"},
	{"id":"scanner", "name":"Advanced scanner", "price":850, "benefit":"Check a local batch of 24 and shortlist candidates for inspection.", "tag":"08 / NARROW THE SEARCH"}
]

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
var _menu_title: Label
var _address: LineEdit
var _port: SpinBox
var _font: SystemFont
var _bold: SystemFont
var _session_text: String = "SOLO WORKSHOP"
var _last_state: Variant
var _modal_return_title: bool = false
var _modal_kind: String = ""
var _shop_signature: String = ""
var _voice_badge: Label
var _voice_meter: ProgressBar
var _voice_status: Label
var _voice_enabled: CheckButton
var _mic_muted: CheckButton
var _input_devices: OptionButton
var _voice_text: String = "Solo · voice off"
var _voice_level: float = 0.0
var _voice_transmitting: bool = false

func build(game: Node) -> void:
	_game = game
	layer = 20
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Segoe UI", "Arial", "sans-serif"])
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.35))
	theme.set_stylebox("normal", "Button", _style(Color("274349"), 9, 16, 11))
	theme.set_stylebox("hover", "Button", _style(MINT, 9, 16, 11))
	theme.set_stylebox("pressed", "Button", _style(ORANGE, 9, 16, 11))
	theme.set_stylebox("disabled", "Button", _style(Color("20383c"), 9, 16, 11))
	theme.set_stylebox("focus", "Button", _style(Color(0,0,0,0), 9, 16, 11, MINT))
	theme.set_stylebox("normal", "LineEdit", _style(Color("274349"), 7, 12, 9))
	theme.set_stylebox("focus", "LineEdit", _style(Color("274349"), 7, 12, 9, MINT))
	theme.set_color("font_color", "LineEdit", CREAM)
	theme.set_stylebox("slider", "HSlider", _style(Color("385158"), 3, 0, 2))
	theme.set_stylebox("grabber_area", "HSlider", _style(MINT, 3, 0, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _style(ORANGE, 3, 0, 2))
	_root.theme = theme
	_build_hud()
	_build_menu()
	_build_modal()
	_build_inspection()
	show_menu(false)

func _style(color: Color, radius: int = 10, horizontal: int = 20, vertical: int = 16, border: Color = Color(0,0,0,0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
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
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", _bold)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _wrapped(text: String, size: int = 16, color: Color = MUTED) -> Label:
	var label := _label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _box(spacing: int = 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	return box

func _button(text: String, callable: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 43
	button.pressed.connect(callable)
	if primary:
		button.add_theme_stylebox_override("normal", _style(MINT, 9, 16, 11))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_font_override("font", _bold)
	return button

func _panel(parent: Node, position: Vector2, size: Vector2, color: Color = PANEL) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = position
	panel.custom_minimum_size = size
	panel.add_theme_stylebox_override("panel", _style(color))
	parent.add_child(panel)
	return panel

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)
	var money_panel := _panel(_hud, Vector2(26,26), Vector2(190,68), Color(0.06,0.12,0.13,0.87))
	var money_box := _box(2)
	money_panel.add_child(money_box)
	money_box.add_child(_label("SHARED WORKSHOP FUND",11,MUTED,true))
	_money = _label("$22",27,MINT,true)
	money_box.add_child(_money)
	var net_panel := PanelContainer.new()
	net_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	net_panel.position = Vector2(-296,26)
	net_panel.custom_minimum_size = Vector2(270,44)
	net_panel.add_theme_stylebox_override("panel", _style(Color(0.06,0.12,0.13,0.85),8,14,10))
	_hud.add_child(net_panel)
	_network = _label("●  SOLO WORKSHOP",12,MINT,true)
	_network.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	net_panel.add_child(_network)
	var reticle := _label("+",22,Color(0.96,0.96,0.89,0.72))
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.position = Vector2(-7,-17)
	reticle.size = Vector2(14,28)
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(reticle)
	_prompt = _label("",17,CREAM,true)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-380,45)
	_prompt.size = Vector2(760,55)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_shadow_color",INK)
	_prompt.add_theme_constant_override("shadow_offset_x",2)
	_prompt.add_theme_constant_override("shadow_offset_y",2)
	_hud.add_child(_prompt)
	var objective_panel := PanelContainer.new()
	_objective_card = objective_panel
	objective_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	objective_panel.position = Vector2(26,-136)
	objective_panel.custom_minimum_size = Vector2(365,110)
	objective_panel.add_theme_stylebox_override("panel",_style(Color(0.06,0.12,0.13,0.86),10,18,14))
	_hud.add_child(objective_panel)
	var objective_box := _box(7)
	objective_panel.add_child(objective_box)
	objective_box.add_child(_label("A DIAMOND DOESN’T SORT ITSELF",11,ORANGE,true))
	_objective = _wrapped("Scoop a handful, check your finds, then sell the rubbish.",16,CREAM)
	_objective.custom_minimum_size.x = 329
	objective_box.add_child(_objective)
	var tool_panel := PanelContainer.new()
	_tool_card = tool_panel
	tool_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tool_panel.position = Vector2(-304,-136)
	tool_panel.custom_minimum_size = Vector2(278,110)
	tool_panel.add_theme_stylebox_override("panel",_style(Color(0.06,0.12,0.13,0.86),10,18,14))
	_hud.add_child(tool_panel)
	var tool_box := _box(3)
	tool_panel.add_child(tool_box)
	_tool = _label("SMALL SCOOP",19,CREAM,true)
	_capacity = _label("0 / 3 objects",14,MINT)
	tool_box.add_child(_tool)
	tool_box.add_child(_capacity)
	tool_box.add_child(_label("1–4 tools    TAB ledger    ESC pause",11,MUTED))
	var voice_panel := PanelContainer.new()
	voice_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	voice_panel.position = Vector2(-170,-90)
	voice_panel.custom_minimum_size = Vector2(340,64)
	voice_panel.add_theme_stylebox_override("panel",_style(Color(0.06,0.12,0.13,0.86),8,12,9))
	voice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(voice_panel)
	var voice_box := _box(5)
	voice_panel.add_child(voice_box)
	_voice_badge = _label(_voice_text,12,MUTED,true)
	_voice_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_box.add_child(_voice_badge)
	var voice_hint := _label("V · proximity voice    M · mic mute",11,MUTED)
	voice_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_box.add_child(voice_hint)
	_toast_panel = PanelContainer.new()
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.position = Vector2(-340,26)
	_toast_panel.custom_minimum_size = Vector2(680,44)
	_toast_panel.add_theme_stylebox_override("panel",_style(MINT,8,18,10))
	_toast_panel.z_index = 50
	_root.add_child(_toast_panel)
	_toast = _label("",15,INK,true)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast)
	_toast_panel.hide()

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu)
	var shade := ColorRect.new()
	shade.color = Color(0.025,0.06,0.067,0.74)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",48)
	margin.add_theme_constant_override("margin_right",48)
	margin.add_theme_constant_override("margin_top",28)
	margin.add_theme_constant_override("margin_bottom",28)
	_menu.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",44)
	margin.add_child(columns)
	var branding := _box(0)
	branding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	branding.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(branding)
	branding.add_child(_label("D / R     •     THE SORTING WORKSHOP",12,MINT,true))
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	branding.add_child(space)
	branding.add_child(_label("DIAMOND",64,CREAM,true))
	branding.add_child(_label("IN THE",35,ORANGE,true))
	branding.add_child(_label("ROUGH",82,MINT,true))
	var tagline := _wrapped("One real diamond.\nAn unreasonable amount of rubbish.",20,CREAM)
	tagline.custom_minimum_size.y = 80
	branding.add_child(tagline)
	var loop_label := _label("SCOOP   →   SORT   →   INSPECT   →   UPGRADE",12,MINT,true)
	branding.add_child(loop_label)
	var lower_space := Control.new()
	lower_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	branding.add_child(lower_space)
	branding.add_child(_wrapped("A small workshop. A deeply questionable business plan.\nFind something extraordinary in the everyday mess.",13,MUTED))
	branding.add_child(_label("NATIVE DESKTOP PROTOTYPE   /   UP TO FOUR SORTERS",10,MUTED,true))
	var menu_panel := PanelContainer.new()
	menu_panel.custom_minimum_size.x = 370
	menu_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu_panel.add_theme_stylebox_override("panel",_style(PANEL,16,24,20,Color("385158")))
	columns.add_child(menu_panel)
	var box := _box(7)
	menu_panel.add_child(box)
	_menu_title = _label("CLOCK IN",25,CREAM,true)
	box.add_child(_menu_title)
	box.add_child(_label("Every good find begins with a handful.",13,MUTED))
	_resume_button = _button("Resume sorting   →",_resume,true)
	box.add_child(_resume_button)
	box.add_child(_button("New solo workshop   →",func(): request_start.emit("solo","",_port_number(),true),true))
	box.add_child(_button("Continue saved workshop",func(): request_start.emit("solo","",_port_number(),false)))
	box.add_child(_button("Host shared workshop",func(): request_start.emit("host","",_port_number(),false)))
	box.add_child(_label("JOIN A FRIEND’S WORKSHOP",10,ORANGE,true))
	var network_row := HBoxContainer.new()
	network_row.add_theme_constant_override("separation",8)
	box.add_child(network_row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host IP address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.custom_minimum_size.x = 190
	network_row.add_child(_address)
	_port = SpinBox.new()
	_port.min_value = 1
	_port.max_value = 65535
	_port.value = 24680
	_port.custom_minimum_size.x = 105
	network_row.add_child(_port)
	box.add_child(_button("Join workshop   →",func(): request_start.emit("join",_address.text.strip_edges(),_port_number(),false)))
	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation",8)
	box.add_child(utility_row)
	var settings_button := _button("Settings",_show_settings)
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utility_row.add_child(settings_button)
	var controls_button := _button("Controls",_show_controls)
	controls_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	utility_row.add_child(controls_button)
	_save_button = _button("Save workshop",func(): request_action.emit("save",{}))
	box.add_child(_save_button)
	_return_button = _button("Return to the title",func(): request_action.emit("menu",{}))
	box.add_child(_return_button)
	var quit_button := _button("Leave for the day",func(): get_tree().quit())
	quit_button.add_theme_color_override("font_color",MUTED)
	box.add_child(quit_button)
	box.add_child(_label("Shared money. Shared machines. Your own silly hat.",10,MUTED))

func _port_number() -> int:
	return int(_port.value) if is_instance_valid(_port) else 24680

func _build_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_modal)
	var shade := ColorRect.new()
	shade.color = Color(0.025,0.06,0.067,0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top",35)
	margin.add_theme_constant_override("margin_bottom",35)
	margin.add_theme_constant_override("margin_left",40)
	margin.add_theme_constant_override("margin_right",40)
	_modal.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760,580)
	panel.add_theme_stylebox_override("panel",_style(PANEL,14,26,20,Color("385158")))
	center.add_child(panel)
	var box := _box(12)
	panel.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	_modal_title = _label("WORKSHOP LEDGER",27,CREAM,true)
	_modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_modal_title)
	heading.add_child(_button("Close  ×",_close_modal))
	_modal_subtitle = _wrapped("",14,MUTED)
	box.add_child(_modal_subtitle)
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator",_style(Color("385158"),0,0,0))
	box.add_child(line)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(708,407)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_modal_body = _box(10)
	_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_modal_body)
	_modal.hide()

func _build_inspection() -> void:
	_inspection = Control.new()
	_inspection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_inspection)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.position = Vector2(-444,-278)
	panel.custom_minimum_size = Vector2(416,540)
	panel.add_theme_stylebox_override("panel",_style(PANEL,14,22,20,Color("385158")))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspection.add_child(panel)
	var box := _box(13)
	panel.add_child(box)
	_inspection_tag = _label("ON THE INSPECTION TRAY",11,ORANGE,true)
	box.add_child(_inspection_tag)
	_inspection_title = _wrapped("Uncertified candidate",26,CREAM)
	_inspection_title.add_theme_font_override("font",_bold)
	box.add_child(_inspection_title)
	box.add_child(_wrapped("Move the mouse to turn your find. Ctrl + mouse wheel brings it closer. Follow the evidence.",13,MUTED))
	var separator := HSeparator.new()
	box.add_child(separator)
	_inspection_body = _box(13)
	box.add_child(_inspection_body)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	box.add_child(_label("RMB  finish inspecting     Q  drop carefully",12,MINT,true))
	_inspection.hide()

func show_menu(in_game: bool = false) -> void:
	menu_visible = true
	inspecting = false
	_menu.show()
	_modal.hide()
	_inspection.hide()
	_hud.hide()
	_resume_button.visible = in_game
	_save_button.visible = in_game
	_return_button.visible = in_game
	_menu_title.text = "ON A TEA BREAK" if in_game else "CLOCK IN"

func hide_menu() -> void:
	menu_visible = false
	_menu.hide()
	_modal.hide()
	_hud.show()
	_tool_card.show()
	_objective_card.show()
	_modal_kind = ""

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

func _read(state: Variant, key: String, fallback: Variant = null) -> Variant:
	if state is Dictionary:
		return state.get(key,fallback)
	if state is Object:
		for property in state.get_property_list():
			if str(property.name) == key:
				var value: Variant = state.get(key)
				return value if value != null else fallback
	return fallback

func update_hud(state: Variant, tool_name: String, capacity: int, prompt: String, objective: String) -> void:
	_last_state = state
	_money.text = "$%s" % str(_read(state,"money",0))
	_tool.text = tool_name.to_upper()
	var held_count: int = 0
	if state is Object and state.has_method("held_ids"):
		held_count = state.held_ids().size()
	else:
		var held: Variant = _read(state,"held",[])
		if held is Array:
			held_count = held.size()
	_capacity.text = "%d / %d objects" % [held_count,capacity]
	_prompt.text = prompt
	_objective.text = objective
	if _modal_kind == "shop" and _modal.visible:
		var signature: String = str(_read(state,"money",0)) + str(_read(state,"upgrades",[]))
		if signature != _shop_signature:
			show_shop(state)

func update_network(text: String) -> void:
	_session_text = text
	_network.text = "●  " + text.to_upper()

func update_voice_status(text: String, level: float, transmitting: bool) -> void:
	_voice_text = text
	_voice_level = clampf(level,0.0,1.0)
	_voice_transmitting = transmitting
	var accent: Color = MINT if transmitting else MUTED
	if is_instance_valid(_voice_badge):
		_voice_badge.text = ("●  " if transmitting else "") + text
		_voice_badge.add_theme_color_override("font_color",accent)
	if _modal_kind != "settings" or not _modal.visible:
		return
	if is_instance_valid(_voice_status):
		_voice_status.text = text
		_voice_status.add_theme_color_override("font_color",accent)
	if is_instance_valid(_voice_meter):
		_voice_meter.value = _voice_level
		_voice_meter.add_theme_stylebox_override("fill",_style(accent,3,0,0))
	var settings: Variant = _read(_game,"settings",{})
	if is_instance_valid(_voice_enabled):
		_voice_enabled.set_pressed_no_signal(bool(_read(settings,"voice_enabled",true)))
	if is_instance_valid(_mic_muted):
		_mic_muted.set_pressed_no_signal(bool(_read(settings,"mic_muted",false)))

func toast(text: String) -> void:
	_toast.text = text
	_toast_clock = clampf(2.4 + text.length() * 0.025,3.0,6.0)
	_toast_panel.modulate.a = 1.0
	_toast_panel.show()

func _process(delta: float) -> void:
	if _toast_clock > 0.0:
		_toast_clock -= delta
		_toast_panel.modulate.a = minf(1.0,maxf(0.0,_toast_clock * 2.5))
		if _toast_clock <= 0.0:
			_toast_panel.hide()

func show_inspection(gem: Dictionary, has_loupe: bool) -> void:
	inspecting = true
	menu_visible = false
	_menu.hide()
	_modal.hide()
	_hud.show()
	_tool_card.hide()
	_objective_card.hide()
	_inspection.show()
	_clear(_inspection_body)
	var kind: String = str(gem.get("kind","glass"))
	var candidate: bool = kind in ["diamond","suspect","moissanite"]
	_inspection_title.text = "Uncertified candidate" if candidate else str(gem.get("name","Interesting find"))
	_inspection_tag.text = "LOUPE + LAMP  /  ACTIVE" if has_loupe else "NAKED EYE  /  BASIC INSPECTION"
	var clues: Array[String] = _clues(gem,has_loupe)
	for index in range(clues.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",12)
		row.add_child(_label("0%d" % (index+1),12,MINT,true))
		row.add_child(_wrapped(clues[index],15,CREAM))
		_inspection_body.add_child(row)
	if not has_loupe and kind in ["diamond","suspect","glass","crystal","moissanite"]:
		_inspection_body.add_child(_wrapped("A loupe and lamp reveal finer facet and inclusion clues. Available at the workshop shop.",12,ORANGE))
	if candidate:
		_inspection_body.add_child(_wrapped("Promising? Take it to the certification bench. Suspicious candidates are protected from accidental sale.",13,MINT))
	else:
		_inspection_body.add_child(_label("Estimated clean return: $%s" % str(gem.get("value",0)),14,MINT,true))
		if kind in ["collectible","oddity"]:
			_inspection_body.add_child(_wrapped("[C]  Keep this find on the display shelf.",14,ORANGE))

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
			result = ["A satisfying metallic weight in your hand.","Scratched plating. Valuable to the recycling bench."]
		"cash":
			result = ["Someone’s forgotten emergency fund.","The best optical test: it looks exactly like money."]
		"collectible":
			result = ["An elaborate imitation with real personality.","Keep it in the collection, or sell it for a useful payout."]
		"oddity", "junk":
			result = ["Questionable provenance. Impeccable comic timing.","Not everything in a gem pile is a gem."]
		_:
			result = [str(gem.get("clue","Turn it under the light and watch the surface.")),"Look carefully before deciding what to keep."]
	return result

func hide_inspection() -> void:
	inspecting = false
	_inspection.hide()
	_tool_card.show()
	_objective_card.show()

func show_shop(state: Variant) -> void:
	_last_state = state
	var money: int = int(_read(state,"money",0))
	var upgrades: Variant = _read(state,"upgrades",[])
	_open_modal("THE WORKSHOP SHOP", "$%d shared funds  •  Purchases improve the workshop for everyone." % money)
	_modal_kind = "shop"
	_shop_signature = str(money) + str(upgrades)
	for item in PURCHASES:
		var owned: bool = item.id in upgrades
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",_style(Color("20383c"),9,15,13))
		_modal_body.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",18)
		card.add_child(row)
		var details := _box(4)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		details.add_child(_label(str(item.tag),10,MINT,true))
		details.add_child(_label(str(item.name),19,CREAM,true))
		details.add_child(_wrapped(str(item.benefit),13,MUTED))
		var purchase_id: String = str(item.id)
		var button := _button("INSTALLED  ✓" if owned else "$%d  BUY" % int(item.price),func(): request_action.emit("buy",{"upgrade":purchase_id}),not owned and money >= int(item.price))
		button.disabled = owned or money < int(item.price)
		button.custom_minimum_size.x = 150
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
	_modal_body.add_child(_wrapped("Safety is part of the business plan: machines route promising stones to the inspection tray. The scanner shortlists candidates; certification earns the reveal.",13,ORANGE))

func show_collection(state: Variant) -> void:
	_last_state = state
	_open_modal("THE WORKSHOP LEDGER","Three ambitions: a better tool, a stranger collection, and one extraordinary stone.")
	var upgrades: Variant = _read(state,"upgrades",[])
	var money: int = int(_read(state,"money",0))
	var next: Dictionary = {}
	for item in PURCHASES:
		if not item.id in upgrades:
			next = item
			break
	_add_ledger_card("01 / YOUR NEXT UPGRADE",str(next.get("name","Workshop fully equipped")),"$%d of $%d saved. %s" % [money,int(next.get("price",0)),str(next.get("benefit","Enjoy your ridiculous sorting operation."))] if not next.is_empty() else "Every machine is ready. The rest is in your hands.",MINT)
	var collection: Variant = _read(state,"collection",_read(state,"collections",[]))
	var collection_count: int = collection.size() if collection is Array or collection is Dictionary else int(collection)
	_add_ledger_card("02 / CABINET OF CURIOSITIES","%d unusual finds collected" % collection_count,"Bring interesting imitations and oddities home. A respectable collection is entirely optional.",ORANGE)
	var certified: bool = bool(_read(state,"certified",false))
	_add_ledger_card("03 / THE LONG SHOT","Genuine diamond certified" if certified else "One real diamond. Still out there.","You earned it. The certificate is official." if certified else "Fast-clearing breath, crisp facets, no trapped bubbles, and a point lost in haze. Compare the evidence, then use the certification bench.",MINT)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",10)
	_modal_body.add_child(actions)
	for entry in [{"label":"Save progress","action":"save"},{"label":"Recover lost finds","action":"recover"},{"label":"Unstuck / reset","action":"unstuck"}]:
		var action: String = str(entry.action)
		var button := _button(str(entry.label),func(): request_action.emit(action,{}))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	_modal_body.add_child(_wrapped("Progress, shared equipment, finds and the diamond’s location are saved together. Lost-item recovery returns misplaced finds to the workshop.",12,MUTED))

func _add_ledger_card(tag: String, title: String, description: String, accent: Color) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(Color("20383c"),9,16,15))
	_modal_body.add_child(panel)
	var box := _box(6)
	panel.add_child(box)
	box.add_child(_label(tag,10,accent,true))
	box.add_child(_label(title,21,CREAM,true))
	box.add_child(_wrapped(description,14,MUTED))

func _show_controls() -> void:
	_open_modal("A SORTER’S FIELD GUIDE","The loop is simple: scoop → sort → inspect → sell → upgrade.")
	var rows := [
		["W A S D  /  MOUSE","Move and look around your workshop."],
		["E","Use a station, pick up a find, or advance certification."],
		["LEFT MOUSE","Scoop a batch or use your equipped tool."],
		["RIGHT MOUSE","Inspect a find. Move the mouse to rotate it."],
		["MOUSE WHEEL","Cycle through your carried candidates."],
		["CTRL + MOUSE WHEEL","Zoom closer during inspection."],
		["Q","Drop your selected object carefully into the world."],
		["1  /  2  /  3  /  4","Scoop / hands / purchased vacuum / purchased scanner."],
		["TAB  /  ESC","Workshop ledger / pause menu."],
		["V  /  M","Hold V to talk to nearby sorters. M mutes your microphone."],
		["C","Keep the selected collectible or oddity on display."],
		["R","Wrap a promising stone as a gift for a friend."],
		["T","Reverse a conveyor near a friend for a harmless wobble."],
		["F  /  G  /  H","Questionable label / washable polishing foam / silly hat."]
	]
	for entry in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",22)
		var key := _label(str(entry[0]),12,MINT,true)
		key.custom_minimum_size.x = 190
		row.add_child(key)
		row.add_child(_wrapped(str(entry[1]),15,CREAM))
		_modal_body.add_child(row)
	_modal_body.add_child(HSeparator.new())
	_modal_body.add_child(_wrapped("First shift: scoop a handful from the pile. Sell recyclable finds for workshop money. The bigger scoop is your first affordable upgrade. Keep suspicious candidates and take them to certification when the evidence agrees.",15,ORANGE))

func _show_settings() -> void:
	_open_modal("MAKE YOURSELF COMFORTABLE","Camera, sound and display preferences are saved locally.")
	_modal_kind = "settings"
	var settings: Variant = _read(_game,"settings",{})
	_build_voice_settings(settings)
	_setting_slider("Mouse sensitivity","sensitivity",float(_read(settings,"sensitivity",0.0025)),0.0005,0.008,0.0001,"%.4f")
	_setting_slider("Field of view","fov",float(_read(settings,"fov",78)),60,110,1,"%.0f°")
	_setting_slider("Master audio","volume",float(_read(settings,"volume",0.65)),0,1,0.01,"%.0f%%",100.0)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen display"
	fullscreen.button_pressed = bool(_read(settings,"fullscreen",false))
	fullscreen.toggled.connect(func(value: bool): setting_changed.emit("fullscreen",value))
	_modal_body.add_child(fullscreen)
	_modal_body.add_child(_wrapped("A wider view helps keep your stations in sight. Lower sensitivity makes precise inspection easier.",14,MUTED))
	if _resume_button.visible:
		_modal_body.add_child(_button("Return to sorting   →",_resume,true))
	else:
		_modal_body.add_child(_button("Back to the title   →",func(): show_menu(false),true))

func _build_voice_settings(settings: Variant) -> void:
	_modal_body.add_child(_label("PROXIMITY VOICE",11,ORANGE,true))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(Color("20383c"),9,18,14))
	_modal_body.add_child(panel)
	var box := _box(10)
	panel.add_child(box)
	var toggles := HBoxContainer.new()
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
	box.add_child(_label("MICROPHONE",10,MINT,true))
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
	var meter_row := HBoxContainer.new()
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
	_voice_meter.add_theme_stylebox_override("background",_style(Color("385158"),3,0,0))
	_voice_meter.add_theme_stylebox_override("fill",_style(MINT,3,0,0))
	meter_row.add_child(_voice_meter)
	box.add_child(_wrapped("Hold V to talk; M mutes your mic. Voices get quieter with distance and stop at 12 metres. Headphones help keep your workshop sound out of your mic.",13,MUTED))
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
	panel.add_theme_stylebox_override("panel",_style(Color("20383c"),9,18,17))
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
	_open_modal("DIAMOND. FOUND.","The rubbish was real. So was the diamond.")
	_modal_body.add_child(_label("✦",68,MINT,true))
	_modal_body.add_child(_label("CERTIFICATE OF AUTHENTICITY",13,ORANGE,true))
	_modal_body.add_child(_wrapped("One genuine diamond, recovered by an increasingly unreasonable sorting operation.",27,CREAM))
	_modal_body.add_child(_wrapped("You followed the clues, built the workshop, and found the extraordinary thing hiding in an ordinary mess. Your shared progress and discoveries remain saved.",16,MUTED))
	_modal_body.add_child(_button("Keep sorting   →",_resume,true))
	_modal_body.add_child(_button("Save the good news",func(): request_action.emit("save",{})))
	_modal_body.add_child(_button("Back to the title",func(): request_action.emit("menu",{})))
