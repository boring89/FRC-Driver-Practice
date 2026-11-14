class_name PlaceholderField
extends Node3D
## Stand-in for the 2025 REEFSCAPE field until the real CAD is imported: carpet,
## perimeter walls and the two reefs as plain hexagonal prisms.

const WALL_THICKNESS := 0.05
const GUARDRAIL_HEIGHT := 0.51
const ALLIANCE_WALL_HEIGHT := 1.98
# Reef: distance from the alliance wall to its centre, and across its flats.
const REEF_CENTER_X := 4.489
const REEF_FLAT_TO_FLAT := 1.664
const REEF_HEIGHT := 1.0


func _ready() -> void:
	var length := Frc.FIELD_LENGTH
	var width := Frc.FIELD_WIDTH

	var surround := _material(Color(0.07, 0.07, 0.08), 0.9)
	var carpet := _material(Color(0.16, 0.17, 0.18), 1.0)
	var tape := _material(Color(0.9, 0.9, 0.9), 0.8)
	var rail := _material(Color(0.75, 0.82, 0.9, 0.18), 0.1)
	rail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Floor slab with its top face at z = 0, extending past the field.
	_box(Vector3(0.5 * length, 0.5 * width, -0.5), Vector3(length + 12.0, width + 12.0, 1.0), surround, 1.0)
	_box(Vector3(0.5 * length, 0.5 * width, 0.001), Vector3(length, width, 0.002), carpet)
	_box(Vector3(0.5 * length, 0.5 * width, 0.002), Vector3(0.05, width, 0.002), tape)

	for y in [-0.5 * WALL_THICKNESS, width + 0.5 * WALL_THICKNESS]:
		_box(Vector3(0.5 * length, y, 0.5 * GUARDRAIL_HEIGHT),
				Vector3(length, WALL_THICKNESS, GUARDRAIL_HEIGHT), rail, 0.3)
	for x in [-0.5 * WALL_THICKNESS, length + 0.5 * WALL_THICKNESS]:
		_box(Vector3(x, 0.5 * width, 0.5 * ALLIANCE_WALL_HEIGHT),
				Vector3(WALL_THICKNESS, width + 2.0 * WALL_THICKNESS, ALLIANCE_WALL_HEIGHT), rail, 0.3)

	_reef(Vector2(REEF_CENTER_X, 0.5 * width), _material(Color(0.2, 0.35, 0.8), 0.6))
	_reef(Vector2(length - REEF_CENTER_X, 0.5 * width), _material(Color(0.8, 0.2, 0.2), 0.6))


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


## Adds a box given in field coordinates. A non-negative `friction` also makes it a collider.
func _box(center: Vector3, size: Vector3, material: Material, friction := -1.0) -> void:
	var godot_size := Vector3(size.x, size.z, size.y)
	var mesh := BoxMesh.new()
	mesh.size = godot_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	if friction < 0.0:
		instance.position = Frc.to_godot(center)
		add_child(instance)
		return
	var shape := BoxShape3D.new()
	shape.size = godot_size
	_static_body(Frc.to_godot(center), shape, instance, friction)


func _reef(center: Vector2, material: Material) -> void:
	# A flat face points at the alliance wall, so corners sit at 30, 90, ... degrees.
	var corner_radius := 0.5 * REEF_FLAT_TO_FLAT / cos(PI / 6.0)
	var points := PackedVector3Array()
	for i in 6:
		var angle := PI / 6.0 + i * PI / 3.0
		var corner := Vector2(cos(angle), sin(angle)) * corner_radius
		points.append(Frc.to_godot(Vector3(corner.x, corner.y, 0.0)))
		points.append(Frc.to_godot(Vector3(corner.x, corner.y, REEF_HEIGHT)))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var prism := CylinderMesh.new()
	prism.radial_segments = 6
	prism.rings = 1
	prism.top_radius = corner_radius
	prism.bottom_radius = corner_radius
	prism.height = REEF_HEIGHT
	var instance := MeshInstance3D.new()
	instance.mesh = prism
	instance.material_override = material
	instance.position.y = 0.5 * REEF_HEIGHT
	_static_body(Frc.to_godot(Vector3(center.x, center.y, 0.0)), shape, instance, 0.4)


func _static_body(origin: Vector3, shape: Shape3D, visual: MeshInstance3D, friction: float) -> void:
	var body := StaticBody3D.new()
	body.position = origin
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = friction
	body.physics_material_override = physics_material
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.add_child(visual)
	add_child(body)
