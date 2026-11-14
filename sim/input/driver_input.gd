class_name DriverInput
extends Node
## Reads the driver's gamepad (or keyboard) and writes the robot's drive command.
## Left stick translates, right stick X rotates; W/A/S/D and Q/E on keyboard.

const DEADBAND := 0.1

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

	var keys := Vector2(
			float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)),
			float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D)))
	if keys != Vector2.ZERO:
		translate = keys.normalized()
	var key_turn := float(Input.is_physical_key_pressed(KEY_Q)) - float(Input.is_physical_key_pressed(KEY_E))
	if key_turn != 0.0:
		turn = key_turn

	translate = _shape(translate)
	turn = _shape(Vector2(turn, 0.0)).x
	robot.command = Vector3(translate.x * robot.max_speed, translate.y * robot.max_speed, turn * robot.max_omega)


## Radial deadband, then squared magnitude for finer control near centre.
func _shape(stick: Vector2) -> Vector2:
	var magnitude := minf(stick.length(), 1.0)
	if magnitude < DEADBAND:
		return Vector2.ZERO
	var scaled := (magnitude - DEADBAND) / (1.0 - DEADBAND)
	return stick / stick.length() * scaled * scaled
