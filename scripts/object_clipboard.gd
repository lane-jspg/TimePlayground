extends RefCounted
## A value-only clipboard. Nothing in snapshot refers to live scene objects, so
## originals can be deleted before a paste or pasted repeatedly.

var snapshot: Dictionary = {}

func copy_objects(owners: Array, connection_system: Node) -> bool:
	var unique: Array = []
	for object in owners:
		if is_instance_valid(object) and object not in unique:
			unique.append(object)
	if unique.is_empty():
		return false
	var center := Vector2.ZERO
	var body_count := 0
	for object in unique:
		for body in _bodies(object):
			center += body.global_position
			body_count += 1
	if body_count == 0:
		return false
	center /= float(body_count)
	var data: Array = []
	var body_ids: Dictionary = {}
	for index in unique.size():
		var object: Node2D = unique[index]
		var entry := {
			"kind": object.kind if object is RigidBody2D else "ragdoll",
			"position": object.global_position - center,
			"rotation": object.global_rotation,
			"resize": object.get_resize_percent(),
			"frozen": object.user_frozen,
			"flipped": _property(object, "flipped", false),
			"activated": _property(object, "activated", false),
			"program": _property(object, "program_source", ""),
			"bodies": [],
		}
		for body in _bodies(object):
			var body_name := "" if object is RigidBody2D else String(body.name)
			var id := "%d:%s" % [index, body_name]
			body_ids[body.get_instance_id()] = id
			entry.bodies.append({
				"id": id,
				"name": body_name,
				"position": body.global_position - center,
				"rotation": body.global_rotation,
				"flipped": _property(body, "flipped", false),
			})
		data.append(entry)
	var links: Array = []
	if is_instance_valid(connection_system):
		for record in connection_system.connections:
			var a = record.get("a")
			var b = record.get("b")
			if not is_instance_valid(a) or not is_instance_valid(b):
				continue
			if not body_ids.has(a.get_instance_id()) or not body_ids.has(b.get_instance_id()):
				continue
			var ends: Array = connection_system.endpoints(record)
			if ends.size() < 2:
				continue
			links.append({
				"kind": record.kind,
				"a": body_ids[a.get_instance_id()],
				"b": body_ids[b.get_instance_id()],
				"point_a": ends[0] - center,
				"point_b": ends[1] - center,
				"rest_length": record.get("rest_length", ends[0].distance_to(ends[1])),
			})
	snapshot = {"objects": data, "connections": links}
	return true

func paste_into(world: Node, at: Vector2) -> Array:
	var created: Array = []
	if snapshot.is_empty():
		return created
	var body_map: Dictionary = {}
	for entry in snapshot.objects:
		var object = world.create_object(entry.kind, at + entry.position, entry.rotation)
		if not is_instance_valid(object):
			continue
		object.resize_object(entry.resize)
		if bool(_property(object, "flipped", false)) != bool(entry.flipped) and object.has_method("flip_object"):
			object.flip_object()
		if _has_property(object, "activated"):
			object.activated = entry.activated
		if entry.kind == "cpu" and not String(entry.program).is_empty():
			object.set_program(entry.program)
		for part in entry.bodies:
			var body: RigidBody2D = object if object is RigidBody2D else object.get_node_or_null(NodePath(part.name))
			if not is_instance_valid(body):
				continue
			if bool(_property(body, "flipped", false)) != bool(part.flipped) and body.has_method("flip_object"):
				body.flip_object()
			body.global_position = at + part.position
			body.global_rotation = part.rotation
			body.linear_velocity = Vector2.ZERO
			body.angular_velocity = 0.0
			body.paused_velocity = Vector2.ZERO
			body.paused_spin = 0.0
			body.sleeping = false
			body_map[part.id] = body
		object.set_user_frozen(entry.frozen)
		created.append(object)
	for link in snapshot.connections:
		if not body_map.has(link.a) or not body_map.has(link.b):
			continue
		var node = world.connection_system.add_connection(link.kind, body_map[link.a], at + link.point_a, body_map[link.b], at + link.point_b)
		if not is_instance_valid(node):
			continue
		# Keep the copied slack, not just the endpoints' current separation.
		for record in world.connection_system.connections:
			if record.get("node") == node:
				record.rest_length = link.rest_length
				break
	return created

func _bodies(object: Node) -> Array:
	return [object] if object is RigidBody2D else object.bodies()

func _has_property(object: Object, name: String) -> bool:
	for item in object.get_property_list():
		if item.name == name:
			return true
	return false

func _property(object: Object, name: String, fallback: Variant) -> Variant:
	return object.get(name) if _has_property(object, name) else fallback
