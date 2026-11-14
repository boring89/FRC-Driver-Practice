class_name ReefAlign
extends RefCounted
## Auto-align: drives the robot to the scoring spot in front of the nearest
## reef face, lined up with that face's left or right branch.

const _POSITION_GAIN := 5.0
const _HEADING_GAIN := 8.0
const _MAX_SPEED := 3.0
const _MAX_OMEGA := 6.0

var _centers: Array = []
var _face_distance := 0.0
var _branch_offset := 0.0


func _init(reefs: Dictionary) -> void:
	for center: Array in reefs["centers_m"]:
		_centers.append(Vector2(center[0], center[1]))
	_face_distance = reefs["face_distance_m"]
	_branch_offset = reefs["branch_offset_m"]


## Field pose (x, y, heading) to score from: bumper `standoff` back from the
## nearest reef face, at the branch to the robot's left (`side` +1) or right (-1).
func target(position: Vector2, half_length: float, standoff: float, side: float) -> Vector3:
	var reef: Vector2 = _centers[0]
	for center: Vector2 in _centers:
		if position.distance_to(center) < position.distance_to(reef):
			reef = center
	# The six faces look out every 60 degrees; take the one the robot is in front of.
	var bearing: float = snappedf((position - reef).angle(), PI / 3.0)
	var outward := Vector2.from_angle(bearing)
	var heading := wrapf(bearing + PI, -PI, PI)
	var robot_left := Vector2.from_angle(heading + PI / 2.0)
	var spot := reef + outward * (_face_distance + half_length + standoff) + robot_left * _branch_offset * side
	return Vector3(spot.x, spot.y, heading)


## Field-relative drive command (vx, vy, omega) that takes the robot to `goal`.
func command(position: Vector2, heading: float, goal: Vector3) -> Vector3:
	var velocity := ((Vector2(goal.x, goal.y) - position) * _POSITION_GAIN).limit_length(_MAX_SPEED)
	var omega := clampf(angle_difference(heading, goal.z) * _HEADING_GAIN, -_MAX_OMEGA, _MAX_OMEGA)
	return Vector3(velocity.x, velocity.y, omega)
