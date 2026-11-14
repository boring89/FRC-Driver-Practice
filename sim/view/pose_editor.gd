class_name PoseEditor
extends CanvasLayer
## Panel for posing the robot's mechanisms by hand and saving the result as a
## preset. The pose editor action (Tab) opens and closes it; while open the
## joints follow the sliders
## directly, without the usual retract-swing-extend sequencing.

var robot: SwerveRobot
var camera: CameraRig

var _panel := PanelContainer.new()
var _preset_picker := OptionButton.new()
var _name_edit := LineEdit.new()
var _status := Label.new()
# MechanismJoint -> the slider that poses it, in degrees or metres.
var _sliders := {}


func _ready() -> void:
	visible = false
	_panel.custom_minimum_size = Vector2(400.0, 0.0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Pose editor"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	var superstructure := robot.superstructure
	if superstructure == null or superstructure.joints.is_empty():
		_status.text = "This robot has no mechanisms."
		column.add_child(_status)
		return

	column.add_child(_row("Load preset", _preset_picker))
	_preset_picker.item_selected.connect(_on_preset_picked)

	for joint in superstructure.joints:
		var unit := 1.0 if joint.prismatic else 180.0 / PI
		var slider := HSlider.new()
		slider.min_value = joint.min_position * unit
		slider.max_value = joint.max_position * unit
		slider.step = 0.005 if joint.prismatic else 0.5
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(170.0, 0.0)
		var box := SpinBox.new()
		box.suffix = "m" if joint.prismatic else "°"
		box.custom_minimum_size = Vector2(110.0, 0.0)
		# Sharing keeps the slider and the number box on one value.
		slider.share(box)
		slider.value_changed.connect(_on_slider_moved.bind(joint))
		var controls := HBoxContainer.new()
		controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.add_child(slider)
		controls.add_child(box)
		column.add_child(_row(joint.name, controls))
		_sliders[joint] = slider

	_name_edit.placeholder_text = "preset name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_row("Save as", _name_edit))
	var buttons := HBoxContainer.new()
	var save := Button.new()
	save.text = "Save preset"
	save.pressed.connect(_on_save)
	buttons.add_child(save)
	var copy := Button.new()
	copy.text = "Copy all presets"
	copy.pressed.connect(_on_copy)
	buttons.add_child(copy)
	column.add_child(buttons)

	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var hint := Label.new()
	hint.text = "Right-drag: orbit    Wheel: zoom    %s: close" % Settings.key_name("pose_editor")
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(hint)


# Handled ahead of the GUI, which would otherwise use Tab to move focus
# between the panel's own controls.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.physical_keycode != KEY_TAB and get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.is_action_pressed("pose_editor"):
		_set_open(not visible)
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	if not visible or _sliders.is_empty():
		return
	# Presets picked with the driver's buttons move the sliders too.
	if robot.superstructure.preset_name != "":
		_sync_sliders()


func _set_open(open: bool) -> void:
	visible = open
	var superstructure := robot.superstructure
	if superstructure == null or _sliders.is_empty():
		return
	superstructure.sequencing = not open
	if not open:
		get_viewport().gui_release_focus()
		return
	camera.mode = CameraRig.Mode.ORBIT
	_fill_preset_picker()
	_sync_sliders()
	_status.text = ""


func _fill_preset_picker() -> void:
	_preset_picker.clear()
	var current := -1
	for preset: Dictionary in robot.superstructure.presets:
		if preset["name"] == robot.superstructure.preset_name:
			current = _preset_picker.item_count
		_preset_picker.add_item(preset["name"])
	_preset_picker.select(current)


func _sync_sliders() -> void:
	for joint: MechanismJoint in _sliders:
		var unit := 1.0 if joint.prismatic else 180.0 / PI
		var slider: HSlider = _sliders[joint]
		slider.set_value_no_signal(robot.superstructure.requested(joint) * unit)


func _on_preset_picked(index: int) -> void:
	var preset: Dictionary = robot.superstructure.presets[index]
	robot.superstructure.go_to(preset)
	_name_edit.text = preset["name"]
	_sync_sliders()


func _on_slider_moved(value: float, joint: MechanismJoint) -> void:
	var unit := 1.0 if joint.prismatic else PI / 180.0
	robot.superstructure.set_manual(joint, value * unit)


func _on_save() -> void:
	var preset_name := _name_edit.text.strip_edges()
	if preset_name == "":
		_status.text = "Type a preset name first."
		return
	robot.superstructure.save_preset(preset_name)
	_fill_preset_picker()
	_status.text = "Saved \"%s\"." % preset_name


func _on_copy() -> void:
	DisplayServer.clipboard_set(JSON.stringify(robot.superstructure.presets, "  ", false))
	_status.text = "Copied %d presets to the clipboard." % robot.superstructure.presets.size()


func _row(text: String, control: Control) -> HBoxContainer:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(90.0, 0.0)
	var row := HBoxContainer.new()
	row.add_child(label)
	row.add_child(control)
	return row
