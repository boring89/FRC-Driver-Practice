class_name MatchSetup
extends Control
## The screen between the title menu and a match: alliance, where the robot
## starts, whether it is a timed match or open-ended practice, and how coral
## is fed.

signal closed
signal started

var _alliance := MenuStyle.button("", 22)
var _mode := MenuStyle.button("", 22)
var _length := MenuStyle.button("", 22)
var _feed := MenuStyle.button("", 22)
var _map := StartSpotMap.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.box(MenuStyle.PANEL, 8, 24))
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Match setup"
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)

	var options := VBoxContainer.new()
	options.custom_minimum_size = Vector2(260.0, 0.0)
	options.add_theme_constant_override("separation", 10)
	body.add_child(options)
	for option: Array in [
		[_alliance, _cycle_alliance], [_mode, _cycle_mode], [_length, _cycle_length], [_feed, _cycle_feed],
	]:
		(option[0] as Button).pressed.connect(option[1])
		options.add_child(option[0])
	var reset_spot := MenuStyle.button("Reset starting spot", 18)
	reset_spot.pressed.connect(_reset_spot)
	options.add_child(reset_spot)

	var map_side := VBoxContainer.new()
	body.add_child(map_side)
	_map.changed.connect(_on_spot_changed)
	map_side.add_child(_map)
	var hint := Label.new()
	hint.text = "Drag to place the robot. Mouse wheel or %s / %s turns it." % [
		Settings.key_name("turn_left"), Settings.key_name("turn_right")]
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	map_side.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var back := MenuStyle.button("←  Back", 24)
	back.pressed.connect(_on_back)
	buttons.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var start := MenuStyle.button("Start match", 24, true)
	start.custom_minimum_size = Vector2(220.0, 0.0)
	start.pressed.connect(_on_start)
	buttons.add_child(start)


## Shows the screen for the robot and field chosen in the title menu.
func open(robot: Dictionary, field: Dictionary) -> void:
	visible = true
	var frame: Array = robot["frame_m"]
	var bumper: float = robot["bumper_thickness_m"]
	_map.footprint = Vector2(float(frame[0]) + 2.0 * bumper, float(frame[1]) + 2.0 * bumper)
	if field.has("reefs"):
		_map.reefs = field["reefs"]["centers_m"]
		_map.reef_face_distance = field["reefs"]["face_distance_m"]
	_refresh()


func _refresh() -> void:
	_alliance.text = "Alliance: %s" % Session.alliance.capitalize()
	MenuStyle.paint(_alliance, false)
	_mode.text = "Mode: %s" % ("Free practice" if Session.free_practice else "Match")
	_length.text = "Length: %d:%02d" % [Session.match_seconds / 60, Session.match_seconds % 60]
	_length.disabled = Session.free_practice
	_feed.text = "Coral feed: %s" % (
			"keep %d on floor" % Session.auto_feed_limit if Session.auto_feed_limit > 0 else "manual")
	var pose := Session.start_pose()
	_map.alliance = Session.alliance
	_map.spot = Vector2(pose.x, pose.y)
	_map.heading = pose.z
	_map.queue_redraw()


func _cycle_alliance() -> void:
	Session.alliance = "red" if Session.alliance == "blue" else "blue"
	# The old spot is on the other alliance's side now.
	Session.start_position = Vector2(NAN, NAN)
	_refresh()


func _cycle_mode() -> void:
	Session.free_practice = not Session.free_practice
	_refresh()


func _cycle_length() -> void:
	var index := Session.MATCH_LENGTHS.find(Session.match_seconds)
	Session.match_seconds = Session.MATCH_LENGTHS[(index + 1) % Session.MATCH_LENGTHS.size()]
	_refresh()


func _cycle_feed() -> void:
	var index := Session.AUTO_FEED_LIMITS.find(Session.auto_feed_limit)
	Session.auto_feed_limit = Session.AUTO_FEED_LIMITS[(index + 1) % Session.AUTO_FEED_LIMITS.size()]
	_refresh()


func _reset_spot() -> void:
	Session.start_position = Vector2(NAN, NAN)
	_refresh()


func _on_spot_changed() -> void:
	Session.start_position = _map.spot
	Session.start_heading = _map.heading


func _on_back() -> void:
	Settings.save_file()
	visible = false
	closed.emit()


func _on_start() -> void:
	Settings.save_file()
	started.emit()
