class_name SwerveController
extends RefCounted
## Stand-in for the robot's drive code: turns a chassis speed request into
## module angle targets and drive voltages, the way a typical WPILib/CTRE
## swerve teleop does (discretize, inverse kinematics, desaturate, optimize,
## cosine compensation, voltage feedforward).

# Below this wheel speed request the module keeps its angle instead of snapping to zero.
const _HOLD_SPEED := 0.02

var modules: Array[SwerveModule]
## Robot code loop period.
var period := 0.02
## Wheel speed the kinematics may ask for before every module is scaled back.
var max_wheel_speed: float
## Volts per m/s feedforward.
var drive_kv: float
## Volts per m/s of wheel speed error; 0 gives open-loop voltage control.
var drive_kp := 0.0


func _init(robot_modules: Array[SwerveModule], kp: float) -> void:
	modules = robot_modules
	max_wheel_speed = modules[0].free_speed()
	drive_kv = modules[0].drive_motor.nominal_voltage / max_wheel_speed
	drive_kp = kp


## `speeds` is (vx, vy, omega) in m/s and rad/s. When field-relative, `heading`
## is the robot's yaw measured from the direction the driver calls forward.
func update(speeds: Vector3, field_relative: bool, heading: float) -> void:
	var vx := speeds.x
	var vy := speeds.y
	var omega := speeds.z
	if field_relative:
		var c := cos(heading)
		var s := sin(heading)
		var fx := vx
		vx = fx * c + vy * s
		vy = -fx * s + vy * c

	# Compensate for the robot turning during one loop (ChassisSpeeds.discretize).
	var dtheta := omega * period
	var half := 0.5 * dtheta
	var a := 1.0 - dtheta * dtheta / 12.0
	if absf(dtheta) > 1e-4:
		a = -(half * sin(dtheta)) / (cos(dtheta) - 1.0)
	var dx := vx
	vx = dx * a + vy * half
	vy = vy * a - dx * half

	var wheel_speeds: Array[float] = []
	var wheel_angles: Array[float] = []
	var fastest := 0.0
	for m in modules:
		var wx := vx - omega * m.position.y
		var wy := vy + omega * m.position.x
		var speed := sqrt(wx * wx + wy * wy)
		wheel_speeds.append(speed)
		wheel_angles.append(atan2(wy, wx))
		fastest = maxf(fastest, speed)
	var scale := 1.0
	if fastest > max_wheel_speed:
		scale = max_wheel_speed / fastest

	for i in modules.size():
		var m := modules[i]
		var speed := wheel_speeds[i] * scale
		if speed < _HOLD_SPEED:
			speed = 0.0
		else:
			var angle := wheel_angles[i]
			# Never turn the module more than 90 degrees; reverse the wheel instead.
			var error := angle_difference(m.steer_angle, angle)
			if absf(error) > PI / 2.0:
				angle = wrapf(angle + PI, -PI, PI)
				speed = -speed
				error = angle_difference(m.steer_angle, angle)
			m.target_angle = angle
			speed *= cos(error)
		var measured := m.wheel_omega * m.wheel_radius
		m.drive_voltage = clampf(drive_kv * speed + drive_kp * (speed - measured), -12.0, 12.0)
