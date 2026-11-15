class_name GamePiece
extends RigidBody3D
## A 2025 game piece: a CORAL (a length of PVC pipe, hollow so reef branches
## pass through it) or an ALGAE (a large ball). A coral's axis is its local Y.

const CORAL := "coral"
const ALGAE := "algae"
const GROUP := "game_pieces"

const CORAL_LENGTH := 0.3016
const CORAL_RADIUS := 0.05715
# Thicker than the real 6 mm wall so fast contacts cannot slip through it.
const CORAL_WALL := 0.014
const CORAL_MASS := 0.65
const ALGAE_RADIUS := 0.2064
const ALGAE_MASS := 0.6
const _RING_SEGMENTS := 10
const _TUBE_SIDES := 24

var kind: String
## True while a robot's intake is carrying the piece.
var held := false
## True while a coral sits on a reef, on a branch or in the trough. Kept up to
## date by the Match; intakes leave such a coral where it is.
var on_reef := false

static var _coral_mesh: ArrayMesh


static func create(piece_kind: String) -> GamePiece:
	var piece := GamePiece.new()
	piece.kind = piece_kind
	piece.add_to_group(GROUP)
	piece.continuous_cd = true
	var material := PhysicsMaterial.new()
	var surface := StandardMaterial3D.new()
	var visual := MeshInstance3D.new()
	if piece_kind == CORAL:
		piece.mass = CORAL_MASS
		material.friction = 0.25
		material.bounce = 0.2
		surface.albedo_color = Color(0.93, 0.93, 0.9)
		surface.roughness = 0.4
		visual.mesh = _coral_tube()
		# A ring of slabs leaves the bore open.
		var slab := BoxShape3D.new()
		slab.size = Vector3(
				CORAL_WALL, CORAL_LENGTH, 2.04 * CORAL_RADIUS * tan(PI / _RING_SEGMENTS))
		for i in _RING_SEGMENTS:
			var angle := TAU * i / _RING_SEGMENTS
			var collider := CollisionShape3D.new()
			collider.shape = slab
			collider.transform = Transform3D(
					Basis(Vector3.UP, -angle),
					Vector3(cos(angle), 0.0, sin(angle)) * (CORAL_RADIUS - 0.5 * CORAL_WALL))
			piece.add_child(collider)
	else:
		piece.mass = ALGAE_MASS
		material.friction = 0.6
		material.bounce = 0.55
		surface.albedo_color = Color(0.1, 0.75, 0.6)
		surface.roughness = 0.7
		var ball := SphereMesh.new()
		ball.radius = ALGAE_RADIUS
		ball.height = 2.0 * ALGAE_RADIUS
		visual.mesh = ball
		var sphere := SphereShape3D.new()
		sphere.radius = ALGAE_RADIUS
		var collider := CollisionShape3D.new()
		collider.shape = sphere
		piece.add_child(collider)
	piece.physics_material_override = material
	visual.material_override = surface
	piece.add_child(visual)
	return piece


## Hands the piece to an intake: it stops colliding and follows where it is put.
func grab() -> void:
	held = true
	freeze_mode = FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0


func release(velocity: Vector3) -> void:
	held = false
	collision_layer = 1
	collision_mask = 1
	freeze = false
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO


static func _coral_tube() -> ArrayMesh:
	if _coral_mesh != null:
		return _coral_mesh
	var inner := CORAL_RADIUS - 0.006
	var half := 0.5 * CORAL_LENGTH
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _TUBE_SIDES:
		var a := Vector3(cos(TAU * i / _TUBE_SIDES), 0.0, sin(TAU * i / _TUBE_SIDES))
		var b := Vector3(cos(TAU * (i + 1) / _TUBE_SIDES), 0.0, sin(TAU * (i + 1) / _TUBE_SIDES))
		var up := Vector3(0.0, half, 0.0)
		# Outer wall, inner wall, then the two end rings.
		_quad(tool, a * CORAL_RADIUS - up, b * CORAL_RADIUS - up, b * CORAL_RADIUS + up, a * CORAL_RADIUS + up)
		_quad(tool, b * inner - up, a * inner - up, a * inner + up, b * inner + up)
		_quad(tool, a * CORAL_RADIUS + up, b * CORAL_RADIUS + up, b * inner + up, a * inner + up)
		_quad(tool, b * CORAL_RADIUS - up, a * CORAL_RADIUS - up, a * inner - up, b * inner - up)
	tool.generate_normals()
	_coral_mesh = tool.commit()
	return _coral_mesh


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for corner in [a, c, b, a, d, c]:
		tool.add_vertex(corner)
