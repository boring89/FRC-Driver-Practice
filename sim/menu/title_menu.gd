extends Control
## Title screen: pick the season and the robot to practise with, open the
## settings, or quit.

const PRACTICE_SCENE := "res://sim/main.tscn"
const FIELDS_DIR := "res://data/fields"
const ROBOTS_DIR := "res://data/robots"

var _year_picker := OptionButton.new()
var _robot_picker := OptionButton.new()
var _menu := VBoxContainer.new()
var _settings := SettingsPanel.new()
# Config path of each entry in the robot picker.
var _robot_paths: Array[String] = []


func _ready() -> void:
	Settings.load_file()
	Settings.apply(get_tree())

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.07, 0.08, 0.1)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	_menu.custom_minimum_size = Vector2(420.0, 0.0)
	_menu.add_theme_constant_override("separation", 14)
	centre.add_child(_menu)
	var title := Label.new()
	title.text = "FRC Driver Practice"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	_menu.add_child(title)
	_menu.add_child(HSeparator.new())
	_menu.add_child(_row("Season", _year_picker))
	_menu.add_child(_row("Robot", _robot_picker))
	_menu.add_child(_button("Start practice", _on_start))
	_menu.add_child(_button("Settings", _on_settings))
	_menu.add_child(_button("Quit", get_tree().quit))

	_settings.visible = false
	_settings.closed.connect(_on_settings_closed)
	centre.add_child(_settings)

	for file in DirAccess.get_files_at(FIELDS_DIR):
		if file.get_extension() == "json":
			var field: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIELDS_DIR.path_join(file)))
			_year_picker.add_item(field["name"], int(file.get_basename()))
	_year_picker.item_selected.connect(_fill_robots.unbind(1))
	_year_picker.select(maxi(0, _year_picker.get_item_index(Session.year)))
	_fill_robots()


## Lists the robots built for the selected season, plus any that fit every season.
func _fill_robots() -> void:
	var year := _year_picker.get_selected_id()
	_robot_picker.clear()
	_robot_paths.clear()
	for file in DirAccess.get_files_at(ROBOTS_DIR):
		if file.get_extension() != "json" or file.ends_with("_presets.json"):
			continue
		var path := ROBOTS_DIR.path_join(file)
		var robot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		if robot.get("year", year) != year:
			continue
		_robot_picker.add_item(robot["name"])
		_robot_paths.append(path)
		if path == Session.robot_config:
			_robot_picker.select(_robot_picker.item_count - 1)


func _on_start() -> void:
	Session.year = _year_picker.get_selected_id()
	Session.robot_config = _robot_paths[_robot_picker.selected]
	Settings.save_file()
	get_tree().change_scene_to_file(PRACTICE_SCENE)


func _on_settings() -> void:
	_menu.visible = false
	_settings.open()


func _on_settings_closed() -> void:
	_menu.visible = true


func _row(text: String, control: Control) -> HBoxContainer:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(90.0, 0.0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_child(label)
	row.add_child(control)
	return row


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.pressed.connect(action)
	return button
