class_name SwerveModule
extends RefCounted
## One swerve module: drive and steer motor dynamics plus the tire contact model.
##
## Works in the chassis ground-plane frame (x forward, y left). The chassis is
## much heavier than the wheel, so each physics tick holds the chassis velocity
## fixed and sub-steps the fast wheel and steer dynamics against it.

# Speeds below which Coulomb friction is ramped linearly instead of switching sign.
const _WHEEL_FRICTION_EPS := 0.5
const _STEER_FRICTION_EPS := 0.2
# Wheel speed (m/s) at which rolling halves the scrub torque on the steer axis.
const _SCRUB_FADE := 0.5

# --- Configuration ---
var position: Vector2
var wheel_radius: float

var drive_motor: DCMotor
var drive_gearing: float
var drive_stator_limit: float
var drive_supply_limit: float
## Wheel plus reflected rotor inertia, at the wheel.
var drive_inertia: float
## Drivetrain plus motor loss torque, at the wheel.
var drive_friction: float

var steer_motor: DCMotor
var steer_gearing: float
var steer_stator_limit: float
var steer_supply_limit: float
var steer_inertia: float
var steer_friction: float
var steer_kp: float
var steer_kd: float

var mu_static: float
var mu_kinetic: float
var stribeck_speed: float
## Slip speed at which the tire reaches peak friction: the larger of this floor
## and `slip_fraction` of the contact patch speed.
var slip_speed_min: float
var slip_fraction: float
var scrub_radius: float

# --- Commands from the drive controller ---
var target_angle := 0.0
var drive_voltage := 0.0

# --- State ---
var steer_angle := 0.0
var steer_velocity := 0.0
var wheel_omega := 0.0
## Accumulated wheel rotation, for visuals only.
var wheel_spin := 0.0

# --- Telemetry from the last tick ---
var normal_force := 0.0
var slip_speed := 0.0
var force := Vector2.ZERO
var drive_current := 0.0
var supply_current := 0.0


static func from_config(swerve: Dictionary, index: int) -> SwerveModule:
	var m := SwerveModule.new()
	var pos: Array = swerve["module_positions_m"][index]
	m.position = Vector2(pos[0], pos[1])
	m.wheel_radius = swerve["wheel_radius_m"]

	var drive: Dictionary = swerve["drive"]
	m.drive_motor = DCMotor.from_id(drive["motor"])
	m.drive_gearing = drive["gearing"]
	m.drive_stator_limit = drive["stator_limit_a"]
	m.drive_supply_limit = drive["supply_limit_a"]
	m.drive_inertia = float(swerve["wheel_inertia_kgm2"]) \
			+ m.drive_motor.rotor_inertia * m.drive_gearing * m.drive_gearing
	m.drive_friction = float(drive["friction_nm"]) + m.drive_motor.friction_torque * m.drive_gearing

	var steer: Dictionary = swerve["steer"]
	m.steer_motor = DCMotor.from_id(steer["motor"])
	m.steer_gearing = steer["gearing"]
	m.steer_stator_limit = steer["stator_limit_a"]
	m.steer_supply_limit = steer["supply_limit_a"]
	m.steer_inertia = float(steer["inertia_kgm2"]) \
			+ m.steer_motor.rotor_inertia * m.steer_gearing * m.steer_gearing
	m.steer_friction = float(steer["friction_nm"]) + m.steer_motor.friction_torque * m.steer_gearing
	m.steer_kp = steer["kp_v_per_rad"]
	m.steer_kd = steer["kd_v_per_radps"]

	var tire: Dictionary = swerve["tire"]
	m.mu_static = tire["mu_static"]
	m.mu_kinetic = tire["mu_kinetic"]
	m.stribeck_speed = tire["stribeck_speed_mps"]
	m.slip_speed_min = tire["slip_speed_min_mps"]
	m.slip_fraction = tire["slip_fraction"]
	m.scrub_radius = tire["scrub_radius_m"]
	return m


## Theoretical wheel surface speed with the drive motor at free speed.
func free_speed() -> float:
	return drive_motor.free_speed / drive_gearing * wheel_radius


func reset() -> void:
	steer_angle = 0.0
	steer_velocity = 0.0
	wheel_omega = 0.0
	target_angle = 0.0
	drive_voltage = 0.0


## Advances the module by `dt`. (vx, vy) is the contact patch velocity relative
## to the ground in the chassis frame and `normal` the load on the tire.
## Returns the average tire force on the chassis in the same frame.
func step(dt: float, substeps: int, vx: float, vy: float, normal: float, v_bat: float) -> Vector2:
	var h := dt / substeps
	var v0 := maxf(slip_speed_min, slip_fraction * sqrt(vx * vx + vy * vy))
	var k_linear := mu_static * normal / v0
	var force_sum := Vector2.ZERO
	var supply_sum := 0.0
	var stator_sum := 0.0
	var slip_sum := 0.0

	for _i in substeps:
		var c := cos(steer_angle)
		var s := sin(steer_angle)
		var v_long := vx * c + vy * s
		var v_lat := -vx * s + vy * c

		# Tire: friction opposes slip, rising linearly to its peak at v0 and
		# then falling from static toward kinetic as the tire slides.
		var slip_long := wheel_omega * wheel_radius - v_long
		var slip_lat := -v_lat
		var slip := sqrt(slip_long * slip_long + slip_lat * slip_lat)
		var f_long := 0.0
		var f_lat := 0.0
		# d(f_long)/d(slip_long), used to integrate the stiff wheel dynamics implicitly.
		var k_long := 0.0
		if normal > 0.0 and slip > 1e-9:
			if slip < v0:
				f_long = k_linear * slip_long
				f_lat = k_linear * slip_lat
				k_long = k_linear
			else:
				var mu := mu_kinetic + (mu_static - mu_kinetic) * exp(-(slip - v0) / stribeck_speed)
				var f_per_slip := mu * normal / slip
				f_long = f_per_slip * slip_long
				f_lat = f_per_slip * slip_lat
				k_long = f_per_slip * slip_lat * slip_lat / (slip * slip)

		# Drive: motor torque through the gearbox against tire reaction and losses.
		var drive := drive_motor.currents(
				drive_voltage, wheel_omega * drive_gearing, v_bat, drive_stator_limit, drive_supply_limit)
		var drive_loss := drive_friction * clampf(wheel_omega / _WHEEL_FRICTION_EPS, -1.0, 1.0)
		var drive_damping := wheel_radius * wheel_radius * k_long
		if absf(wheel_omega) < _WHEEL_FRICTION_EPS:
			drive_damping += drive_friction / _WHEEL_FRICTION_EPS
		var drive_torque := drive_motor.kt * drive.x * drive_gearing - drive_loss - f_long * wheel_radius
		wheel_omega += h * drive_torque / (drive_inertia + h * drive_damping)
		wheel_spin += h * wheel_omega

		# Steer: onboard position PD, resisted by the tire scrubbing on the carpet.
		var steer_error := angle_difference(steer_angle, target_angle)
		var steer_voltage := steer_kp * steer_error - steer_kd * steer_velocity
		var steer := steer_motor.currents(
				steer_voltage, steer_velocity * steer_gearing, v_bat, steer_stator_limit, steer_supply_limit)
		var scrub := mu_static * normal * scrub_radius / (1.0 + absf(v_long) / _SCRUB_FADE)
		var steer_resist := steer_friction + scrub
		var steer_loss := steer_resist * clampf(steer_velocity / _STEER_FRICTION_EPS, -1.0, 1.0)
		var steer_damping := 0.0
		if absf(steer_velocity) < _STEER_FRICTION_EPS:
			steer_damping = steer_resist / _STEER_FRICTION_EPS
		var steer_torque := steer_motor.kt * steer.x * steer_gearing - steer_loss
		steer_velocity += h * steer_torque / (steer_inertia + h * steer_damping)
		steer_angle = wrapf(steer_angle + h * steer_velocity, -PI, PI)

		force_sum += Vector2(f_long * c - f_lat * s, f_long * s + f_lat * c)
		supply_sum += drive.y + steer.y
		stator_sum += drive.x
		slip_sum += slip

	normal_force = normal
	force = force_sum / substeps
	supply_current = supply_sum / substeps
	drive_current = stator_sum / substeps
	slip_speed = slip_sum / substeps
	return force
