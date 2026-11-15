class_name Intake
extends RefCounted
## End effector that picks up, carries and ejects game pieces. Rollers gripping
## a piece are not simulated: a piece that reaches the mouth while the intake
## runs is taken hold of and carried at a fixed place on the intake's link
## until it is ejected back into the physics world.

# How quickly a captured piece is drawn from where it was to where it is held.
const _DRAW_IN_RATE := 20.0
# A released piece ignores the robot for at least this long, and until it is
# this far from where it was carried: a scored coral sits right where the
# intake still is, and must not be knocked off as the arm withdraws.
const _CLEARANCE_TIME := 0.4
const _CLEARANCE_DISTANCE := 0.35

## +1 runs the rollers inward, -1 feeds the piece on through and out the far
## side, -2 reverses it back out of the mouth, 0 stops.
var command := 0.0
## The kind of piece the driver is after; the intake leaves the other kind
## alone. Empty takes whatever reaches the mouth.
var wanted := ""
var held: GamePiece

var _link: String
# Per kind of piece, in the robot's stowed pose (body-local): where it is
# carried (its local Y pointing the way it leaves when fed through), and the
# mouth it enters by with how close it has to come.
var _hold := {}
var _mouth := {}
var _reach := {}
var _eject_speed := {}
var _released: GamePiece
var _clearance := 0.0


func _init(cfg: Dictionary) -> void:
	_link = cfg["link"]
	var pieces: Dictionary = cfg["pieces"]
	for kind: String in pieces:
		var origin: Array = pieces[kind]["hold_m"]
		var axis: Array = pieces[kind]["axis"]
		var mouth: Array = pieces[kind]["mouth_m"]
		_mouth[kind] = Frc.to_godot(Vector3(mouth[0], mouth[1], mouth[2]))
		_reach[kind] = pieces[kind]["reach_m"]
		var direction := Frc.to_godot(Vector3(axis[0], axis[1], axis[2])).normalized()
		_hold[kind] = Transform3D(
				Basis(Quaternion(Vector3.UP, direction)), Frc.to_godot(Vector3(origin[0], origin[1], origin[2])))
		_eject_speed[kind] = pieces[kind]["eject_mps"]


## Puts `piece` straight into the intake, as when a robot is preloaded.
func load_piece(piece: GamePiece) -> void:
	if held != null or not _hold.has(piece.kind):
		return
	held = piece
	piece.grab()


func step(dt: float, robot: SwerveRobot) -> void:
	var link_pose := robot.global_transform * robot.superstructure.link_pose(_link)
	if _released != null:
		_clearance -= dt
		if not is_instance_valid(_released):
			_released = null
		elif _clearance <= 0.0:
			var carried_at := link_pose * (_hold[_released.kind] as Transform3D).origin
			if _released.global_position.distance_to(carried_at) > _CLEARANCE_DISTANCE:
				robot.remove_collision_exception_with(_released)
				_released = null

	if held != null and not is_instance_valid(held):
		held = null
	if held != null:
		var carried := link_pose * (_hold[held.kind] as Transform3D)
		held.global_transform = held.global_transform.interpolate_with(carried, 1.0 - exp(-_DRAW_IN_RATE * dt))
		if command < 0.0:
			_eject(robot)
	elif command > 0.0:
		for piece: GamePiece in robot.get_tree().get_nodes_in_group(GamePiece.GROUP):
			if piece.held or not _hold.has(piece.kind):
				continue
			if wanted != "" and piece.kind != wanted:
				continue
			# A coral placed on a reef stays there, and so does the piece just let
			# go of, which is still right at the mouth.
			if piece.on_reef or piece == _released:
				continue
			var mouth := link_pose * (_mouth[piece.kind] as Vector3)
			if piece.global_position.distance_to(mouth) < float(_reach[piece.kind]):
				load_piece(piece)
				break


## Lets go of the held piece, pushing it out along the axis it is held by:
## on through the intake, or back out of the mouth when reversing.
func _eject(robot: SwerveRobot) -> void:
	var way := -1.0 if command < -1.5 else 1.0
	var piece := held
	held = null
	var offset := piece.global_position - robot.global_transform * robot.center_of_mass
	var carried_velocity := robot.linear_velocity + robot.angular_velocity.cross(offset)
	if _released != null and is_instance_valid(_released):
		robot.remove_collision_exception_with(_released)
	robot.add_collision_exception_with(piece)
	_released = piece
	_clearance = _CLEARANCE_TIME
	piece.release(carried_velocity + piece.global_basis.y * way * float(_eject_speed[piece.kind]))
