class_name CameraRig
extends Camera3D
## Switchable views of the robot: from the driver station, following behind it,
## straight down, or orbiting it with the mouse (right-drag to turn, wheel to zoom).

enum Mode { DRIVER_STATION, FOLLOW, TOP, ORBIT }

const MODE_NAMES := ["Driver station", "Follow", "Top", "Orbit"]
const _ORBIT_SENSITIVITY := 0.008
# Driver's eyes behind the middle blue driver station, in field coordinates.
const _STATION_EYE := Vector3(-0.8, 0.5 * Frc.FIELD_WIDTH, 1.65)
const _FIELD_CENTER := Vector3(0.5 * Frc.FIELD_LENGTH, 0.5 * Frc.FIELD_WIDTH, 0.3)

var mode := Mode.DRIVER_STATION
var target: Node3D

var _orbit_yaw := deg_to_rad(70.0)
var _orbit_pitch := deg_to_rad(15.0)
var _orbit_distance := 3.5


func cycle() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.ORBIT:
		return
	var motion := event as InputEventMouseMotion
	var button := event as InputEventMouseButton
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_orbit_yaw += motion.relative.x * _ORBIT_SENSITIVITY
		_orbit_pitch = clampf(_orbit_pitch + motion.relative.y * _ORBIT_SENSITIVITY, -0.2, 1.5)
	elif button and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_orbit_distance = maxf(0.8, _orbit_distance * 0.9)
	elif button and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_orbit_distance = minf(15.0, _orbit_distance / 0.9)


func _process(dt: float) -> void:
	if target == null:
		return
	var robot := target.global_position
	match mode:
		Mode.DRIVER_STATION:
			fov = 60.0
			global_position = Frc.to_godot(_STATION_EYE)
			look_at(Frc.to_godot(_FIELD_CENTER).lerp(robot, 0.5), Vector3.UP)
		Mode.FOLLOW:
			fov = 70.0
			var desired := robot + Vector3(-3.2, 2.4, 0.0)
			global_position = global_position.lerp(desired, 1.0 - exp(-8.0 * dt))
			look_at(robot + Vector3(0.8, 0.2, 0.0), Vector3.UP)
		Mode.TOP:
			fov = 70.0
			global_position = robot + Vector3(0.0, 9.0, 0.0)
			look_at(robot, Vector3.RIGHT)
		Mode.ORBIT:
			fov = 60.0
			var focus := robot + Vector3(0.0, 0.9, 0.0)
			var direction := Vector3(
					cos(_orbit_pitch) * cos(_orbit_yaw), sin(_orbit_pitch), cos(_orbit_pitch) * sin(_orbit_yaw))
			global_position = focus + direction * _orbit_distance
			look_at(focus, Vector3.UP)
