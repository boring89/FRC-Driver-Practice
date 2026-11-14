class_name SwerveRobot
extends RigidBody3D
## Swerve robot chassis. The body is a rigid box riding on four ray-cast wheels;
## each wheel's load, grip and motor torque come from SwerveModule, so traction
## limits, weight transfer and wheel lift all fall out of the physics.
##
## The body origin sits on the floor under the centre of the frame when at rest.

const SUBSTEPS := 8
# Vertical compliance of tread plus carpet: about 1.3 mm of sag at rest.
const TIRE_STIFFNESS := 120000.0
const TIRE_DAMPING := 1500.0
const _RAY_MARGIN := 0.05

var config: Dictionary
var modules: Array[SwerveModule] = []
var controller: SwerveController
var battery := Battery.new()
## Mechanisms above the drivebase; null for a robot without a CAD model.
var superstructure: Superstructure

## Driver request: x, y in m/s and z in rad/s.
var command := Vector3.ZERO
var field_relative := true
## Field heading the driver calls "forward": 0 from the blue wall, PI from red.
var driver_heading := 0.0
var max_speed := 5.0
var max_omega := 9.0

var _quiescent_current := 0.0
var _code_time := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _wheel_pivots: Array[Node3D] = []
var _wheel_spinners: Array[Node3D] = []


static func load_config(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Builds the robot from its config. Call before adding it to the scene.
func setup(robot_config: Dictionary, bumper_color: Color) -> void:
	config = robot_config
	var inertia_cfg: Dictionary = config["inertia_kgm2"]
	var com: Array = config["com_m"]
	mass = config["mass_kg"]
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Frc.to_godot(Vector3(com[0], com[1], com[2]))
	inertia = Vector3(inertia_cfg["roll"], inertia_cfg["yaw"], inertia_cfg["pitch"])
	linear_damp_mode = DAMP_MODE_REPLACE
	angular_damp_mode = DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	continuous_cd = true
	var material := PhysicsMaterial.new()
	material.friction = 0.5
	material.bounce = 0.05
	physics_material_override = material

	var battery_cfg: Dictionary = config["battery"]
	battery.open_circuit_voltage = battery_cfg["open_circuit_v"]
	battery.resistance = battery_cfg["resistance_ohm"]
	battery.voltage = battery.open_circuit_voltage
	_quiescent_current = battery_cfg["quiescent_a"]

	var driver: Dictionary = config["driver"]
	max_speed = driver["max_speed_mps"]
	max_omega = driver["max_omega_radps"]

	var swerve: Dictionary = config["swerve"]
	var positions: Array = swerve["module_positions_m"]
	for i in positions.size():
		modules.append(SwerveModule.from_config(swerve, i))
	controller = SwerveController.new(modules, swerve["drive"]["kp_v_per_mps"])

	_build_body(bumper_color)


func _ready() -> void:
	_ray.exclude = [get_rid()]


func yaw() -> float:
	return Frc.yaw_of(global_basis)


func ground_speed() -> float:
	return Vector2(linear_velocity.x, linear_velocity.z).length()


## Teleports the robot to a field position (m) and heading (rad), at rest.
func reset_pose(field_xy: Vector2, heading: float) -> void:
	global_transform = Transform3D(
			Basis(Vector3.UP, heading), Frc.to_godot(Vector3(field_xy.x, field_xy.y, 0.0)))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Tell the physics server directly: a node transform set late in a frame can
	# otherwise be overwritten by the body's own state before it is picked up.
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	command = Vector3.ZERO
	for m in modules:
		m.reset()
	if superstructure:
		superstructure.reset()


func _physics_process(dt: float) -> void:
	_code_time += dt
	if _code_time >= controller.period:
		_code_time = fmod(_code_time, controller.period)
		controller.update(command, field_relative, yaw() - driver_heading)
	# Mechanism position loops run on the motor controllers, far faster than robot code.
	if superstructure:
		superstructure.update_controllers(dt, self)

	var space := get_world_3d().direct_space_state
	var xf := global_transform
	var up := xf.basis.y
	var com_world := xf * center_of_mass
	var total_current := _quiescent_current

	for m in modules:
		var hub := xf * Vector3(m.position.x, m.wheel_radius, -m.position.y)
		_ray.from = hub
		_ray.to = hub - up * (m.wheel_radius + _RAY_MARGIN)
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			m.step(dt, SUBSTEPS, 0.0, 0.0, 0.0, battery.voltage)
			total_current += m.supply_current
			continue

		var contact: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var velocity := linear_velocity + angular_velocity.cross(contact - com_world)
		var other := hit["collider"] as RigidBody3D
		if other:
			var other_state := PhysicsServer3D.body_get_direct_state(other.get_rid())
			velocity -= other_state.get_velocity_at_local_position(contact - other.global_position)

		var tire_load := 0.0
		var sag := m.wheel_radius - hub.distance_to(contact)
		if sag > 0.0:
			tire_load = maxf(0.0, TIRE_STIFFNESS * sag - TIRE_DAMPING * velocity.dot(normal))

		var forward := (xf.basis.x - normal * xf.basis.x.dot(normal)).normalized()
		var left := normal.cross(forward)
		var grip := m.step(dt, SUBSTEPS, velocity.dot(forward), velocity.dot(left), tire_load, battery.voltage)
		var tire_force := forward * grip.x + left * grip.y + normal * tire_load
		apply_force(tire_force, contact - xf.origin)
		if other:
			other.apply_force(-tire_force, contact - other.global_position)
		total_current += m.supply_current

	if superstructure:
		total_current += superstructure.step(dt, self, battery.voltage)
	battery.step(total_current, dt)


func _process(_dt: float) -> void:
	for i in modules.size():
		_wheel_pivots[i].rotation.y = modules[i].steer_angle
		_wheel_spinners[i].rotation.z = -modules[i].wheel_spin


func _build_body(bumper_color: Color) -> void:
	var frame: Array = config["frame_m"]
	var length: float = frame[0]
	var width: float = frame[1]
	var clearance: float = config["ground_clearance_m"]
	var bumper: float = config["bumper_thickness_m"]
	var zone: Array = config["bumper_zone_m"]
	var bumper_low: float = zone[0]
	var bumper_high: float = zone[1]

	var shape := BoxShape3D.new()
	shape.size = Vector3(length + 2.0 * bumper, bumper_high - clearance, width + 2.0 * bumper)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.5 * (bumper_high + clearance)
	add_child(collider)

	# The CAD model only exists once scripts/build_robot.py has been run.
	var model_dir: String = config.get("model", "")
	if model_dir != "" and ResourceLoader.exists(model_dir.path_join("robot.glb")):
		_build_cad_model(model_dir)
		return

	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.55, 0.57, 0.6)
	frame_material.metallic = 0.8
	frame_material.roughness = 0.4
	# Plus-shaped belly so the wheels in the corners stay visible.
	_add_box(Vector3(0.0, clearance + 0.04, 0.0), Vector3(length, 0.08, width - 0.3), frame_material)
	_add_box(Vector3(0.0, clearance + 0.04, 0.0), Vector3(length - 0.3, 0.08, width), frame_material)

	var bumper_material := StandardMaterial3D.new()
	bumper_material.albedo_color = bumper_color
	bumper_material.roughness = 0.9
	var bumper_height := bumper_high - bumper_low
	var bumper_y := 0.5 * (bumper_high + bumper_low)
	for side in [-1.0, 1.0]:
		_add_box(Vector3(side * 0.5 * (length + bumper), bumper_y, 0.0),
				Vector3(bumper, bumper_height, width + 2.0 * bumper), bumper_material)
		_add_box(Vector3(0.0, bumper_y, side * 0.5 * (width + bumper)),
				Vector3(length, bumper_height, bumper), bumper_material)

	# Bright strip marking the front of the robot.
	var front_material := StandardMaterial3D.new()
	front_material.albedo_color = Color(1.0, 0.85, 0.1)
	front_material.emission_enabled = true
	front_material.emission = Color(1.0, 0.85, 0.1)
	_add_box(Vector3(0.5 * length - 0.03, clearance + 0.09, 0.0),
			Vector3(0.05, 0.02, 0.6 * width), front_material)

	var tread_material := StandardMaterial3D.new()
	tread_material.albedo_color = Color(0.08, 0.08, 0.08)
	tread_material.roughness = 1.0
	var hub_material := StandardMaterial3D.new()
	hub_material.albedo_color = Color(0.9, 0.9, 0.9)
	for m in modules:
		var pivot := Node3D.new()
		pivot.position = Vector3(m.position.x, m.wheel_radius, -m.position.y)
		add_child(pivot)
		var spinner := Node3D.new()
		pivot.add_child(spinner)
		var tread := CylinderMesh.new()
		tread.top_radius = m.wheel_radius
		tread.bottom_radius = m.wheel_radius
		tread.height = 0.038
		var wheel := MeshInstance3D.new()
		wheel.mesh = tread
		wheel.material_override = tread_material
		wheel.rotation.x = PI / 2.0
		spinner.add_child(wheel)
		# Spoke across the hub so wheel spin is visible.
		var spoke := BoxMesh.new()
		spoke.size = Vector3(1.6 * m.wheel_radius, 0.012, 0.042)
		var spoke_instance := MeshInstance3D.new()
		spoke_instance.mesh = spoke
		spoke_instance.material_override = hub_material
		spinner.add_child(spoke_instance)
		_wheel_pivots.append(pivot)
		_wheel_spinners.append(spinner)


## Robot built from the Onshape CAD by scripts/build_robot.py: one mesh per
## link, with each module's "steer_N" and "wheel_N" posed straight ahead.
func _build_cad_model(model_dir: String) -> void:
	var scene: PackedScene = load(model_dir.path_join("robot.glb"))
	var model := scene.instantiate()
	add_child(model)
	for i in modules.size():
		_wheel_pivots.append(model.find_child("steer_%d" % i, true, false))
		_wheel_spinners.append(model.find_child("wheel_%d" % i, true, false))

	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(model_dir.path_join("model.json")))
	superstructure = Superstructure.new()
	superstructure.setup(config.get("mechanism", {}), model, meta, self)


func _add_box(center: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	add_child(instance)
