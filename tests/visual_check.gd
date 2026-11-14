extends SceneTree
## Renders the practice scene while the robot drives, then side views of the
## named mechanism presets against the reef, and saves screenshots. Needs a
## display. Run with:
##   godot --path . -s res://tests/visual_check.gd -- <output directory> [preset ...]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := "user://"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	var main: Node = load("res://sim/main.tscn").instantiate()
	root.add_child(main)
	var robot: SwerveRobot = main.robot
	var camera: CameraRig = main.camera
	# Take over from the driver so the run is repeatable.
	for child in main.get_children():
		if child is DriverInput:
			child.robot = null

	robot.command = Vector3(1.5, -0.3, 1.5)
	camera.mode = CameraRig.Mode.FOLLOW
	await _shot(1.0, out_dir.path_join("view_follow.png"))
	robot.command = Vector3.ZERO

	# Side views of the robot against the blue reef in a few mechanism poses.
	var superstructure := robot.superstructure
	if superstructure == null or superstructure.presets.is_empty():
		quit()
		return
	var side := Camera3D.new()
	root.add_child(side)
	side.make_current()
	for preset: Dictionary in superstructure.presets:
		if not args.slice(1).has(preset["name"]):
			continue
		robot.reset_pose(Vector2(3.657 - 0.48, 0.5 * Frc.FIELD_WIDTH), 0.0)
		superstructure.go_to(preset)
		side.global_position = robot.global_position + Vector3(0.5, 1.1, 2.9)
		side.look_at(robot.global_position + Vector3(0.5, 1.0, 0.0), Vector3.UP)
		await _shot(3.0, out_dir.path_join("pose_%s.png" % preset["name"]))
	quit()


func _shot(seconds: float, path: String) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
