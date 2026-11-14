class_name Frc
extends RefCounted
## FRC field frame <-> Godot conversions.
##
## FRC: x toward the red alliance wall, y to the left (seen from blue), z up,
## origin at the blue alliance's right-hand corner. Godot is y-up, so
## FRC (x, y, z) maps to Godot (x, z, -y). A robot's forward is its local +X.

const FIELD_LENGTH := 17.548
const FIELD_WIDTH := 8.052


static func to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


static func from_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y)


## Heading of a body in the field frame, counter-clockwise positive.
static func yaw_of(basis: Basis) -> float:
	var forward := basis.x
	return atan2(-forward.z, forward.x)
