extends SceneTree
## Headless check of how a practice session starts and restarts. Run with:
##   godot --headless --path . --fixed-fps 240 -s res://tests/session_test.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://sim/main.tscn").instantiate()
	root.add_child(main)
	var robot: SwerveRobot = main.robot
	await _wait(1.0)

	print("\n== Start of a match ==")
	var preload_coral := robot.intake.held
	_check("the robot starts with a coral preloaded", preload_coral != null and preload_coral.kind == GamePiece.CORAL)
	var hold: Array = robot.config["intake"]["pieces"]["coral"]["hold_m"]
	var carried := robot.global_transform * Frc.to_godot(Vector3(hold[0], hold[1], hold[2]))
	_check("the preload sits in the intake", preload_coral.global_position.distance_to(carried) < 0.02)
	_check("the robot stands level on its wheels", robot.global_basis.y.dot(Vector3.UP) > 0.999)

	print("\n== Reset ==")
	main.driver.algae_mode = true
	main.call("_reset")
	await _wait(1.0)
	var again := robot.intake.held
	_check("a reset preloads a new coral", again != null and again != preload_coral and again.kind == GamePiece.CORAL)
	_check("a reset goes back to coral mode", not main.driver.algae_mode)
	var held := 0
	for piece: GamePiece in main.pieces.get_children():
		held += int(piece.held)
	_check("only that coral is held", held == 1)

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)


func _wait(seconds: float) -> void:
	for _i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		failures += 1
