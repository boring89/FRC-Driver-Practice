class_name MechanismJoint
extends RefCounted
## One powered joint of the superstructure (arm pivot, telescope, wrist): a
## group of motors through a gearbox driving a single degree of freedom, plus
## the position controller that would run on its motor controllers.
##
## Positions are radians for a revolute joint and metres for a prismatic one.

# Speed below which Coulomb friction is ramped linearly instead of switching sign.
const _FRICTION_EPS := 0.02
const _SUBSTEPS := 4

var name: String
var prismatic := false
var parent: MechanismJoint
## Joint frame in the robot's stowed pose, in the body's local coordinates.
var origin: Vector3
var axis: Vector3
var min_position: float
var max_position: float

var motor: DCMotor
var motor_count: int
## Motor radians per unit of joint travel.
var ratio: float
var stator_limit: float
var supply_limit: float
## Loss torque (or force) at the joint, including the motors' own.
var friction: float

var kp: float
var kd: float
var max_velocity: float
var max_acceleration: float

var position := 0.0
var velocity := 0.0
var goal := 0.0
var voltage := 0.0
var supply_current := 0.0

# Motion profile setpoint the controller is tracking toward `goal`.
var _ref_position := 0.0
var _ref_velocity := 0.0


static func from_config(cfg: Dictionary) -> MechanismJoint:
	var j := MechanismJoint.new()
	j.name = cfg["name"]
	j.prismatic = cfg["type"] == "prismatic"
	# Config gives revolute joints in degrees.
	var unit := 1.0 if j.prismatic else PI / 180.0
	var origin_m: Array = cfg["origin_m"]
	var axis_dir: Array = cfg["axis"]
	j.origin = Frc.to_godot(Vector3(origin_m[0], origin_m[1], origin_m[2]))
	j.axis = Frc.to_godot(Vector3(axis_dir[0], axis_dir[1], axis_dir[2])).normalized()
	var limits: Array = cfg["range"]
	j.min_position = float(limits[0]) * unit
	j.max_position = float(limits[1]) * unit

	j.motor = DCMotor.from_id(cfg["motor"])
	j.motor_count = cfg["motor_count"]
	j.ratio = cfg["gearing"]
	if j.prismatic:
		j.ratio /= float(cfg["meters_per_output_rad"])
	j.stator_limit = cfg["stator_limit_a"]
	j.supply_limit = cfg["supply_limit_a"]
	j.friction = float(cfg["friction"]) + j.motor.friction_torque * j.ratio * j.motor_count
	j.kp = float(cfg["kp_v"]) / unit
	j.kd = float(cfg["kd_v"]) / unit
	j.max_velocity = float(cfg["max_velocity"]) * unit
	j.max_acceleration = float(cfg["max_acceleration"]) * unit
	return j


## How far something riding on this joint has moved from the stowed pose when
## the joint is at `amount`.
func motion(amount: float) -> Transform3D:
	if prismatic:
		return Transform3D(Basis.IDENTITY, axis * amount)
	var rotation := Basis(axis, amount)
	return Transform3D(rotation, origin - rotation * origin)


func set_goal(value: float) -> void:
	goal = clampf(value, min_position, max_position)


func reset() -> void:
	position = 0.0
	velocity = 0.0
	goal = 0.0
	voltage = 0.0
	_ref_position = 0.0
	_ref_velocity = 0.0


## One loop of the position controller: trapezoidal profile toward the goal,
## PD on the tracking error, and feedforward for gravity and back-EMF.
## `load_force` is the generalised gravity force on the joint.
func update_controller(period: float, load_force: float) -> void:
	var remaining := goal - _ref_position
	var braking_speed := sqrt(2.0 * max_acceleration * absf(remaining))
	var wanted := signf(remaining) * minf(max_velocity, braking_speed)
	_ref_velocity = move_toward(_ref_velocity, wanted, max_acceleration * period)
	_ref_position += _ref_velocity * period
	if absf(goal - _ref_position) < 1e-4 and absf(_ref_velocity) <= max_acceleration * period:
		_ref_position = goal
		_ref_velocity = 0.0

	var hold := -load_force / (ratio * motor_count * motor.kt) * motor.resistance
	var back_emf := _ref_velocity * ratio * motor.ke
	voltage = clampf(
			kp * (_ref_position - position) + kd * (_ref_velocity - velocity) + hold + back_emf,
			-motor.nominal_voltage, motor.nominal_voltage)


## Advances the joint by `dt`. `inertia` and `load_force` are the generalised
## inertia and gravity force of everything the joint carries.
func step(dt: float, inertia: float, load_force: float, v_bat: float) -> void:
	var h := dt / _SUBSTEPS
	var total_inertia := inertia + motor_count * motor.rotor_inertia * ratio * ratio
	var supply_sum := 0.0
	for _i in _SUBSTEPS:
		var currents := motor.currents(voltage, velocity * ratio, v_bat, stator_limit, supply_limit)
		var drive := motor.kt * currents.x * ratio * motor_count
		var loss := friction * clampf(velocity / _FRICTION_EPS, -1.0, 1.0)
		var damping := 0.0
		if absf(velocity) < _FRICTION_EPS:
			damping = friction / _FRICTION_EPS
		velocity += h * (drive + load_force - loss) / (total_inertia + h * damping)
		position += h * velocity
		# Hard stops.
		if position < min_position or position > max_position:
			position = clampf(position, min_position, max_position)
			velocity = 0.0
		supply_sum += currents.y * motor_count
	supply_current = supply_sum / _SUBSTEPS
