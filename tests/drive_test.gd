extends SceneTree
## Headless drive physics checks. Run with:
##   godot --headless --path . --fixed-fps 240 -s res://tests/drive_test.gd [-- <robot config>]

const G := 9.80665

var robot: SwerveRobot
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(PlaceholderField.new())
	robot = SwerveRobot.new()
	var args := OS.get_cmdline_user_args()
	var config_path := "res://data/robots/placeholder_swerve.json" if args.is_empty() else args[0]
	robot.setup(SwerveRobot.load_config(config_path), Color.BLUE)
	root.add_child(robot)
	print("Robot: %s" % robot.config["name"])

	await _test_rest()
	await _test_sprint_and_brake()
	await _test_spin()
	await _test_strafe_while_spinning()
	await _test_wall_hit()

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)


func _test_rest() -> void:
	print("\n== Rest ==")
	robot.reset_pose(Vector2(2.0, 1.5), 0.0)
	await _wait(1.0)
	var start := robot.global_position
	await _wait(2.0)
	var drift := robot.global_position.distance_to(start)
	print("drift %.5f m, height %.4f m, speed %.5f m/s, battery %.2f V" % [
		drift, robot.global_position.y, robot.linear_velocity.length(), robot.battery.voltage])
	_check("stays put", drift < 1e-3)
	_check("sits on its wheels", absf(robot.global_position.y) < 0.004)
	_check("no jitter", robot.linear_velocity.length() < 1e-3)


func _test_sprint_and_brake() -> void:
	print("\n== Sprint and brake ==")
	robot.reset_pose(Vector2(1.5, 1.2), 0.0)
	await _wait(0.5)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var mu: float = robot.modules[0].mu_static
	var times := {}
	var peak_accel := 0.0
	var peak_current := 0.0
	var min_voltage := 99.0
	var max_slip := 0.0
	var last_speed := 0.0
	var smoothed_accel := 0.0
	robot.command = Vector3(robot.max_speed, 0.0, 0.0)
	for tick in int(3.0 / dt):
		await physics_frame
		var speed := robot.ground_speed()
		# Average over ~10 ticks so tire-spring ripple does not inflate the peak.
		smoothed_accel += ((speed - last_speed) / dt - smoothed_accel) * 0.1
		last_speed = speed
		peak_accel = maxf(peak_accel, smoothed_accel)
		peak_current = maxf(peak_current, robot.battery.current)
		min_voltage = minf(min_voltage, robot.battery.voltage)
		max_slip = maxf(max_slip, robot.modules[2].slip_speed)
		for mark in [1.0, 2.0, 3.0, 4.0]:
			if speed >= mark and not times.has(mark):
				times[mark] = (tick + 1) * dt
	var top := robot.ground_speed()
	var travelled := Frc.from_godot(robot.global_position).x - 1.5
	print("time to 1/2/3/4 m/s: %s" % [times.values().map(func(t: float) -> String: return "%.2f" % t)])
	print("top speed %.2f m/s (wheel free speed %.2f), distance %.2f m in 3 s" % [
		top, robot.modules[0].free_speed(), travelled])
	print("peak accel %.2f m/s^2 (%.2f g), peak battery current %.0f A, min voltage %.2f V, max rear slip %.2f m/s" % [
		peak_accel, peak_accel / G, peak_current, min_voltage, max_slip])
	_check("top speed near free speed", top > 0.85 * robot.modules[0].free_speed() and top < robot.modules[0].free_speed())
	_check("acceleration within traction limit", peak_accel < 1.05 * mu * G)
	_check("acceleration is brisk", peak_accel > 0.5 * G)
	_check("drives straight", absf(Frc.from_godot(robot.global_position).y - 1.2) < 0.02)
	_check("stays flat", absf(robot.global_basis.y.dot(Vector3.UP)) > 0.995)

	robot.command = Vector3.ZERO
	var brake_start := Frc.from_godot(robot.global_position).x
	var stop_time := -1.0
	for tick in int(2.0 / dt):
		await physics_frame
		if stop_time < 0.0 and robot.ground_speed() < 0.05:
			stop_time = (tick + 1) * dt
	print("brake: stopped in %.2f s over %.2f m, residual speed %.4f m/s" % [
		stop_time, Frc.from_godot(robot.global_position).x - brake_start, robot.ground_speed()])
	_check("stops", stop_time > 0.0 and robot.ground_speed() < 0.02)


func _test_spin() -> void:
	print("\n== Spin in place ==")
	robot.reset_pose(Vector2(2.5, 1.5), 0.0)
	await _wait(0.5)
	var start := robot.global_position
	robot.command = Vector3(0.0, 0.0, 6.0)
	await _wait(2.0)
	var rate := robot.angular_velocity.y
	var drift := robot.global_position.distance_to(start)
	print("yaw rate %.2f rad/s (asked 6.00), centre drift %.3f m" % [rate, drift])
	_check("yaw rate tracks", absf(rate - 6.0) < 0.6)
	_check("spins about its centre", drift < 0.05)
	robot.command = Vector3.ZERO
	await _wait(1.0)


func _test_strafe_while_spinning() -> void:
	print("\n== Field-relative strafe while spinning ==")
	robot.reset_pose(Vector2(2.0, 1.5), 0.0)
	await _wait(0.5)
	var start := Frc.from_godot(robot.global_position)
	robot.command = Vector3(2.0, 0.0, 3.0)
	await _wait(2.5)
	var travel := Frc.from_godot(robot.global_position) - start
	var velocity := Frc.from_godot(robot.linear_velocity)
	var course := rad_to_deg(atan2(travel.y, travel.x))
	print("travelled (%.2f, %.2f) m, course %.1f deg, speed %.2f m/s, yaw rate %.2f rad/s" % [
		travel.x, travel.y, course, Vector2(velocity.x, velocity.y).length(), robot.angular_velocity.y])
	_check("holds field course", absf(course) < 5.0)
	_check("holds speed", absf(Vector2(velocity.x, velocity.y).length() - 2.0) < 0.3)
	_check("holds spin", absf(robot.angular_velocity.y - 3.0) < 0.5)
	robot.command = Vector3.ZERO
	await _wait(1.0)


func _test_wall_hit() -> void:
	print("\n== Full-speed wall hit ==")
	robot.reset_pose(Vector2(5.0, 1.2), PI)
	await _wait(0.5)
	robot.command = Vector3(-robot.max_speed, 0.0, 0.0)
	await _wait(3.0)
	var pose := Frc.from_godot(robot.global_position)
	print("ended at x %.3f m, height %.4f m, tilt %.1f deg" % [
		pose.x, pose.z, rad_to_deg(acos(clampf(robot.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))])
	_check("stopped by the wall", pose.x > 0.3 and pose.x < 0.6)
	_check("still upright", robot.global_basis.y.dot(Vector3.UP) > 0.95)
	robot.command = Vector3.ZERO


func _wait(seconds: float) -> void:
	for _i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		failures += 1
