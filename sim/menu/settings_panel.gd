class_name SettingsPanel
extends PanelContainer
## Settings screen: graphics options and the key and gamepad binding of each
## action. Changes take effect immediately and are saved when it closes.

signal closed

const _WAITING := "Press..."

var _tabs := TabContainer.new()
var _quality := OptionButton.new()
var _fullscreen := CheckBox.new()
var _vsync := CheckBox.new()
var _fps_limit := OptionButton.new()
# Action id -> its key button and its gamepad button.
var _key_buttons := {}
var _pad_buttons := {}
# The binding being changed: action id, and whether it is the gamepad one.
var _capture_action := ""
var _capture_pad := false


func _ready() -> void:
	custom_minimum_size = Vector2(620.0, 560.0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)

	var graphics := VBoxContainer.new()
	graphics.name = "Graphics"
	graphics.add_theme_constant_override("separation", 10)
	_tabs.add_child(graphics)
	for quality_name: String in Settings.QUALITY_NAMES:
		_quality.add_item(quality_name)
	graphics.add_child(_row("Quality", _quality))
	_fullscreen.text = "Fullscreen"
	graphics.add_child(_fullscreen)
	_vsync.text = "V-Sync"
	graphics.add_child(_vsync)
	for limit: int in Settings.FPS_LIMITS:
		_fps_limit.add_item("Unlimited" if limit == 0 else "%d FPS" % limit)
	graphics.add_child(_row("Frame rate limit", _fps_limit))
	var note := Label.new()
	note.text = "Low: no shadows or anti-aliasing, 75% render scale.\nMedium: shadows, 2x MSAA.\nHigh: sharper shadows, 4x MSAA."
	note.modulate = Color(1.0, 1.0, 1.0, 0.6)
	graphics.add_child(note)
	_quality.item_selected.connect(_on_graphics_changed.unbind(1))
	_fps_limit.item_selected.connect(_on_graphics_changed.unbind(1))
	_fullscreen.toggled.connect(_on_graphics_changed.unbind(1))
	_vsync.toggled.connect(_on_graphics_changed.unbind(1))

	var controls := VBoxContainer.new()
	controls.name = "Controls"
	_tabs.add_child(controls)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	scroll.add_child(grid)
	for heading: String in ["Action", "Keyboard", "Gamepad"]:
		var label := Label.new()
		label.text = heading
		label.modulate = Color(1.0, 1.0, 1.0, 0.6)
		grid.add_child(label)
	for action: Array in Settings.ACTIONS:
		var id: String = action[0]
		var label := Label.new()
		label.text = action[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		for is_pad: bool in [false, true]:
			var button := Button.new()
			button.custom_minimum_size = Vector2(130.0, 0.0)
			button.pressed.connect(_start_capture.bind(id, is_pad))
			grid.add_child(button)
			(_pad_buttons if is_pad else _key_buttons)[id] = button
	var hint := Label.new()
	hint.text = "Click a binding, then press the new key or button. Esc cancels, Delete clears.\nDriving is always on the sticks; mechanism presets use the number keys."
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	controls.add_child(hint)
	var defaults := Button.new()
	defaults.text = "Reset controls to defaults"
	defaults.pressed.connect(_on_reset_bindings)
	controls.add_child(defaults)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 40.0)
	back.pressed.connect(_on_back)
	column.add_child(back)


func open() -> void:
	visible = true
	_quality.select(Settings.quality)
	_fps_limit.select(maxi(0, Settings.FPS_LIMITS.find(Settings.fps_limit)))
	_fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_vsync.set_pressed_no_signal(Settings.vsync)
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _capture_action == "":
		return
	var key := event as InputEventKey
	var button := event as InputEventJoypadButton
	var motion := event as InputEventJoypadMotion
	if key and key.pressed:
		if key.physical_keycode == KEY_DELETE:
			(Settings.pads if _capture_pad else Settings.keys)[_capture_action] = {} if _capture_pad else 0
		elif key.physical_keycode != KEY_ESCAPE and not _capture_pad:
			Settings.keys[_capture_action] = key.physical_keycode
		elif key.physical_keycode != KEY_ESCAPE:
			return
	elif button and button.pressed and _capture_pad:
		Settings.pads[_capture_action] = {"button": button.button_index}
	elif motion and _capture_pad and absf(motion.axis_value) > 0.6 \
			and motion.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		Settings.pads[_capture_action] = {"axis": motion.axis}
	else:
		return
	_capture_action = ""
	get_viewport().set_input_as_handled()
	Settings.apply(get_tree())
	_refresh_bindings()


func _start_capture(id: String, is_pad: bool) -> void:
	_capture_action = id
	_capture_pad = is_pad
	_refresh_bindings()
	((_pad_buttons if is_pad else _key_buttons)[id] as Button).text = _WAITING


func _refresh_bindings() -> void:
	for action: Array in Settings.ACTIONS:
		(_key_buttons[action[0]] as Button).text = Settings.key_name(action[0])
		(_pad_buttons[action[0]] as Button).text = Settings.pad_name(action[0])


func _on_graphics_changed() -> void:
	Settings.quality = _quality.selected
	Settings.fps_limit = Settings.FPS_LIMITS[_fps_limit.selected]
	Settings.fullscreen = _fullscreen.button_pressed
	Settings.vsync = _vsync.button_pressed
	Settings.apply(get_tree())


func _on_reset_bindings() -> void:
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
	label.custom_minimum_size = Vector2(160.0, 0.0)
	var row := HBoxContainer.new()
	row.add_child(label)
	row.add_child(control)
	return row
