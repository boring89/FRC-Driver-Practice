class_name CameraRig
extends Camera3D
## Switchable views of the robot: from the driver station, following behind it,
## or straight down.

enum Mode { DRIVER_STATION, FOLLOW, TOP }

const MODE_NAMES := ["Driver station", "Follow", "Top"]
# Driver's eyes behind the middle blue driver station, in field coordinates.
const _STATION_EYE := Vector3(-0.8, 0.5 * Frc.FIELD_WIDTH, 1.65)
const _FIELD_CENTER := Vector3(0.5 * Frc.FIELD_LENGTH, 0.5 * Frc.FIELD_WIDTH, 0.3)

var mode := Mode.DRIVER_STATION
var target: Node3D


func cycle() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode


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
