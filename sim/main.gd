extends Node3D
## Practice session: one field, one robot, one driver.

const ROBOT_CONFIG := "res://data/robots/2910_2025.json"
const FIELD_YEAR := 2025
const START_POSITION := Vector2(1.6, 2.0)

var robot := SwerveRobot.new()
var camera := CameraRig.new()
## Null when the field has no game piece data.
var pieces: GamePieces


func _ready() -> void:
	_build_lighting()
	# The CAD field only exists once scripts/build_field.py has been run.
	if ResourceLoader.exists(CadField.asset_path(FIELD_YEAR)):
		add_child(CadField.new(FIELD_YEAR))
	else:
		add_child(PlaceholderField.new())

	if FileAccess.file_exists(GamePieces.data_path(FIELD_YEAR)):
		pieces = GamePieces.new(FIELD_YEAR)
		add_child(pieces)

	robot.setup(SwerveRobot.load_config(ROBOT_CONFIG), Color(0.1, 0.25, 0.85))
	add_child(robot)
	robot.reset_pose(START_POSITION, 0.0)

	var driver := DriverInput.new()
	driver.robot = robot
	add_child(driver)

	camera.target = robot
	add_child(camera)
	camera.make_current()

	var hud := Hud.new()
	hud.robot = robot
	hud.camera = camera
	add_child(hud)

	var pose_editor := PoseEditor.new()
	pose_editor.robot = robot
	pose_editor.camera = camera
	add_child(pose_editor)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var button := event as InputEventJoypadButton
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_R:
				_reset()
			KEY_C:
				camera.cycle()
			KEY_H:
				_feed_coral()
			KEY_L:
				_preload_coral()
			KEY_ESCAPE:
				get_tree().quit()
	elif button and button.pressed:
		match button.button_index:
			JOY_BUTTON_START:
				_reset()
			JOY_BUTTON_BACK:
				camera.cycle()
			JOY_BUTTON_RIGHT_SHOULDER:
				_feed_coral()
			JOY_BUTTON_LEFT_SHOULDER:
				_preload_coral()


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


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)

	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
