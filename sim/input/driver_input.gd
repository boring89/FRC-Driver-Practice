class_name DriverInput
extends Node
## Reads the driver's gamepad and keyboard and runs the robot from them. The
## left stick translates and the right stick rotates; the keyboard and every
## button go through the actions bound in Settings. What a button means for
## this robot (which preset "L3" is, in coral or algae mode) comes from the
## robot config's "controls" block.

const DEADBAND := 0.1
const SPEED_SCALES := {"speed_1": 0.4, "speed_2": 0.7, "speed_3": 1.0}
const _LEVELS := ["l1", "l2", "l3", "l4"]

var robot: SwerveRobot
## Reef geometry of the field, for auto-align; null without it.
var reef_align: ReefAlign
var algae_mode := false
var speed_scale := 1.0

var _climb_step := 0


func _physics_process(_dt: float) -> void:
	if robot == null:
		return
	var translate := Vector2.ZERO
	var turn := 0.0
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var pad := pads[0]
		# Stick up is -Y and should drive away from the driver (+x); stick left is +y.
		translate = Vector2(-Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y), -Input.get_joy_axis(pad, JOY_AXIS_LEFT_X))
		turn = -Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X)

	# Typing in a text box must not drive the robot.
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if not typing:
		var keys := Input.get_vector("move_back", "move_forward", "move_right", "move_left")
		if keys != Vector2.ZERO:
			translate = keys.normalized()
		var key_turn := Input.get_axis("turn_right", "turn_left")
		if key_turn != 0.0:
			turn = key_turn

	if robot.intake:
		robot.intake.command = 0.0
		if Input.is_action_pressed("place") and not typing:
			# Some poses score by backing the piece out of the mouth instead.
			var reversed: Array = _controls().get("reverse_place", [])
			robot.intake.command = -2.0 if reversed.has(robot.superstructure.preset_name) else -1.0
		elif Input.is_action_pressed("intake") and not typing:
			robot.intake.command = 1.0

	translate = _shape(translate) * speed_scale
	turn = _shape(Vector2(turn, 0.0)).x * speed_scale
	robot.command = Vector3(translate.x * robot.max_speed, translate.y * robot.max_speed, turn * robot.max_omega)

	var side := float(Input.is_action_pressed("align_left")) - float(Input.is_action_pressed("align_right"))
	if reef_align and side != 0.0 and not typing:
		var pose := Frc.from_godot(robot.global_position)
		robot.command = reef_align.command(Vector2(pose.x, pose.y), robot.yaw(), align_target(side))


## Where auto-align would take the robot for the branch on `side` (+1 left, -1 right).
func align_target(side: float) -> Vector3:
	var pose := Frc.from_godot(robot.global_position)
	var standoffs: Dictionary = _controls().get("align_standoff_m", {})
	var standoff: float = standoffs.get(robot.superstructure.preset_name, standoffs.get("default", 0.0))
	var half_length := 0.5 * float(robot.config["frame_m"][0]) + float(robot.config["bumper_thickness_m"])
	return reef_align.target(Vector2(pose.x, pose.y), half_length, standoff, side)


func _unhandled_input(event: InputEvent) -> void:
	if robot == null or robot.superstructure == null:
		return
	var controls := _controls()
	var mode: Dictionary = controls.get("algae" if algae_mode else "coral", {})
	for level: String in _LEVELS:
		if event.is_action_pressed(level) and mode.has(level):
			robot.superstructure.go_to_named(mode[level])
	if event.is_action_pressed("intake") and mode.has("intake"):
		robot.superstructure.go_to_named(mode["intake"])
	elif event.is_action_pressed("special") and mode.has("special"):
		robot.superstructure.go_to_named(mode["special"])
	elif event.is_action_pressed("stow") and controls.has("stow"):
		robot.superstructure.go_to_named(controls["stow"])
		_climb_step = 0
	elif event.is_action_pressed("climb") and controls.has("climb"):
		# Each press moves on to the next stage of the climb.
		var stages: Array = controls["climb"]
		robot.superstructure.go_to_named(stages[mini(_climb_step, stages.size() - 1)])
		_climb_step += 1
	elif event.is_action_pressed("mode_toggle"):
		algae_mode = not algae_mode
	for action: String in SPEED_SCALES:
		if event.is_action_pressed(action):
			speed_scale = SPEED_SCALES[action]


func _controls() -> Dictionary:
	return robot.config.get("controls", {})


## Radial deadband, then squared magnitude for finer control near centre.
func _shape(stick: Vector2) -> Vector2:
	var magnitude := minf(stick.length(), 1.0)
	if magnitude < DEADBAND:
		return Vector2.ZERO
	var scaled := (magnitude - DEADBAND) / (1.0 - DEADBAND)
	return stick / stick.length() * scaled * scaled
