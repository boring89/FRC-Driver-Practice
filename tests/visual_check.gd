extends SceneTree
## Renders the practice scene from each camera while the robot drives, and saves
## screenshots. Needs a display. Run with:
##   godot --path . -s res://tests/visual_check.gd -- <output directory>


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

	for mode in CameraRig.Mode.size():
		robot.command = Vector3(1.5, -0.3, 1.5)
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("view_%d.png" % mode)
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		camera.cycle()
	quit()
