extends Node3D
## Practice session: one field, one robot, one driver. Which field and robot
## comes from Session.

const TITLE_SCENE := "res://sim/menu/title_menu.tscn"
const START_POSITION := Vector2(1.6, 2.0)

var robot := SwerveRobot.new()
var camera := CameraRig.new()
## Null when the field has no game piece data.
var pieces: GamePieces


func _ready() -> void:
	Settings.apply(get_tree())
	Stage.add_lighting(self)
	# The CAD field only exists once scripts/build_field.py has been run.
	if ResourceLoader.exists(CadField.asset_path(Session.year)):
		add_child(CadField.new(Session.year))
	else:
		add_child(PlaceholderField.new())

	if FileAccess.file_exists(GamePieces.data_path(Session.year)):
		pieces = GamePieces.new(Session.year)
		add_child(pieces)

	robot.setup(SwerveRobot.load_config(Session.robot_config), Color(0.1, 0.25, 0.85))
	add_child(robot)
	robot.reset_pose(START_POSITION, 0.0)

	var driver := DriverInput.new()
	driver.robot = robot
	var field_config := "res://data/fields/%d.json" % Session.year
	if FileAccess.file_exists(field_config):
		var field: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(field_config))
		if field.has("reefs"):
			driver.reef_align = ReefAlign.new(field["reefs"])
	add_child(driver)

	camera.target = robot
	add_child(camera)
	camera.make_current()

	var hud := Hud.new()
	hud.robot = robot
	hud.camera = camera
	hud.driver = driver
	add_child(hud)

	var pose_editor := PoseEditor.new()
	pose_editor.robot = robot
	pose_editor.camera = camera
	add_child(pose_editor)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		_reset()
	elif event.is_action_pressed("camera"):
		camera.cycle()
	elif event.is_action_pressed("feed_coral"):
		_feed_coral()
	elif event.is_action_pressed("preload_coral"):
		_preload_coral()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(TITLE_SCENE)


func _reset() -> void:
	robot.reset_pose(START_POSITION, 0.0)
	if pieces:
		pieces.reset()


## The human player drops a coral into the station nearest the robot.
func _feed_coral() -> void:
	if pieces:
		pieces.feed_coral(robot.global_position)


func _preload_coral() -> void:
	if pieces and robot.intake and robot.intake.held == null:
		var coral := pieces.spawn(GamePiece.CORAL)
		coral.global_position = robot.global_position + Vector3(0.0, 0.5, 0.0)
		robot.intake.load_piece(coral)
