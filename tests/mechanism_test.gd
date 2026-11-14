extends SceneTree
## Headless checks of the superstructure: every preset is reached and held,
## and the robot stays put and upright while it moves. Run with:
##   godot --headless --path . --fixed-fps 240 -s res://tests/mechanism_test.gd [-- <robot config>]

var robot: SwerveRobot
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(PlaceholderField.new())
	robot = SwerveRobot.new()
	var args := OS.get_cmdline_user_args()
	var config_path := "res://data/robots/2910_2025.json" if args.is_empty() else args[0]
	robot.setup(SwerveRobot.load_config(config_path), Color.BLUE)
	root.add_child(robot)
	var superstructure := robot.superstructure
	if superstructure == null or superstructure.joints.is_empty():
		print("Robot has no built model or no mechanism; run scripts/build_robot.py first.")
		quit(1)
		return
	print("Robot: %s" % robot.config["name"])
	robot.reset_pose(Vector2(4.0, 2.0), 0.0)
	await _wait(1.0)
	var start := robot.global_position
	var stowed_com := robot.center_of_mass

	for preset: Dictionary in superstructure.presets + [superstructure.presets[0]]:
		print("\n== %s ==" % preset["name"])
		superstructure.go_to(preset)
		var dt := 1.0 / Engine.physics_ticks_per_second
		var settle_time := -1.0
		var peak_current := 0.0
		var max_tilt := 0.0
		for tick in int(3.0 / dt):
			await physics_frame
			peak_current = maxf(peak_current, robot.battery.current)
			max_tilt = maxf(max_tilt, _tilt())
			if settle_time < 0.0 and _settled():
				settle_time = (tick + 1) * dt
		await _wait(0.5)
		var report := PackedStringArray()
		for joint in superstructure.joints:
			var unit := "m" if joint.prismatic else "deg"
			var scale := 1.0 if joint.prismatic else 180.0 / PI
			report.append("%s %.3f %s (goal %.3f)" % [
				joint.name, joint.position * scale, unit, superstructure.requested(joint) * scale])
		print("  ".join(report))
		print("settled in %.2f s, peak battery current %.0f A, max tilt %.1f deg, centre of mass height %.3f m" % [
			settle_time, peak_current, max_tilt, robot.center_of_mass.y])
		_check("reaches the preset", settle_time > 0.0 and settle_time < 2.5)
		_check("holds it", _settled())
		_check("stays upright", max_tilt < 10.0)

	var drift := robot.global_position.distance_to(start)
	print("\nback at stow: drifted %.3f m, centre of mass moved %.4f m" % [
		drift, robot.center_of_mass.distance_to(stowed_com)])
	_check("robot stayed in place", drift < 0.05)
	_check("centre of mass returned", robot.center_of_mass.distance_to(stowed_com) < 1e-3)

	print("\n== Sprint and brake with the arm at its most extended preset ==")
	var tallest: Dictionary = superstructure.presets[0]
	for preset: Dictionary in superstructure.presets:
		if preset["positions"]["extension"] > tallest["positions"]["extension"]:
			tallest = preset
	superstructure.go_to(tallest)
	await _wait(2.5)
	var tilt := 0.0
	robot.command = Vector3(robot.max_speed, 0.0, 0.0)
	for tick in int(1.0 * Engine.physics_ticks_per_second):
		await physics_frame
		tilt = maxf(tilt, _tilt())
	robot.command = Vector3.ZERO
	for tick in int(1.5 * Engine.physics_ticks_per_second):
		await physics_frame
		tilt = maxf(tilt, _tilt())
	print("max tilt %.1f deg, ended %s" % [tilt, "upright" if _tilt() < 10.0 else "tipped over"])

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)


func _settled() -> bool:
	for joint in robot.superstructure.joints:
		var tolerance := 0.01 if joint.prismatic else deg_to_rad(1.0)
		var target := robot.superstructure.requested(joint)
		if absf(joint.position - target) > tolerance or absf(joint.velocity) > 5.0 * tolerance:
			return false
	return true


func _tilt() -> float:
	return rad_to_deg(acos(clampf(robot.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))


func _wait(seconds: float) -> void:
	for _i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		failures += 1
