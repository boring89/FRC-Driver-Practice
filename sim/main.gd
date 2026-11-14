extends Node3D
## Practice session: one field, one robot, one driver. Which field and robot
## comes from Session.

const TITLE_SCENE := "res://sim/menu/title_menu.tscn"

var robot := SwerveRobot.new()
var camera := CameraRig.new()
## Null when the field has no game piece data.
var pieces: GamePieces
## Null when the field has no scoring rules.
var game: Match
var driver := DriverInput.new()


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
	robot.driver_heading = Session.driver_heading()
	add_child(robot)
	_place_robot()

	driver.robot = robot
	var field_config := "res://data/fields/%d.json" % Session.year
	if FileAccess.file_exists(field_config):
		var field: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(field_config))
		if field.has("reefs"):
			driver.reef_align = ReefAlign.new(field["reefs"])
		if field.has("match") and pieces:
			game = Match.new(field, pieces)
			add_child(game)
			game.start(Session.match_seconds, Session.free_practice)
	add_child(driver)

	camera.target = robot
	camera.driver_heading = Session.driver_heading()
	add_child(camera)
	camera.make_current()

	var hud := Hud.new()
	hud.robot = robot
	hud.camera = camera
	hud.driver = driver
	add_child(hud)

	if game:
		var scoreboard := Scoreboard.new()
		scoreboard.game = game
		add_child(scoreboard)

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


func _process(_dt: float) -> void:
	# The robot is disabled when the match clock runs out, as on a real field.
	driver.enabled = game == null or game.running


## Puts the robot and the game pieces back and starts a new match.
func _reset() -> void:
	_place_robot()
	if pieces:
		pieces.reset()
	if game:
		game.start(Session.match_seconds, Session.free_practice)


func _place_robot() -> void:
	var start := Session.start_pose()
	robot.reset_pose(Vector2(start.x, start.y), start.z)


## The human player drops a coral into the station nearest the robot.
func _feed_coral() -> void:
	if pieces:
		pieces.feed_coral(robot.global_position)


func _preload_coral() -> void:
	if pieces and robot.intake and robot.intake.held == null:
		var coral := pieces.spawn(GamePiece.CORAL)
		coral.global_position = robot.global_position + Vector3(0.0, 0.5, 0.0)
		robot.intake.load_piece(coral)
