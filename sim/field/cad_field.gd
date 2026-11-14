class_name CadField
extends Node3D
## Field built from the Onshape CAD by scripts/build_field.py. The asset is
## already laid out in the FRC field frame, and its "-colonly" mesh arrives from
## the importer as a static triangle-mesh collider.

const ELEMENT_FRICTION := 0.4
const _FLOOR_MARGIN := 6.0

var _scene_path: String


static func asset_path(year: int) -> String:
	return "res://assets/fields/%d/field.glb" % year


func _init(year: int) -> void:
	_scene_path = asset_path(year)


func _ready() -> void:
	var scene: PackedScene = load(_scene_path)
	add_child(scene.instantiate())
	var element_material := PhysicsMaterial.new()
	element_material.friction = ELEMENT_FRICTION
	for body: StaticBody3D in find_children("*", "StaticBody3D", true, false):
		body.physics_material_override = element_material

	# Wheels ride on a flat slab at z = 0 rather than on the CAD carpet mesh.
	var size := Vector3(Frc.FIELD_LENGTH + 2.0 * _FLOOR_MARGIN, 1.0, Frc.FIELD_WIDTH + 2.0 * _FLOOR_MARGIN)
	var centre := Frc.to_godot(Vector3(0.5 * Frc.FIELD_LENGTH, 0.5 * Frc.FIELD_WIDTH, -0.5))
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	var floor_body := StaticBody3D.new()
	floor_body.position = centre
	floor_body.add_child(collider)
	add_child(floor_body)

	# Arena floor around the carpet, a little lower so the two never z-fight.
	var surround_material := StandardMaterial3D.new()
	surround_material.albedo_color = Color(0.07, 0.07, 0.08)
	surround_material.roughness = 0.9
	var surround_mesh := BoxMesh.new()
	surround_mesh.size = size
	var surround := MeshInstance3D.new()
	surround.mesh = surround_mesh
	surround.material_override = surround_material
	surround.position = centre + Vector3(0.0, -0.02, 0.0)
	add_child(surround)
