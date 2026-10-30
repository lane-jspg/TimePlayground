extends Node2D
## Physical tethers, rigid welds and directed electrical connections.
## Wires advance synchronously by one simulation tick, including feedback loops.

var objects: Node2D
var world_paused := false
var connections: Array[Dictionary] = []
var _collision_pairs: Dictionary = {}

func configure(object_root: Node2D) -> void:
	objects = object_root

func add_connection(kind: String, a: RigidBody2D, anchor_world_a: Vector2, b: RigidBody2D, anchor_world_b: Vector2) -> Node:
	if kind not in ["rope", "weld", "wire"] or not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return null
	if not a.is_inside_tree() or not b.is_inside_tree():
		return null
	var holder := Node2D.new()
	holder.name = "Connection_" + kind
	add_child(holder)
	var record: Dictionary = {
		"kind": kind, "a": a, "b": b,
		"anchor_a": _normalized_anchor(a, anchor_world_a),
		"anchor_b": _normalized_anchor(b, anchor_world_b),
		"rest_length": maxf(4.0, anchor_world_a.distance_to(anchor_world_b)),
		"node": holder, "lit": false,
		"geometry": _geometry_key(a, b),
		"pose_a": a.global_transform, "pose_b": b.global_transform,
	}
	connections.append(record)
	if kind == "weld":
		_build_weld(record)
	if kind != "wire":
		record["pair_key"] = _retain_collision_pair(a, b)
	queue_redraw()
	return holder

func endpoints(record: Dictionary) -> Array[Vector2]:
	if not _valid_record(record):
		return []
	return [record.a.to_global(_local_anchor(record.a, record.anchor_a)), record.b.to_global(_local_anchor(record.b, record.anchor_b))]

func remove_connection(connection: Variant) -> void:
	var node: Node = connection.node if connection is Dictionary else connection
	for index in range(connections.size() - 1, -1, -1):
		if connections[index].node == node:
			_remove_at(index)
	queue_redraw()

func refresh_for(object_owner: Node) -> void:
	for record in connections:
		if _valid_record(record) and record.kind == "weld" and (_owner_of(record.a) == object_owner or _owner_of(record.b) == object_owner):
			_build_weld(record)
	queue_redraw()

func remove_for(object_owner: Node) -> void:
	for index in range(connections.size() - 1, -1, -1):
		var record: Dictionary = connections[index]
		if not _valid_record(record) or _owner_of(record.a) == object_owner or _owner_of(record.b) == object_owner:
			_remove_at(index)
	queue_redraw()

func clear_all() -> void:
	for index in range(connections.size() - 1, -1, -1):
		_remove_at(index)
	queue_redraw()

func _owner_of(body: RigidBody2D) -> Node:
	var object = body.get("object_owner")
	return object if is_instance_valid(object) else body

func _valid_record(record: Dictionary) -> bool:
	return is_instance_valid(record.a) and is_instance_valid(record.b) and record.a.is_inside_tree() and record.b.is_inside_tree()

func _body_size(body: RigidBody2D) -> Vector2:
	var dimensions = body.get("body_size")
	if dimensions is Vector2:
		return Vector2(maxf(dimensions.x, 0.01), maxf(dimensions.y, 0.01))
	return Vector2.ONE

func _local_anchor(body: RigidBody2D, normalized: Vector2) -> Vector2:
	var point := normalized * _body_size(body)
	if body.get("flipped") == true:
		point.x = -point.x
	return point

func _normalized_anchor(body: RigidBody2D, world: Vector2) -> Vector2:
	var point := body.to_local(world) / _body_size(body)
	if body.get("flipped") == true:
		point.x = -point.x
	return point

func _geometry_key(a: RigidBody2D, b: RigidBody2D) -> Array:
	return [_body_size(a), _body_size(b), a.get("flipped"), b.get("flipped")]

func _build_weld(record: Dictionary) -> void:
	var holder: Node2D = record.node
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var points := endpoints(record)
	if points.size() != 2:
		return
	var midpoint := (points[0] + points[1]) * 0.5
	var direction: Vector2 = (record.b.global_position - record.a.global_position).normalized()
	if direction.length_squared() < 0.1:
		direction = Vector2.RIGHT
	# Two separated pins lock both translation and relative rotation. Pin anchors
	# share world positions, preserving the chosen pose without snapping bodies.
	var separation := direction.orthogonal() * 28.0
	for point in [midpoint - separation, midpoint + separation]:
		var joint := PinJoint2D.new()
		joint.disable_collision = false # Collision ownership is tracked separately.
		joint.softness = 0.0
		joint.bias = 0.8
		holder.add_child(joint)
		joint.global_position = point
		joint.node_a = joint.get_path_to(record.a)
		joint.node_b = joint.get_path_to(record.b)
	record.geometry = _geometry_key(record.a, record.b)
	record.pose_a = record.a.global_transform
	record.pose_b = record.b.global_transform

func _retain_collision_pair(a: RigidBody2D, b: RigidBody2D) -> String:
	var key := "%d:%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
	if not _collision_pairs.has(key):
		_collision_pairs[key] = {
			"a": a, "b": b, "count": 0,
			"had_a": a.get_collision_exceptions().has(b),
			"had_b": b.get_collision_exceptions().has(a),
		}
	_collision_pairs[key].count += 1
	a.add_collision_exception_with(b)
	b.add_collision_exception_with(a)
	return key

func _release_collision_pair(key: String) -> void:
	if not _collision_pairs.has(key):
		return
	var pair: Dictionary = _collision_pairs[key]
	pair.count -= 1
	if pair.count > 0:
		return
	if is_instance_valid(pair.a) and is_instance_valid(pair.b):
		if not pair.had_a:
			pair.a.remove_collision_exception_with(pair.b)
		if not pair.had_b:
			pair.b.remove_collision_exception_with(pair.a)
	_collision_pairs.erase(key)

func _remove_at(index: int) -> void:
	var record: Dictionary = connections[index]
	if record.has("pair_key"):
		_release_collision_pair(record.pair_key)
	if is_instance_valid(record.node):
		remove_child(record.node)
		record.node.queue_free()
	connections.remove_at(index)

func _process(_delta: float) -> void:
	# Refresh even while the simulation is stopped and bodies are edited.
	for index in range(connections.size() - 1, -1, -1):
		var record: Dictionary = connections[index]
		if not _valid_record(record):
			_remove_at(index)
		elif record.kind == "weld":
			var edited: bool = world_paused and (record.pose_a != record.a.global_transform or record.pose_b != record.b.global_transform)
			if edited or record.geometry != _geometry_key(record.a, record.b):
				_build_weld(record)
			record.pose_a = record.a.global_transform
			record.pose_b = record.b.global_transform
	queue_redraw()

func _physics_process(delta: float) -> void:
	if world_paused:
		return
	for record in connections:
		if _valid_record(record) and record.kind == "rope":
			_tighten_rope(record, delta)
	propagate_power(delta)

func _point_velocity(body: RigidBody2D, radius: Vector2) -> Vector2:
	if body.freeze:
		return Vector2.ZERO
	return body.linear_velocity + Vector2(-radius.y, radius.x) * body.angular_velocity

func _inverse_mass(body: RigidBody2D) -> float:
	return 0.0 if body.freeze else 1.0 / maxf(body.mass, 0.01)

func _inverse_inertia(body: RigidBody2D) -> float:
	if body.freeze:
		return 0.0
	if body.inertia > 0.0:
		return 1.0 / body.inertia
	return 12.0 / maxf(body.mass * _body_size(body).length_squared(), 0.01)

func _tighten_rope(record: Dictionary, delta: float) -> void:
	var points := endpoints(record)
	var difference := points[1] - points[0]
	var distance := difference.length()
	if distance < float(record.rest_length) - 0.5 or distance < 0.001:
		return
	var a: RigidBody2D = record.a
	var b: RigidBody2D = record.b
	var direction := difference / distance
	var radius_a := points[0] - a.global_position
	var radius_b := points[1] - b.global_position
	var effective_mass := _inverse_mass(a) + _inverse_mass(b)
	effective_mass += pow(radius_a.cross(direction), 2.0) * _inverse_inertia(a)
	effective_mass += pow(radius_b.cross(direction), 2.0) * _inverse_inertia(b)
	if effective_mass < 0.00001:
		return
	var relative_speed := (_point_velocity(b, radius_b) - _point_velocity(a, radius_a)).dot(direction)
	var correction := maxf(0.0, distance - float(record.rest_length)) * 0.24 / maxf(delta, 0.0001)
	var magnitude := maxf(0.0, (relative_speed + correction) / effective_mass)
	magnitude = minf(magnitude, (a.mass + b.mass) * 20000.0 * delta)
	if not a.freeze:
		a.sleeping = false
		a.apply_impulse(direction * magnitude, radius_a)
	if not b.freeze:
		b.sleeping = false
		b.apply_impulse(-direction * magnitude, radius_b)

func _electrical_bodies(node: Node) -> Array:
	var result: Array = []
	if node is RigidBody2D and node.has_method("set_power_inputs"):
		result.append(node)
	for child in node.get_children():
		result.append_array(_electrical_bodies(child))
	return result

func propagate_power(delta: float) -> void:
	if not is_instance_valid(objects) or world_paused:
		return
	var bodies := _electrical_bodies(objects)
	var outputs: Dictionary = {}
	var inputs: Dictionary = {}
	for body in bodies:
		outputs[body.get_instance_id()] = bool(body.get("output_power"))
		inputs[body.get_instance_id()] = []
	for record in connections:
		if not _valid_record(record) or record.kind != "wire":
			continue
		var a_id: int = record.a.get_instance_id()
		var b_id: int = record.b.get_instance_id()
		var lit: bool = outputs.get(a_id, false)
		record.lit = lit
		if inputs.has(b_id):
			inputs[b_id].append(lit)
	for body in bodies:
		body.set_power_inputs(inputs[body.get_instance_id()], delta)

func _draw() -> void:
	for record in connections:
		var points := endpoints(record)
		if points.size() != 2:
			continue
		var start := to_local(points[0])
		var end := to_local(points[1])
		match record.kind:
			"rope":
				var slack := maxf(0, float(record.rest_length) - start.distance_to(end))
				var curve := PackedVector2Array()
				for step in 17:
					var t := step / 16.0
					curve.append(start.lerp(end, t) + Vector2(0, sin(t * PI) * minf(slack * 0.6, 80.0)))
				draw_polyline(curve, Color("bd9b69"), 3.0, true)
			"weld":
				draw_line(start, end, Color("9da7ad"), 5.0, true)
				draw_circle(start, 4, Color("c7d2d9"))
				draw_circle(end, 4, Color("c7d2d9"))
			"wire":
				var color := Color("87ea58") if record.lit else Color("425d32")
				var corner := Vector2(end.x, start.y)
				draw_polyline(PackedVector2Array([start, corner, end]), color, 2.0, true)
				var direction := (end - corner).normalized()
				if direction.length_squared() < 0.1:
					direction = (end - start).normalized()
				if direction.length_squared() < 0.1:
					direction = Vector2.RIGHT
				var side := direction.orthogonal() * 3.0
				draw_colored_polygon(PackedVector2Array([end, end - direction * 9 + side, end - direction * 9 - side]), color)
