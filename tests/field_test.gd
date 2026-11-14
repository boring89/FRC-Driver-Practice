extends SceneTree
## Headless checks of the robot against the CAD field's colliders. Run with:
##   godot --headless --path . --fixed-fps 240 -s res://tests/field_test.gd

const YEAR := 2025
# Half the robot's length including bumpers.
const HALF_ROBOT := 0.4325

var robot: SwerveRobot
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(CadField.asset_path(YEAR)):
		print("No CAD field asset; run scripts/build_field.py first.")
		quit(1)
		return
	root.add_child(CadField.new(YEAR))
	robot = SwerveRobot.new()
	robot.setup(SwerveRobot.load_config("res://data/robots/placeholder_swerve.json"), Color.BLUE)
	root.add_child(robot)

	print("\n== Open carpet ==")
	var pose := await _drive(Vector2(2.0, 2.0), Vector2(1.0, 0.0), 1.6)
	print("reached x %.2f m, height %.4f m" % [pose.x, pose.z])
	_check("crosses open carpet unobstructed", pose.x > 6.0)
	_check("stays on the floor", absf(pose.z) < 0.004)

	print("\n== Reef ==")
	var reef_face := 4.489 - 0.5 * 1.664
	pose = await _drive(Vector2(2.0, 0.5 * Frc.FIELD_WIDTH), Vector2(1.0, 0.0), 2.5)
	print("stopped at x %.3f m (reef face at %.3f, bumper reach %.3f)" % [pose.x, reef_face, HALF_ROBOT])
	_check("stopped by the reef", absf(pose.x - (reef_face - HALF_ROBOT)) < 0.15)

	print("\n== Guardrail ==")
	pose = await _drive(Vector2(4.5, 1.6), Vector2(0.0, -1.0), 2.5)
	print("stopped at y %.3f m" % pose.y)
	_check("stopped by the guardrail", pose.y > HALF_ROBOT - 0.03 and pose.y < HALF_ROBOT + 0.15)

	print("\n== Alliance wall ==")
	pose = await _drive(Vector2(2.0, 0.5 * Frc.FIELD_WIDTH), Vector2(-1.0, 0.0), 2.5)
	print("stopped at x %.3f m" % pose.x)
	_check("stopped by the alliance wall", pose.x > HALF_ROBOT - 0.03 and pose.x < HALF_ROBOT + 0.15)

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)


## Starts at `from`, drives at full speed along `direction` for `seconds`, and
## returns the final field pose. Also checks the robot ended upright.
func _drive(from: Vector2, direction: Vector2, seconds: float) -> Vector3:
	robot.reset_pose(from, 0.0)
	await _wait(0.5)
	robot.command = Vector3(direction.x, direction.y, 0.0) * robot.max_speed
	await _wait(seconds)
	robot.command = Vector3.ZERO
	_check("upright", robot.global_basis.y.dot(Vector3.UP) > 0.98)
	return Frc.from_godot(robot.global_position)


func _wait(seconds: float) -> void:
	for _i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		failures += 1
