class_name Superstructure
extends RefCounted
## The robot's mechanisms above the drivebase.
##
## Joint motion is solved here from motor torque, link inertia and gravity (the
## way WPILib's arm and elevator simulations do it) rather than with physics
## joints. The links ride on the chassis body as visuals and convex colliders
## (an end effector's colliders on a body of their own that only game pieces feel),
## their weight moves the body's centre of mass, and their acceleration pushes
## back on the chassis.

const _GRAVITY := Vector3(0.0, -9.80665, 0.0)
# Stand-in for a link's own rotational inertia about its centre of mass.
const _LINK_GYRATION_SQ := 0.01


class Link:
	var joint: MechanismJoint
	## Fraction of the joint's travel this link moves (a telescope's middle stage is 0.5).
	var ratio := 1.0
	var mass := 0.0
	## Centre of mass in the stowed pose, body-local.
	var stowed_com: Vector3
	var com: Vector3
	var visual: Node3D
	## The link's convex hull on the chassis body, or one hull per part where
	## the model has them.
	var colliders: Array[CollisionShape3D] = []
	## Set instead for a link that has to reach in among field elements (an end
	## effector around a reef branch): a body of its own carrying its colliders,
	## which pushes game pieces about but passes through the field.
	var pusher: AnimatableBody3D
	var last_com: Vector3
	var last_velocity: Vector3
	var settled := false


var joints: Array[MechanismJoint] = []
## The bodies of the links that only collide with game pieces.
var pushers: Array[AnimatableBody3D] = []
var presets: Array = []
var preset_name := ""
## Off while posing by hand, so each joint goes straight where it is told.
var sequencing := true

# Optional rule that keeps a telescope pulled in while the arm carrying it swings.
var _slide: MechanismJoint
var _swing: MechanismJoint
var _retracted := 0.0
var _swing_tolerance := 0.0
# Where each joint was last asked to go, before sequencing holds any of them back.
var _requested := {}
var _presets_path := ""

var _links: Array[Link] = []
var _links_by_name := {}
var _chassis_mass := 0.0
var _chassis_com: Vector3
var _chassis_inertia: Vector3
var _last_body_velocity := Vector3.ZERO


## `cfg` is the robot config's "mechanism" block (may be empty), `model` the
## instanced robot scene and `meta` its model.json.
func setup(cfg: Dictionary, model: Node, meta: Dictionary, body: RigidBody3D) -> void:
	var by_name := {}
	for joint_cfg: Dictionary in cfg.get("joints", []):
		var joint := MechanismJoint.from_config(joint_cfg)
		joint.parent = by_name.get(joint_cfg.get("parent", ""))
		by_name[joint.name] = joint
		joints.append(joint)
	# Presets live in their own file so the pose editor can rewrite it.
	_presets_path = cfg.get("presets", "")
	if _presets_path != "":
		presets = JSON.parse_string(FileAccess.get_file_as_string(_presets_path))
	if cfg.has("sequence"):
		var sequence: Dictionary = cfg["sequence"]
		_slide = by_name[sequence["slide"]]
		_swing = by_name[sequence["swing"]]
		_retracted = sequence["retracted_m"]
		_swing_tolerance = deg_to_rad(sequence["swing_tolerance_deg"])

	var moving := {}
	for joint_cfg: Dictionary in cfg.get("joints", []):
		for link_cfg: Dictionary in joint_cfg["links"]:
			var link := Link.new()
			link.joint = by_name[joint_cfg["name"]]
			link.ratio = link_cfg.get("ratio", 1.0)
			link.mass = link_cfg["mass_kg"]
			if link_cfg.get("collides", "all") == "pieces":
				link.pusher = AnimatableBody3D.new()
				# Moved by hand every tick, not by an animation.
				link.pusher.sync_to_physics = false
				link.pusher.collision_layer = GamePiece.PUSHER_LAYER
				link.pusher.collision_mask = 0
				body.add_child(link.pusher)
				pushers.append(link.pusher)
			link.visual = model.find_child(link_cfg["name"], true, false)
			moving[link_cfg["name"]] = link
			_links.append(link)
	_links_by_name = moving

	# Every link above the drivebase collides as its own convex hull, or as
	# the hulls of its parts where the model has them.
	var link_meta: Dictionary = meta["links"]
	for link_name: String in link_meta:
		var link: Link = moving.get(link_name)
		var hulls: Array = link_meta[link_name].get("part_hulls", [link_meta[link_name]["hull"]])
		for hull: Array in hulls:
			var points := PackedVector3Array()
			for point: Array in hull:
				points.append(Frc.to_godot(Vector3(point[0], point[1], point[2])))
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			var collider := CollisionShape3D.new()
			collider.shape = shape
			if link and link.pusher:
				link.pusher.add_child(collider)
				continue
			body.add_child(collider)
			if link:
				link.colliders.append(collider)
		if link:
			var centroid: Array = link_meta[link_name]["centroid"]
			link.stowed_com = Frc.to_godot(Vector3(centroid[0], centroid[1], centroid[2]))
			link.com = link.stowed_com

	_chassis_mass = body.mass
	for link in _links:
		_chassis_mass -= link.mass
	_chassis_com = body.center_of_mass
	_chassis_inertia = body.inertia
	_update_mass_properties(body)


## Where the named link has moved to from the stowed pose, body-local.
func link_pose(link_name: String) -> Transform3D:
	var link: Link = _links_by_name.get(link_name)
	return Transform3D.IDENTITY if link == null else _link_pose(link)


## Sends the mechanisms to the preset called `name`, if there is one.
func go_to_named(name: String) -> void:
	for preset: Dictionary in presets:
		if preset["name"] == name:
			go_to(preset)
			return


func go_to(preset: Dictionary) -> void:
	preset_name = preset["name"]
	var positions: Dictionary = preset["positions"]
	for joint in joints:
		var unit := 1.0 if joint.prismatic else PI / 180.0
		_requested[joint] = float(positions[joint.name]) * unit
		joint.set_goal(_requested[joint])


## Sends one joint to `value` (radians or metres), leaving the others alone.
func set_manual(joint: MechanismJoint, value: float) -> void:
	preset_name = ""
	_requested[joint] = clampf(value, joint.min_position, joint.max_position)


## Stores the current requested pose as preset `name` (replacing one of that
## name, or adding it) and writes the presets file.
func save_preset(name: String) -> void:
	var positions := {}
	for joint in joints:
		var value := requested(joint)
		positions[joint.name] = snappedf(value, 0.001) if joint.prismatic else snappedf(rad_to_deg(value), 0.1)
	var existing := presets.filter(func(preset: Dictionary) -> bool: return preset["name"] == name)
	if existing.is_empty():
		presets.append({"name": name, "positions": positions})
	else:
		existing[0]["positions"] = positions
	preset_name = name
	var rows := PackedStringArray()
	for preset: Dictionary in presets:
		rows.append("  " + JSON.stringify(preset, "", false))
	var file := FileAccess.open(_presets_path, FileAccess.WRITE)
	file.store_string("[\n" + ",\n".join(rows) + "\n]\n")


## Where `joint` was last asked to go (its goal may lag while sequencing).
func requested(joint: MechanismJoint) -> float:
	return _requested.get(joint, joint.goal)


func reset() -> void:
	preset_name = ""
	_requested.clear()
	for joint in joints:
		joint.reset()
	for link in _links:
		link.settled = false
	_last_body_velocity = Vector3.ZERO


## Runs the joints' position controllers for one loop of length `period`.
func update_controllers(period: float, body: RigidBody3D) -> void:
	_sequence_goals()
	var gravity := _felt_gravity(body, 0.0)
	for joint in joints:
		joint.update_controller(period, _load_on(joint, gravity).y)


## Retract, swing, extend: while the arm still has far to go the telescope
## pulls in, and the arm waits for it before moving.
func _sequence_goals() -> void:
	if _requested.is_empty():
		return
	if _slide == null or not sequencing:
		for joint in joints:
			joint.set_goal(requested(joint))
		return
	if absf(_swing.position - _requested[_swing]) <= _swing_tolerance:
		_slide.set_goal(_requested[_slide])
		_swing.set_goal(_requested[_swing])
		return
	_slide.set_goal(minf(_requested[_slide], _retracted))
	if _slide.position <= _retracted + 0.02:
		_swing.set_goal(_requested[_swing])
	else:
		_swing.set_goal(_swing.position)


## Advances the mechanisms by `dt` and returns the battery current they draw.
func step(dt: float, body: RigidBody3D, v_bat: float) -> float:
	if joints.is_empty():
		return 0.0
	var gravity := _felt_gravity(body, dt)
	var current := 0.0
	for joint in joints:
		var carried := _load_on(joint, gravity)
		joint.step(dt, carried.x, carried.y, v_bat)
		current += joint.supply_current

	for link in _links:
		var pose := _link_pose(link)
		link.com = pose * link.stowed_com
		link.visual.transform = pose
		for collider in link.colliders:
			collider.transform = pose
		if link.pusher:
			link.pusher.transform = pose

		# The chassis is one rigid body, so a link speeding up inside it has to
		# push back explicitly for momentum to balance.
		var velocity := (link.com - link.last_com) / dt
		if link.settled:
			var reaction := -link.mass * (velocity - link.last_velocity) / dt
			body.apply_force(body.global_basis * reaction, body.global_basis * link.com)
		link.last_com = link.com
		link.last_velocity = velocity if link.settled else Vector3.ZERO
		link.settled = true

	_update_mass_properties(body)
	return current


## Gravity as the mechanisms feel it in the body's frame: real gravity minus
## the chassis' own acceleration, so a hard launch loads the arm too.
func _felt_gravity(body: RigidBody3D, dt: float) -> Vector3:
	var felt := _GRAVITY
	if dt > 0.0:
		felt -= (body.linear_velocity - _last_body_velocity) / dt
		_last_body_velocity = body.linear_velocity
	return body.global_basis.inverse() * felt


## Pose of whatever is rigidly fixed to a joint's output.
func _frame(joint: MechanismJoint) -> Transform3D:
	var pose := joint.motion(joint.position)
	return pose if joint.parent == null else _frame(joint.parent) * pose


func _link_pose(link: Link) -> Transform3D:
	var pose := link.joint.motion(link.joint.position * link.ratio)
	return pose if link.joint.parent == null else _frame(link.joint.parent) * pose


## Generalised inertia (x) and gravity force (y) of everything `joint` moves.
func _load_on(joint: MechanismJoint, gravity: Vector3) -> Vector2:
	var base := Transform3D.IDENTITY if joint.parent == null else _frame(joint.parent)
	var axis := base.basis * joint.axis
	var origin := base * joint.origin
	var inertia := 0.0
	var force := 0.0
	for link in _links:
		var share := _share_of(link, joint)
		if share == 0.0:
			continue
		if joint.prismatic:
			inertia += link.mass * share * share
			force += link.mass * gravity.dot(axis) * share
		else:
			var arm := link.com - origin
			var radial := arm - axis * arm.dot(axis)
			inertia += link.mass * (radial.length_squared() + _LINK_GYRATION_SQ) * share * share
			force += axis.dot(arm.cross(link.mass * gravity)) * share
	return Vector2(inertia, force)


## How much of `joint`'s travel `link` follows: its own ratio if it sits on
## that joint, all of it if it sits further down the chain, none otherwise.
func _share_of(link: Link, joint: MechanismJoint) -> float:
	if link.joint == joint:
		return link.ratio
	var ancestor := link.joint.parent
	while ancestor != null:
		if ancestor == joint:
			return 1.0
		ancestor = ancestor.parent
	return 0.0


func _update_mass_properties(body: RigidBody3D) -> void:
	if _links.is_empty():
		return
	var com := _chassis_mass * _chassis_com
	for link in _links:
		com += link.mass * link.com
	com /= body.mass
	if com.is_equal_approx(body.center_of_mass):
		return
	var inertia := _chassis_inertia + _chassis_mass * _spread(_chassis_com - com)
	for link in _links:
		inertia += link.mass * _spread(link.com - com)
	body.center_of_mass = com
	body.inertia = inertia


## Diagonal of a point mass's inertia tensor per unit mass at offset `d`.
func _spread(d: Vector3) -> Vector3:
	return Vector3(d.y * d.y + d.z * d.z, d.x * d.x + d.z * d.z, d.x * d.x + d.y * d.y)
