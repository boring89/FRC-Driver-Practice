class_name SettingsPanel
extends Control
## Settings screen: a row of tabs over one page at a time. Graphics options
## take effect immediately; the Keybinds page lists every action with its
## binding for the keyboard or the controller. Everything is saved on Back.

signal closed

const _WAITING := "Press..."
const _PAGES := ["Graphics", "Keybinds"]

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _quality := OptionButton.new()
var _fullscreen := CheckBox.new()
var _vsync := CheckBox.new()
var _fps_limit := OptionButton.new()
var _device_buttons: Array[Button] = []
# Action id -> the button showing its binding for the device being edited.
var _bind_buttons := {}
var _editing_pad := false
# Action whose binding is waiting for a key or button press.
var _capture_action := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Dim whatever is behind the settings.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	var back := MenuStyle.button("←  Back", 26, true)
	back.pressed.connect(_on_back)
	tabs.add_child(back)
	for i in _PAGES.size():
		var tab := MenuStyle.button(_PAGES[i], 26)
		tab.custom_minimum_size = Vector2(260.0, 0.0)
		tab.pressed.connect(_show_page.bind(i))
		tabs.add_child(tab)
		_tab_buttons.append(tab)

	var body := PanelContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_stylebox_override("panel", MenuStyle.box(MenuStyle.PANEL, 8, 20))
	column.add_child(body)
	_pages = [_build_graphics(), _build_keybinds()]
	for page in _pages:
		body.add_child(page)
	_show_page(0)


func open() -> void:
	visible = true
	_quality.select(Settings.quality)
	_fps_limit.select(maxi(0, Settings.FPS_LIMITS.find(Settings.fps_limit)))
	_fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_vsync.set_pressed_no_signal(Settings.vsync)
	_refresh_bindings()


func _build_graphics() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	for quality_name: String in Settings.QUALITY_NAMES:
		_quality.add_item(quality_name)
	page.add_child(_row("Quality", _quality))
	_fullscreen.text = "Fullscreen"
	page.add_child(_fullscreen)
	_vsync.text = "V-Sync"
	page.add_child(_vsync)
	for limit: int in Settings.FPS_LIMITS:
		_fps_limit.add_item("Unlimited" if limit == 0 else "%d FPS" % limit)
	page.add_child(_row("Frame rate limit", _fps_limit))
	var note := Label.new()
	note.text = "Low: no shadows or anti-aliasing, 75% render scale.\nMedium: shadows, 2x MSAA.\nHigh: sharper shadows, 4x MSAA."
	note.modulate = Color(1.0, 1.0, 1.0, 0.6)
	page.add_child(note)
	for control: Control in [_quality, _fullscreen, _vsync, _fps_limit]:
		control.add_theme_font_size_override("font_size", 20)
	_quality.item_selected.connect(_on_graphics_changed.unbind(1))
	_fps_limit.item_selected.connect(_on_graphics_changed.unbind(1))
	_fullscreen.toggled.connect(_on_graphics_changed.unbind(1))
	_vsync.toggled.connect(_on_graphics_changed.unbind(1))
	return page


func _build_keybinds() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var devices := HBoxContainer.new()
	devices.add_theme_constant_override("separation", 8)
	page.add_child(devices)
	for i in 2:
		var device := MenuStyle.button(["Keyboard", "Controller"][i], 22)
		device.custom_minimum_size = Vector2(230.0, 0.0)
		device.pressed.connect(_show_device.bind(i == 1))
		devices.add_child(device)
		_device_buttons.append(device)

	# Two blocks of [action, binding, reset] side by side, filled top to bottom.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var blocks := HBoxContainer.new()
	blocks.add_theme_constant_override("separation", 40)
	scroll.add_child(blocks)
	var per_block := ceili(Settings.ACTIONS.size() / 2.0)
	for start in [0, per_block]:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 6)
		blocks.add_child(grid)
		for action: Array in Settings.ACTIONS.slice(start, start + per_block):
			var id: String = action[0]
			var plate := MenuStyle.plate(action[1], 16)
			plate.custom_minimum_size = Vector2(250.0, 0.0)
			grid.add_child(plate)
			var bind := MenuStyle.button("", 16, true)
			bind.custom_minimum_size = Vector2(150.0, 0.0)
			bind.pressed.connect(_start_capture.bind(id))
			grid.add_child(bind)
			_bind_buttons[id] = bind
			var reset := MenuStyle.button("Reset", 16)
			reset.pressed.connect(_on_reset_one.bind(id))
			grid.add_child(reset)

	var footer := HBoxContainer.new()
	page.add_child(footer)
	var hint := Label.new()
	hint.text = "Click a binding, then press the new key or button. Esc cancels, Delete clears. Driving on a controller is always on the sticks."
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var reset_all := MenuStyle.button("Reset all", 22, true)
	reset_all.pressed.connect(_on_reset_all)
	footer.add_child(reset_all)
	return page


func _show_page(index: int) -> void:
	_capture_action = ""
	for i in _pages.size():
		_pages[i].visible = i == index
		MenuStyle.paint(_tab_buttons[i], i == index)
	_show_device(_editing_pad)


func _show_device(pad: bool) -> void:
	_capture_action = ""
	_editing_pad = pad
	MenuStyle.paint(_device_buttons[0], not pad)
	MenuStyle.paint(_device_buttons[1], pad)
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _capture_action == "":
		return
	var key := event as InputEventKey
	var button := event as InputEventJoypadButton
	var motion := event as InputEventJoypadMotion
	if key and key.pressed:
		if key.physical_keycode == KEY_DELETE and _editing_pad:
			Settings.pads[_capture_action] = {}
		elif key.physical_keycode == KEY_DELETE:
			Settings.keys[_capture_action] = 0
		elif key.physical_keycode != KEY_ESCAPE and not _editing_pad:
			Settings.keys[_capture_action] = key.physical_keycode
		elif key.physical_keycode != KEY_ESCAPE:
			return
	elif button and button.pressed and _editing_pad:
		Settings.pads[_capture_action] = {"button": button.button_index}
	elif motion and _editing_pad and absf(motion.axis_value) > 0.6 \
			and motion.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		Settings.pads[_capture_action] = {"axis": motion.axis}
	else:
		return
	_capture_action = ""
	get_viewport().set_input_as_handled()
	Settings.apply(get_tree())
	_refresh_bindings()


func _start_capture(id: String) -> void:
	_refresh_bindings()
	_capture_action = id
	(_bind_buttons[id] as Button).text = _WAITING


func _refresh_bindings() -> void:
	for id: String in _bind_buttons:
		(_bind_buttons[id] as Button).text = Settings.pad_name(id) if _editing_pad else Settings.key_name(id)


func _on_graphics_changed() -> void:
	Settings.quality = _quality.selected
	Settings.fps_limit = Settings.FPS_LIMITS[_fps_limit.selected]
	Settings.fullscreen = _fullscreen.button_pressed
	Settings.vsync = _vsync.button_pressed
	Settings.apply(get_tree())


func _on_reset_one(id: String) -> void:
	_capture_action = ""
	Settings.reset_binding(id, _editing_pad)
	Settings.apply(get_tree())
	_refresh_bindings()


func _on_reset_all() -> void:
	_capture_action = ""
	Settings.reset_bindings()
	Settings.apply(get_tree())
	_refresh_bindings()


func _on_back() -> void:
	_capture_action = ""
	Settings.save_file()
	visible = false
	closed.emit()


func _row(text: String, control: Control) -> HBoxContainer:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(220.0, 0.0)
	label.add_theme_font_size_override("font_size", 20)
	var row := HBoxContainer.new()
	row.add_child(label)
	row.add_child(control)
	return row
