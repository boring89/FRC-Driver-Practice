extends Node3D
## Title screen: the selected season's field turning slowly behind a menu for
## choosing the season and robot, opening the settings, or quitting.

const PRACTICE_SCENE := "res://sim/main.tscn"
const FIELDS_DIR := "res://data/fields"
const ROBOTS_DIR := "res://data/robots"
const VERSION := "v0.1"
const _ORBIT_RATE := 0.05

var _camera := Camera3D.new()
var _backdrop := Node3D.new()
var _menu := VBoxContainer.new()
var _season_item: Button
var _robot_item: Button
var _settings := SettingsPanel.new()
# Seasons as [year, name], robots of the chosen season as [config path, name].
var _seasons: Array = []
var _robots: Array = []
var _season := 0
var _robot := 0
var _angle := 0.6


func _ready() -> void:
	Settings.load_file()
	Settings.apply(get_tree())
	Stage.add_lighting(self)
	add_child(_backdrop)
	add_child(_camera)
	_camera.fov = 55.0

	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "FRC Driver Practice"
	title.position = Vector2(40.0, 28.0)
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	title.add_theme_constant_override("outline_size", 10)
	layer.add_child(title)
	var version := Label.new()
	version.text = VERSION
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.add_theme_font_size_override("font_size", 24)
	layer.add_child(version)

	_menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 32)
	_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_menu)
	_add_item("Play", _on_play)
	_season_item = _add_item("", _cycle_season)
	_robot_item = _add_item("", _cycle_robot)
	_add_item("Settings", _on_settings)
	_add_item("Quit", get_tree().quit)

	_settings.visible = false
	_settings.closed.connect(_menu.show)
	layer.add_child(_settings)

	for file in DirAccess.get_files_at(FIELDS_DIR):
		if file.get_extension() == "json":
			var field: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIELDS_DIR.path_join(file)))
			_seasons.append([int(file.get_basename()), field["name"]])
	for i in _seasons.size():
		if _seasons[i][0] == Session.year:
			_season = i
	_show_season()


func _process(dt: float) -> void:
	_angle += _ORBIT_RATE * dt
	var centre := Frc.to_godot(Vector3(0.5 * Frc.FIELD_LENGTH, 0.5 * Frc.FIELD_WIDTH, 0.5))
	_camera.global_position = centre + Vector3(cos(_angle) * 13.0, 7.0, sin(_angle) * 13.0)
	_camera.look_at(centre, Vector3.UP)


## Loads the chosen season's field behind the menu and lists its robots.
func _show_season() -> void:
	var year: int = _seasons[_season][0]
	_season_item.text = "Season: %s" % _seasons[_season][1]
	for child in _backdrop.get_children():
		child.queue_free()
	if ResourceLoader.exists(CadField.asset_path(year)):
		_backdrop.add_child(CadField.new(year))
		if FileAccess.file_exists(GamePieces.data_path(year)):
			_backdrop.add_child(GamePieces.new(year))
	else:
		_backdrop.add_child(PlaceholderField.new())

	_robots.clear()
	_robot = 0
	for file in DirAccess.get_files_at(ROBOTS_DIR):
		if file.get_extension() != "json" or file.ends_with("_presets.json"):
			continue
		var path := ROBOTS_DIR.path_join(file)
		var robot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		# A robot without a year fits every season.
		if robot.get("year", year) != year:
			continue
		if path == Session.robot_config:
			_robot = _robots.size()
		_robots.append([path, robot["name"]])
	_robot_item.text = "Robot: %s" % _robots[_robot][1]


func _cycle_season() -> void:
	_season = (_season + 1) % _seasons.size()
	_show_season()


func _cycle_robot() -> void:
	_robot = (_robot + 1) % _robots.size()
	_robot_item.text = "Robot: %s" % _robots[_robot][1]


func _on_play() -> void:
	Session.year = _seasons[_season][0]
	Session.robot_config = _robots[_robot][0]
	Settings.save_file()
	get_tree().change_scene_to_file(PRACTICE_SCENE)


func _on_settings() -> void:
	_menu.visible = false
	_settings.open()


func _add_item(text: String, action: Callable) -> Button:
	var item := MenuStyle.menu_item(text)
	item.pressed.connect(action)
	_menu.add_child(item)
	return item
