class_name DriverInput
extends Node
## Reads the driver's gamepad (or keyboard) and writes the robot's drive command.
## Left stick translates, right stick X rotates; W/A/S/D and Q/E on keyboard.
## Mechanism presets are on the buttons named in the robot config and on the
## number keys, in the order the config lists them. Space or the right trigger
## runs the intake; F or the left trigger feeds the piece through and out.

const DEADBAND := 0.1
const _BUTTONS := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"lb": JOY_BUTTON_LEFT_SHOULDER, "rb": JOY_BUTTON_RIGHT_SHOULDER,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
}

var robot: SwerveRobot


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
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		var keys := Vector2(
				float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)),
				float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D)))
		if keys != Vector2.ZERO:
			translate = keys.normalized()
		var key_turn := float(Input.is_physical_key_pressed(KEY_Q)) - float(Input.is_physical_key_pressed(KEY_E))
		if key_turn != 0.0:
			turn = key_turn

	if robot.intake:
		var pull := Input.is_physical_key_pressed(KEY_SPACE)
		var push := Input.is_physical_key_pressed(KEY_F)
		if not pads.is_empty():
			pull = pull or Input.get_joy_axis(pads[0], JOY_AXIS_TRIGGER_RIGHT) > 0.5
			push = push or Input.get_joy_axis(pads[0], JOY_AXIS_TRIGGER_LEFT) > 0.5
		robot.intake.command = float(pull) - float(push)
		# G or pressing the right stick spits the piece back out of the mouth.
		if Input.is_physical_key_pressed(KEY_G) \
				or (not pads.is_empty() and Input.is_joy_button_pressed(pads[0], JOY_BUTTON_RIGHT_STICK)):
			robot.intake.command = -2.0

	translate = _shape(translate)
	turn = _shape(Vector2(turn, 0.0)).x
	robot.command = Vector3(translate.x * robot.max_speed, translate.y * robot.max_speed, turn * robot.max_omega)


func _unhandled_input(event: InputEvent) -> void:
	if robot == null or robot.superstructure == null:
		return
	var presets := robot.superstructure.presets
	var key := event as InputEventKey
	var button := event as InputEventJoypadButton
	if key and key.pressed and not key.echo:
		var index := key.physical_keycode - KEY_1
		if index >= 0 and index < presets.size():
			robot.superstructure.go_to(presets[index])
	elif button and button.pressed:
		for preset: Dictionary in presets:
			if _BUTTONS.get(preset.get("button", ""), -1) == button.button_index:
				robot.superstructure.go_to(preset)


## Radial deadband, then squared magnitude for finer control near centre.
func _shape(stick: Vector2) -> Vector2:
	var magnitude := minf(stick.length(), 1.0)
	if magnitude < DEADBAND:
		return Vector2.ZERO
	var scaled := (magnitude - DEADBAND) / (1.0 - DEADBAND)
	return stick / stick.length() * scaled * scaled
