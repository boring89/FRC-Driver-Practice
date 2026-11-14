extends SceneTree
## Headless checks of game pieces on the CAD field and of the robot's intake.
## Run with:
##   godot --headless --path . --fixed-fps 240 -s res://tests/game_piece_test.gd

const YEAR := 2025
# Blue reef face nearest the blue wall, and one of its two branch columns.
const REEF_FACE_X := 3.657
const BRANCH_Y := 4.026 + 0.1643

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(CadField.asset_path(YEAR)):
		print("No CAD field asset; run scripts/build_field.py first.")
		quit(1)
		return
	Settings.apply(self)
	root.add_child(CadField.new(YEAR))
	var pieces := GamePieces.new(YEAR)
	root.add_child(pieces)
	var robot := SwerveRobot.new()
	robot.setup(SwerveRobot.load_config("res://data/robots/2910_2025.json"), Color.BLUE)
	root.add_child(robot)
	robot.reset_pose(Vector2(8.0, 2.0), 0.0)
	await _wait(0.5)

	print("\n== Staged pieces, woken up ==")
	var staged := pieces.get_children()
	var starts := {}
	for piece: GamePiece in staged:
		starts[piece] = piece.global_position
		piece.sleeping = false
	await _wait(3.0)
	var moved := {GamePiece.CORAL: 0, GamePiece.ALGAE: 0}
	var worst := 0.0
	for piece: GamePiece in staged:
		var drift := piece.global_position.distance_to(starts[piece])
		worst = maxf(worst, drift)
		if drift > 0.05:
			moved[piece.kind] += 1
	print("%d pieces staged; moved more than 5 cm: %d coral, %d algae (worst %.2f m)" % [
		staged.size(), moved[GamePiece.CORAL], moved[GamePiece.ALGAE], worst])
	_check("staged coral stays standing", moved[GamePiece.CORAL] == 0)
	_check("staged algae stays put", moved[GamePiece.ALGAE] == 0)

	print("\n== Coral station feed ==")
	var fed := pieces.feed_coral(Frc.to_godot(Vector3(1.5, 1.0, 0.0)))
	var slot := Frc.from_godot(fed.global_position)
	await _wait(3.0)
	var landed := Frc.from_godot(fed.global_position)
	print("dropped at (%.2f, %.2f, %.2f), came to rest at (%.2f, %.2f, %.2f)" % [
		slot.x, slot.y, slot.z, landed.x, landed.y, landed.z])
	_check("lands on the carpet", landed.z < 0.16)
	_check("ends up in the field near the station", landed.x > 0.5 and landed.y > 0.5 and landed.length() < 4.0)

	print("\n== Intake ==")
	var coral := pieces.spawn(GamePiece.CORAL)
	var mouth: Array = robot.config["intake"]["pieces"]["coral"]["mouth_m"]
	coral.global_position = robot.global_transform * Frc.to_godot(Vector3(mouth[0], 0.0, mouth[2] + 0.1))
	robot.intake.command = 1.0
	await _wait(0.5)
	_check("picks up a coral at its mouth", robot.intake.held == coral)
	robot.intake.command = 0.0
	robot.command = Vector3(2.0, 0.0, 0.0)
	await _wait(1.0)
	robot.command = Vector3.ZERO
	await _wait(1.0)
	var hold: Array = robot.config["intake"]["pieces"]["coral"]["hold_m"]
	var carried := robot.global_transform * Frc.to_godot(Vector3(hold[0], hold[1], hold[2]))
	print("carried coral is %.3f m from its hold point after driving" % coral.global_position.distance_to(carried))
	_check("carries it while driving", robot.intake.held == coral and coral.global_position.distance_to(carried) < 0.02)
	robot.intake.command = -1.0
	await _wait(0.1)
	robot.intake.command = 0.0
	await _wait(2.0)
	var dropped := Frc.from_godot(coral.global_position)
	print("ejected coral came to rest at height %.3f m, %.2f m from the robot" % [
		dropped.z, coral.global_position.distance_to(robot.global_position)])
	_check("lets go of it", robot.intake.held == null and not coral.held)
	_check("ejected coral falls to the floor", dropped.z < 0.16)
	_check("robot is undisturbed", robot.global_basis.y.dot(Vector3.UP) > 0.99)

	print("\n== Scoring coral on the reef ==")
	for piece in pieces.get_children():
		piece.queue_free()
	var presets := {}
	for preset: Dictionary in robot.superstructure.presets:
		presets[preset["name"]] = preset
	# Preset, gap between bumper and reef face, and the height band a coral
	# hanging on that level's branch rests in. The back poses score tail to the
	# reef, with the coral leaving by the intake's mouth.
	var standoffs: Dictionary = robot.config["controls"]["align_standoff_m"]
	for shot: Array in [
		["l4", 1.6, 1.8], ["l3", 1.05, 1.2], ["l2", 0.65, 0.8],
		["l4_back", 1.6, 1.8], ["l3_back", 1.05, 1.2], ["l2_back", 0.65, 0.8],
	]:
		var backward: bool = robot.config["controls"]["back_to_reef"].has(shot[0])
		var gap: float = standoffs[shot[0]]
		var half_length := 0.5 * float(robot.config["frame_m"][0]) + float(robot.config["bumper_thickness_m"])
		robot.reset_pose(Vector2(REEF_FACE_X - half_length - gap, BRANCH_Y), PI if backward else 0.0)
		await _wait(0.5)
		var scored := pieces.spawn(GamePiece.CORAL)
		scored.global_position = robot.global_position + Vector3(0.0, 0.5, 0.0)
		robot.intake.load_piece(scored)
		robot.superstructure.go_to(presets[shot[0]])
		await _wait(2.0)
		robot.intake.command = -2.0 if backward else -1.0
		await _wait(0.1)
		robot.intake.command = 0.0
		await _wait(1.0)
		robot.superstructure.go_to(presets["stow"])
		await _wait(2.0)
		var rest := Frc.from_godot(scored.global_position)
		print("%s from %.2f m back: coral rests %.3f m past the reef face at height %.3f m" % [
			shot[0], gap, rest.x - REEF_FACE_X, rest.z])
		_check("coral stays on the branch with %s" % shot[0],
				rest.z > float(shot[1]) and rest.z < float(shot[2]) and absf(rest.y - BRANCH_Y) < 0.05)
		scored.queue_free()

	print("\n== Choosing poses and branches ==")
	var chooser := DriverInput.new()
	chooser.robot = robot
	chooser.reef_align = ReefAlign.new(
			JSON.parse_string(FileAccess.get_file_as_string("res://data/fields/%d.json" % YEAR))["reefs"])
	root.add_child(chooser)
	chooser.set_physics_process(false)
	robot.superstructure.go_to(presets["stow"])
	# In front of the reef face nearest the blue wall, then round the far side.
	robot.reset_pose(Vector2(2.6, BRANCH_Y), 0.0)
	_check("nose to the reef picks the front pose", chooser.level_preset("l4") == "l4")
	_check("left branch on the near side is to the driver's left",
			absf(chooser.align_target(1.0).y - BRANCH_Y) < 0.01)
	robot.reset_pose(Vector2(2.6, BRANCH_Y), PI)
	_check("tail to the reef picks the back pose", chooser.level_preset("l4") == "l4_back")
	_check("a level without a back pose stays nose-first", chooser.level_preset("l1") == "l1")
	robot.reset_pose(Vector2(6.4, BRANCH_Y), PI)
	_check("nose to the reef from the far side picks the front pose", chooser.level_preset("l4") == "l4")
	var far := chooser.align_target(1.0)
	print("far-side left target (%.3f, %.3f), heading %.0f deg" % [far.x, far.y, rad_to_deg(far.z)])
	_check("left branch on the far side is still to the driver's left", absf(far.y - BRANCH_Y) < 0.01)
	_check("far-side target is beyond the reef", far.x > 5.3)
	chooser.queue_free()

	print("\n== Auto-align, then score ==")
	var driver := DriverInput.new()
	driver.robot = robot
	driver.reef_align = ReefAlign.new(
			JSON.parse_string(FileAccess.get_file_as_string("res://data/fields/%d.json" % YEAR))["reefs"])
	root.add_child(driver)
	# Only its align target is under test; keep it from overwriting the command.
	driver.set_physics_process(false)
	robot.reset_pose(Vector2(2.2, BRANCH_Y + 0.7), 0.4)
	robot.superstructure.go_to(presets["l4_back"])
	var aligned := pieces.spawn(GamePiece.CORAL)
	aligned.global_position = robot.global_position + Vector3(0.0, 0.5, 0.0)
	robot.intake.load_piece(aligned)
	# Looking at this reef face means looking along +x, so the left branch is the
	# higher-y one; the back pose has the robot facing away, along -x.
	var goal := driver.align_target(1.0)
	for tick in int(2.5 * Engine.physics_ticks_per_second):
		var pose := Frc.from_godot(robot.global_position)
		robot.command = driver.reef_align.command(Vector2(pose.x, pose.y), robot.yaw(), goal)
		await physics_frame
	robot.command = Vector3.ZERO
	var arrived := Frc.from_godot(robot.global_position)
	var miss := Vector2(arrived.x - goal.x, arrived.y - goal.y).length()
	print("stopped %.3f m and %.1f deg from the scoring spot at (%.3f, %.3f)" % [
		miss, rad_to_deg(absf(angle_difference(robot.yaw(), goal.z))), goal.x, goal.y])
	_check("reaches the scoring spot", miss < 0.03 and absf(angle_difference(robot.yaw(), goal.z)) < deg_to_rad(2.0))
	_check("picked the left branch", absf(goal.y - BRANCH_Y) < 0.01)
	_check("turned its back to the reef", absf(angle_difference(robot.yaw(), PI)) < deg_to_rad(2.0))
	robot.intake.command = -2.0
	await _wait(0.1)
	robot.intake.command = 0.0
	await _wait(1.0)
	robot.superstructure.go_to(presets["stow"])
	await _wait(2.0)
	var hung := Frc.from_godot(aligned.global_position)
	print("coral rests at height %.3f m" % hung.z)
	_check("coral stays on the L4 branch after auto-align", hung.z > 1.6 and hung.z < 1.8)

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)


func _wait(seconds: float) -> void:
	for _i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		failures += 1
