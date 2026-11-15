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

	print("\n== Human players feeding unasked ==")
	pieces.auto_feed_limit = 3
	pieces.feed_alliance = "blue"
	await _wait(8.0)
	var ready := pieces.loose_coral()
	var sides := {true: 0, false: 0}
	var own_half := true
	for loose: GamePiece in ready:
		var lies := Frc.from_godot(loose.global_position)
		sides[lies.y > 0.5 * Frc.FIELD_WIDTH] += 1
		own_half = own_half and lies.x < 0.5 * Frc.FIELD_LENGTH
	print("%d coral lying loose: %d by the left station, %d by the right" % [ready.size(), sides[true], sides[false]])
	_check("feeds up to the limit and stops", ready.size() == 3)
	_check("feeds from both of the alliance's stations", sides[true] > 0 and sides[false] > 0 and own_half)
	ready[0].queue_free()
	await _wait(0.5)
	_check("waits a moment before replacing a coral", pieces.loose_coral().size() == 2)
	await _wait(3.0)
	_check("replaces a coral that was taken", pieces.loose_coral().size() == 3)
	pieces.auto_feed_limit = 0

	print("\n== Intake ==")
	var stray := pieces.spawn(GamePiece.ALGAE)
	var algae_mouth: Array = robot.config["intake"]["pieces"]["algae"]["mouth_m"]
	stray.global_position = robot.global_transform * Frc.to_godot(Vector3(algae_mouth[0], algae_mouth[1], algae_mouth[2]))
	# Held still inside the robot, where it would otherwise be shoved out.
	stray.collision_layer = 0
	stray.collision_mask = 0
	stray.freeze = true
	robot.intake.wanted = GamePiece.CORAL
	robot.intake.command = 1.0
	await _wait(0.2)
	_check("leaves an algae alone when after coral", robot.intake.held == null)
	robot.intake.wanted = GamePiece.ALGAE
	await _wait(0.2)
	_check("takes the algae when after algae", robot.intake.held == stray)
	stray.queue_free()
	await _wait(0.1)
	robot.intake.wanted = GamePiece.CORAL
	var coral := pieces.spawn(GamePiece.CORAL)
	var mouth: Array = robot.config["intake"]["pieces"]["coral"]["mouth_m"]
	coral.global_position = robot.global_transform * Frc.to_godot(Vector3(mouth[0], 0.0, mouth[2] + 0.1))
	robot.intake.command = 1.0
	await _wait(0.5)
	_check("picks up a coral at its mouth", robot.intake.held == coral)
	robot.intake.command = 0.0
	await _wait(0.5)
	# Driving and spinning at once: the coral must not trail behind the intake.
	var hold: Array = robot.config["intake"]["pieces"]["coral"]["hold_m"]
	var hold_point := Frc.to_godot(Vector3(hold[0], hold[1], hold[2]))
	var trailing := 0.0
	robot.command = Vector3(3.0, 0.0, 4.0)
	for tick in Engine.physics_ticks_per_second:
		# As it is about to be drawn, not part-way through a physics tick.
		await process_frame
		trailing = maxf(trailing, coral.global_position.distance_to(robot.global_transform * hold_point))
	robot.command = Vector3.ZERO
	await _wait(1.0)
	print("carried coral strays at most %.3f m from its hold point while driving at up to %.1f m/s" % [
		trailing, 3.0])
	_check("carries it rigidly while driving", robot.intake.held == coral and trailing < 0.005)
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

	print("\n== End effector against game pieces ==")
	var half_length := 0.5 * float(robot.config["frame_m"][0]) + float(robot.config["bumper_thickness_m"])
	var ground_presets := {}
	for preset: Dictionary in robot.superstructure.presets:
		ground_presets[preset["name"]] = preset
	# An algae on the floor ahead, pushed along with the intake down in front of
	# the bumper and its rollers stopped, then again with the intake stowed.
	var gaps := {}
	for pose: String in ["ground_coral", "stow"]:
		robot.reset_pose(Vector2(8.0, 2.0), 0.0)
		robot.superstructure.go_to(ground_presets[pose])
		var ball := pieces.spawn(GamePiece.ALGAE)
		ball.global_position = Frc.to_godot(Vector3(9.3, 2.0, GamePiece.ALGAE_RADIUS))
		await _wait(1.5)
		_check("robot stands level in %s" % pose,
				robot.global_basis.y.dot(Vector3.UP) > 0.999 and absf(robot.global_position.y) < 0.01)
		robot.command = Vector3(0.7, 0.0, 0.0)
		await _wait(2.5)
		gaps[pose] = Frc.from_godot(ball.global_position).x - Frc.from_godot(robot.global_position).x - half_length
		robot.command = Vector3.ZERO
		ball.queue_free()
		await _wait(0.5)
	print("pushed algae's centre is %.2f m ahead of the bumper with the intake down, %.2f m with it stowed" % [
		gaps["ground_coral"], gaps["stow"]])
	_check("the intake pushes an algae along ahead of the bumper", gaps["ground_coral"] > gaps["stow"] + 0.05)
	# A coral lying across the robot's path, driven over with the rollers running.
	robot.reset_pose(Vector2(8.0, 2.0), 0.0)
	robot.superstructure.go_to(ground_presets["ground_coral"])
	var lying := pieces.spawn(GamePiece.CORAL)
	lying.global_transform = Transform3D(
			Basis(Vector3.RIGHT, PI / 2.0), Frc.to_godot(Vector3(9.3, 2.0, GamePiece.CORAL_RADIUS)))
	await _wait(1.5)
	robot.intake.command = 1.0
	robot.command = Vector3(1.0, 0.0, 0.0)
	await _wait(1.5)
	robot.command = Vector3.ZERO
	robot.intake.command = 0.0
	_check("picks a coral up off the floor by driving at it", robot.intake.held == lying)
	lying.queue_free()
	await _wait(0.1)
	robot.reset_pose(Vector2(8.0, 2.0), 0.0)
	robot.superstructure.go_to(ground_presets["ground_algae"])
	var rolling := pieces.spawn(GamePiece.ALGAE)
	rolling.global_position = Frc.to_godot(Vector3(9.3, 2.0, GamePiece.ALGAE_RADIUS))
	await _wait(1.5)
	robot.intake.wanted = GamePiece.ALGAE
	robot.intake.command = 1.0
	robot.command = Vector3(1.0, 0.0, 0.0)
	await _wait(1.5)
	robot.command = Vector3.ZERO
	robot.intake.command = 0.0
	robot.intake.wanted = GamePiece.CORAL
	_check("picks an algae up off the floor by driving at it", robot.intake.held == rolling)
	rolling.queue_free()
	robot.superstructure.go_to(ground_presets["stow"])
	await _wait(1.5)

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

	print("\n== Scoring ==")
	for piece in pieces.get_children():
		piece.queue_free()
	await _wait(0.1)
	var field: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/fields/%d.json" % YEAR))
	var game := Match.new(field, pieces)
	root.add_child(game)
	game.start(135.0)
	# A coral scored by the robot itself: nose-first on L4 of the blue reef.
	robot.reset_pose(Vector2(REEF_FACE_X - 0.425, BRANCH_Y), 0.0)
	await _wait(0.5)
	var counted := pieces.spawn(GamePiece.CORAL)
	counted.global_position = robot.global_position + Vector3(0.0, 0.5, 0.0)
	robot.intake.load_piece(counted)
	robot.superstructure.go_to(presets["l4"])
	await _wait(2.0)
	_check("a coral still in the intake scores nothing", game.scores["blue"] == 0)
	robot.intake.command = -1.0
	await _wait(0.1)
	robot.intake.command = 0.0
	await _wait(1.0)
	robot.superstructure.go_to(presets["stow"])
	await _wait(2.0)
	print("after an L4: blue %d, red %d" % [game.scores["blue"], game.scores["red"]])
	_check("L4 coral is worth 5", game.scores["blue"] == 5 and game.scores["red"] == 0)
	# Reaching back up to the branch with the intake running.
	robot.superstructure.go_to(presets["l4"])
	robot.intake.command = 1.0
	await _wait(2.0)
	robot.intake.command = 0.0
	_check("a coral on the reef is not taken back", counted.on_reef and robot.intake.held == null)
	robot.superstructure.go_to(presets["stow"])
	await _wait(2.0)
	_check("and still scores", game.scores["blue"] == 5)
	# The rest placed by hand: L3 and L2 on the same blue branch column, a
	# coral in the red reef's trough, algae in the net and through a processor.
	for spot: Vector3 in [
		Vector3(REEF_FACE_X + 0.135, BRANCH_Y, 1.105), Vector3(REEF_FACE_X + 0.135, BRANCH_Y, 0.705),
		Vector3(13.059 + 0.5, 4.026, 0.5),
	]:
		var placed := pieces.spawn(GamePiece.CORAL)
		placed.global_position = Frc.to_godot(spot)
		placed.freeze = true
	var netted := pieces.spawn(GamePiece.ALGAE)
	netted.global_position = Frc.to_godot(Vector3(0.5 * Frc.FIELD_LENGTH, 6.0, 2.0))
	netted.freeze = true
	var processed := pieces.spawn(GamePiece.ALGAE)
	processed.global_position = Frc.to_godot(Vector3(5.988, -0.3, 0.3))
	processed.freeze = true
	await _wait(0.3)
	print("after placing the rest: blue %d, red %d" % [game.scores["blue"], game.scores["red"]])
	_check("blue has L4 + L3 + L2 + net + processor", game.scores["blue"] == 5 + 4 + 3 + 4 + 6)
	_check("red has one trough coral", game.scores["red"] == 2)
	_check("processed algae leaves the field", not is_instance_valid(processed) or processed.is_queued_for_deletion())
	counted.global_position += Vector3(0.0, 0.0, 2.0)
	counted.freeze = true
	await _wait(0.3)
	_check("a coral knocked off its branch stops counting", game.scores["blue"] == 4 + 3 + 4 + 6)
	game.time_left = 0.2
	await _wait(0.5)
	_check("the match ends when the clock runs out", not game.running and game.time_left == 0.0)
	game.start(135.0, true)
	await _wait(0.5)
	_check("free practice counts up and does not end", game.running and game.time_left > 0.4 and not game.in_endgame())
	game.queue_free()

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
	# A red driver looks the other way down the field, so their left is lower y.
	robot.driver_heading = PI
	_check("left and right swap for the red driver", absf(chooser.align_target(1.0).y - (BRANCH_Y - 2.0 * 0.1643)) < 0.01)
	robot.driver_heading = 0.0

	print("\n== Algae off the reef ==")
	pieces.reset()
	await _wait(0.2)
	var held_coral := pieces.spawn(GamePiece.CORAL)
	robot.reset_pose(Vector2(2.6, 4.026), 0.0)
	robot.intake.load_piece(held_coral)
	chooser._unhandled_input(_press("l3"))
	_check("with a coral in hand L3 is the coral pose", not chooser.algae_mode and robot.superstructure.preset_name == "l3")
	held_coral.queue_free()
	await _wait(0.1)
	chooser._unhandled_input(_press("l2"))
	_check("with empty hands L2 switches to algae mode", chooser.algae_mode and robot.superstructure.preset_name == "l2_algae_front")
	chooser._unhandled_input(_press("stow"))
	_check("stowing before taking the algae switches back", not chooser.algae_mode)
	# The algae on this face of the blue reef sits at L3 height.
	chooser._unhandled_input(_press("l3"))
	var middle := chooser.align_target(1.0)
	_check("auto-align goes to the middle of the face for an algae", absf(middle.y - 4.026) < 0.01)
	for tick in int(3.0 * Engine.physics_ticks_per_second):
		chooser._physics_process(0.0)
		robot.command = chooser.align_command(1.0)
		await physics_frame
	robot.command = Vector3.ZERO
	var taken := robot.intake.held
	_check("takes the reef's algae without the intake button", taken != null and taken.kind == GamePiece.ALGAE)
	_check("stays in algae mode while carrying it", chooser.algae_mode)
	# Up to the barge from the blue side, under the blue alliance's net.
	var net_game := Match.new(field, pieces)
	root.add_child(net_game)
	net_game.start(135.0, true)
	robot.reset_pose(Vector2(0.5 * Frc.FIELD_LENGTH - 0.75, 6.0), 0.0)
	chooser._unhandled_input(_press("l4"))
	_check("L4 is then the net pose", robot.superstructure.preset_name == "net_algae")
	await _wait(2.5)
	Input.action_press("place")
	for tick in 10:
		chooser._physics_process(0.0)
		await physics_frame
	Input.action_release("place")
	chooser._physics_process(0.0)
	_check("scoring the algae switches back to coral mode", robot.intake.held == null and not chooser.algae_mode)
	robot.intake.command = 0.0
	await _wait(3.0)
	var netted_at := Frc.from_godot(taken.global_position)
	print("algae thrown from the net pose lies at (%.2f, %.2f, %.2f): blue %d" % [
		netted_at.x, netted_at.y, netted_at.z, net_game.scores["blue"]])
	_check("the algae lands in the net and scores 4", net_game.scores["blue"] == 4)
	net_game.queue_free()
	robot.superstructure.go_to(presets["stow"])
	await _wait(1.5)
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
		robot.command = driver.align_command(1.0)
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
	# Straight back to intaking, with the coral still at the mouth it left by.
	robot.intake.command = 1.0
	await _wait(1.0)
	robot.intake.command = 0.0
	_check("the coral just placed is not taken back", robot.intake.held == null)
	robot.superstructure.go_to(presets["stow"])
	await _wait(2.0)
	var hung := Frc.from_godot(aligned.global_position)
	print("coral rests at height %.3f m" % hung.z)
	_check("coral stays on the L4 branch after auto-align", hung.z > 1.6 and hung.z < 1.8)

	# The same from the red driver's side of the field: their commands are
	# turned half a circle, and auto-align has to allow for it.
	robot.driver_heading = PI
	robot.superstructure.go_to(presets["l4"])
	robot.reset_pose(Vector2(2.2, BRANCH_Y - 0.9), -0.5)
	var red_goal := driver.align_target(1.0)
	for tick in int(2.5 * Engine.physics_ticks_per_second):
		robot.command = driver.align_command(1.0)
		await physics_frame
	robot.command = Vector3.ZERO
	var red_arrived := Frc.from_godot(robot.global_position)
	var red_miss := Vector2(red_arrived.x - red_goal.x, red_arrived.y - red_goal.y).length()
	print("as the red driver: stopped %.3f m from the scoring spot" % red_miss)
	_check("auto-align works from the red driver's frame", red_miss < 0.03)
	robot.driver_heading = 0.0

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(failures)


func _press(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _wait(seconds: float) -> void:
	for _i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		failures += 1
