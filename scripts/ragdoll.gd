extends Node2D
## A deliberately simple active ragdoll: jointed gray bodies and a ground-aware
## balance/walking controller. It remains a physical puppet when lifted or thrown.

const Prop = preload("res://scripts/prop.gd")
const PARTS := {
	"torso": [Vector2(0, -34), Vector2(26, 42), 4.0],
	"head": [Vector2(0, -70), Vector2(24, 24), 1.0],
	"pelvis": [Vector2(0, -5), Vector2(24, 18), 2.0],
	"left_upper_arm": [Vector2(-21, -36), Vector2(10, 26), 0.7],
	"left_forearm": [Vector2(-21, -10), Vector2(9, 26), 0.6],
	"right_upper_arm": [Vector2(21, -36), Vector2(10, 26), 0.7],
	"right_forearm": [Vector2(21, -10), Vector2(9, 26), 0.6],
	"left_thigh": [Vector2(-8, 19), Vector2(12, 30), 1.4],
	"left_shin": [Vector2(-8, 49), Vector2(11, 30), 1.0],
	"right_thigh": [Vector2(8, 19), Vector2(12, 30), 1.4],
	"right_shin": [Vector2(8, 49), Vector2(11, 30), 1.0],
}
const JOINTS := [
	["torso", "head", Vector2(0, -55), -0.65, 0.65],
	["torso", "pelvis", Vector2(0, -13), -0.5, 0.5],
	["torso", "left_upper_arm", Vector2(-18, -49), -1.8, 1.8],
	["left_upper_arm", "left_forearm", Vector2(-21, -23), -1.5, 1.5],
	["torso", "right_upper_arm", Vector2(18, -49), -1.8, 1.8],
	["right_upper_arm", "right_forearm", Vector2(21, -23), -1.5, 1.5],
	["pelvis", "left_thigh", Vector2(-8, 4), -1.0, 1.0],
	["left_thigh", "left_shin", Vector2(-8, 34), -1.3, 1.3],
	["pelvis", "right_thigh", Vector2(8, 4), -1.0, 1.0],
	["right_thigh", "right_shin", Vector2(8, 34), -1.3, 1.3],
]

var torso: RigidBody2D
var flipped := false
var user_frozen := false
var world_paused := false
var ai_enabled := true
var _parts: Dictionary = {}
var _resize_percent := Vector2(50, 50)
var _phase := 0.0
var _direction := 1.0
var _turn_timer := 0.0

func _ready() -> void:
	_build()

func bodies() -> Array:
	return _parts.values()

func get_resize_percent() -> Vector2:
	return _resize_percent

func set_world_paused(value: bool) -> void:
	world_paused = value
	for body in bodies():
		body.set_world_paused(value)

func set_user_frozen(value: bool) -> void:
	user_frozen = value
	for body in bodies():
		body.set_user_frozen(value)

func resize_object(percent: Vector2) -> void:
	var center := torso.global_position if is_instance_valid(torso) else global_position
	_resize_percent = percent.clamp(Vector2.ZERO, Vector2(100, 100))
	# Keep the torso centered while rebuilding every physical shape and anchor.
	global_position = center - Vector2(0, -34) * _scale_factor()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_parts.clear()
	_build()

func _scale_factor() -> Vector2:
	return Vector2(maxf(_resize_percent.x / 50.0, 0.01), maxf(_resize_percent.y / 50.0, 0.01))

func _build() -> void:
	var factor := _scale_factor()
	for part_name in PARTS:
		var spec: Array = PARTS[part_name]
		var body = Prop.new()
		body.name = part_name
		body.configure_part(spec[1] * factor, part_name == "head")
		body.object_owner = self
		body.position = spec[0] * factor
		add_child(body)
		body.mass = maxf(float(spec[2]) * factor.x * factor.y, 0.05)
		body.angular_damp = 2.0
		_parts[part_name] = body
		torso = _parts["torso"]
	for spec in JOINTS:
		var joint := PinJoint2D.new()
		joint.position = spec[2] * factor
		joint.softness = 0.12
		joint.bias = 0.3
		joint.angular_limit_enabled = true
		joint.angular_limit_lower = spec[3]
		joint.angular_limit_upper = spec[4]
		add_child(joint)
		joint.node_a = joint.get_path_to(_parts[spec[0]])
		joint.node_b = joint.get_path_to(_parts[spec[1]])
		joint.set_meta("anchor_a", _parts[spec[0]].to_local(joint.global_position))
		joint.set_meta("anchor_b", _parts[spec[1]].to_local(joint.global_position))
	_exclude_self_collisions()
	set_world_paused(world_paused)
	set_user_frozen(user_frozen)
	if flipped:
		var previous_direction := _direction
		flipped = false
		flip_object()
		_direction = previous_direction

func _exclude_self_collisions() -> void:
	# Explicitly register both directions after joints finish configuring their
	# own exceptions. These exclusions never include another object or the floor.
	for body in bodies():
		for other in bodies():
			if body != other:
				body.add_collision_exception_with(other)

func flip_object() -> void:
	if not is_instance_valid(torso):
		return
	var pivot := torso.global_position
	var anchor_positions: Dictionary = {}
	for child in get_children():
		if child is PinJoint2D:
			var body_a: Node2D = child.get_node(child.node_a)
			var body_b: Node2D = child.get_node(child.node_b)
			var anchor: Vector2 = (body_a.to_global(child.get_meta("anchor_a")) + body_b.to_global(child.get_meta("anchor_b"))) * 0.5
			anchor_positions[child] = Vector2(pivot.x * 2.0 - anchor.x, anchor.y)
	flipped = not flipped
	_direction *= -1.0
	for body in bodies():
		body.global_position.x = pivot.x * 2.0 - body.global_position.x
		body.rotation = -body.rotation
		body.linear_velocity.x = -body.linear_velocity.x
		body.angular_velocity = -body.angular_velocity
		body.paused_velocity.x = -body.paused_velocity.x
		body.paused_spin = -body.paused_spin
		body.local_grab.x = -body.local_grab.x
		body.flip_object()
	# Rebuild anchors from the current physical pose, not spawn-time positions:
	# the puppet may have walked or fallen far away from its Node2D origin.
	for joint in anchor_positions:
		var path_a: NodePath = joint.node_a
		var path_b: NodePath = joint.node_b
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		joint.global_position = anchor_positions[joint]
		joint.node_a = path_a
		joint.node_b = path_b
		joint.set_meta("anchor_a", joint.get_node(path_a).to_local(joint.global_position))
		joint.set_meta("anchor_b", joint.get_node(path_b).to_local(joint.global_position))
	_exclude_self_collisions()

func _physics_process(delta: float) -> void:
	if not ai_enabled or user_frozen or world_paused or not is_instance_valid(torso):
		return
	for body in bodies():
		if body.dragging:
			return
	_phase += delta * 3.0
	_turn_timer += delta
	if _turn_timer > 5.0:
		_turn_timer = 0.0
		_direction *= -1.0
	if not _is_grounded():
		return
	# Ground-aware modest muscle torques, not transform animation. External
	# impacts can knock it down and picking it up disables the AI controller.
	for part_name in _parts:
		var body: RigidBody2D = _parts[part_name]
		var desired := 0.0
		if "thigh" in part_name:
			desired = sin(_phase) * 0.08 * (1 if part_name.begins_with("left") else -1)
		elif "shin" in part_name:
			desired = sin(_phase + 0.6) * 0.06 * (1 if part_name.begins_with("left") else -1)
		elif "arm" in part_name:
			desired = sin(_phase) * 0.08 * (1 if part_name.begins_with("left") else -1)
		var dimensions: Vector2 = PARTS[part_name][1] * _scale_factor()
		var inertia_estimate := body.mass * dimensions.length_squared() / 12.0
		var angle_error := wrapf(desired - body.rotation, -PI, PI)
		body.apply_torque(clampf((angle_error * 80.0 - body.angular_velocity * 17.0) * inertia_estimate, -120000.0, 120000.0))
	var total_mass := 0.0
	for body in bodies():
		total_mass += body.mass
	# Damp vertical sag using a ground-only muscle support. Capping it below
	# total weight prevents levitation; the feet still carry the remaining load.
	var foot_y := maxf(_parts["left_shin"].global_position.y, _parts["right_shin"].global_position.y)
	var desired_torso_y := foot_y - 83.0 * _scale_factor().y
	var support := total_mass * 980.0 * 0.35 + (torso.global_position.y - desired_torso_y) * total_mass * 35.0 + torso.linear_velocity.y * total_mass * 7.0
	support = clampf(support, 0.0, total_mass * 980.0 * 0.9)
	torso.apply_central_force(Vector2((_direction * 8.0 - torso.linear_velocity.x) * torso.mass * 2.0, -support))

func _is_grounded() -> bool:
	var ignored: Array[RID] = []
	for body in bodies():
		ignored.append(body.get_rid())
	for foot_name in ["left_shin", "right_shin"]:
		var foot: RigidBody2D = _parts[foot_name]
		var reach := 15.0 * _scale_factor().y + 12.0
		var query := PhysicsRayQueryParameters2D.create(foot.global_position, foot.global_position + Vector2(0, reach))
		query.exclude = ignored
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			return true
	return false
