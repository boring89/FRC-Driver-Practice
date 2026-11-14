class_name DCMotor
extends RefCounted
## DC motor model built from the same constants as WPILib's DCMotor.

var id: String
var nominal_voltage: float
var stall_torque: float
var stall_current: float
var free_current: float
## rad/s
var free_speed: float
var rotor_inertia: float
var resistance: float
## N*m per amp
var kt: float
## Back-EMF constant, volts per rad/s
var ke: float
## Internal loss torque at the shaft; makes the unloaded motor settle at free speed.
var friction_torque: float

static var _catalog: Dictionary = {}


static func from_id(motor_id: String) -> DCMotor:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/motors.json"))
	assert(_catalog.has(motor_id), "Unknown motor: " + motor_id)
	var d: Dictionary = _catalog[motor_id]
	var m := DCMotor.new()
	m.id = motor_id
	m.nominal_voltage = d["nominal_voltage"]
	m.stall_torque = d["stall_torque_nm"]
	m.stall_current = d["stall_current_a"]
	m.free_current = d["free_current_a"]
	m.free_speed = float(d["free_speed_rpm"]) * TAU / 60.0
	m.rotor_inertia = d["rotor_inertia_kgm2"]
	m.resistance = m.nominal_voltage / m.stall_current
	m.kt = m.stall_torque / m.stall_current
	m.ke = (m.nominal_voltage - m.resistance * m.free_current) / m.free_speed
	m.friction_torque = m.kt * m.free_current
	return m


## Currents when the controller asks for `voltage` at shaft speed `omega` (rad/s),
## after the stator and supply current limits. x = stator amps (signed, sets
## torque), y = supply amps drawn from the battery (negative while regenerating).
func currents(voltage: float, omega: float, v_bat: float, stator_limit: float, supply_limit: float) -> Vector2:
	var v := clampf(voltage, -v_bat, v_bat)
	var bemf := omega * ke
	var stator := clampf((v - bemf) / resistance, -stator_limit, stator_limit)
	var dir := signf(stator)
	var mag := absf(stator)
	# Back-EMF seen in the direction of current flow.
	var e := dir * bemf
	var supply := mag * (mag * resistance + e) / v_bat
	if supply > supply_limit:
		mag = (-e + sqrt(e * e + 4.0 * resistance * supply_limit * v_bat)) / (2.0 * resistance)
		supply = supply_limit
	return Vector2(dir * mag, supply)
