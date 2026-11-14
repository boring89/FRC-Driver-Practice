class_name ReefAlign
extends RefCounted
## Auto-align: drives the robot to the scoring spot in front of the nearest
## reef face, lined up with that face's left or right branch, nose or tail to
## the reef.

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


## Whether a robot at `position` has its front, rather than its back, toward
## the nearest reef.
func faces_reef(position: Vector2, heading: float) -> bool:
	return Vector2.from_angle(heading).dot(_nearest(position) - position) >= 0.0


## Field pose (x, y, heading) to score from: bumper `standoff` back from the
## nearest reef face, with the robot's back to the reef if `backward`. `side`
## picks the branch: +1 for the one further to the left as the driver, looking
## along `driver_heading`, sees the field, -1 for the other. On the far side
## of a reef that is the opposite of left and right for someone facing the face.
func target(
		position: Vector2, half_length: float, standoff: float,
		side: float, backward: bool, driver_heading: float) -> Vector3:
	var reef := _nearest(position)
	# The six faces look out every 60 degrees; take the one the robot is in front of.
	var bearing: float = snappedf((position - reef).angle(), PI / 3.0)
	var outward := Vector2.from_angle(bearing)
	var along_face := Vector2.from_angle(bearing + PI / 2.0)
	if along_face.dot(Vector2.from_angle(driver_heading + PI / 2.0)) < 0.0:
		along_face = -along_face
	var spot := reef + outward * (_face_distance + half_length + standoff) + along_face * _branch_offset * side
	return Vector3(spot.x, spot.y, bearing if backward else wrapf(bearing + PI, -PI, PI))


func _nearest(position: Vector2) -> Vector2:
	var reef: Vector2 = _centers[0]
	for center: Vector2 in _centers:
		if position.distance_to(center) < position.distance_to(reef):
			reef = center
	return reef


## Field-relative drive command (vx, vy, omega) that takes the robot to `goal`.
func command(position: Vector2, heading: float, goal: Vector3) -> Vector3:
	var velocity := ((Vector2(goal.x, goal.y) - position) * _POSITION_GAIN).limit_length(_MAX_SPEED)
	var omega := clampf(angle_difference(heading, goal.z) * _HEADING_GAIN, -_MAX_OMEGA, _MAX_OMEGA)
	return Vector3(velocity.x, velocity.y, omega)
