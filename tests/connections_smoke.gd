extends SceneTree

const Prop = preload("res://scripts/prop.gd")
const Connections = preload("res://scripts/connection_system.gd")
var failures := 0
var checks := 0
var world: Node2D
var objects: Node2D
var system: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + description)
	else:
		push_error("FAIL: " + description)
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func spawn(kind: String, at: Vector2) -> RigidBody2D:
	var body := Prop.new()
	body.configure(kind)
	body.position = at
	body.gravity_scale = 0.0
	objects.add_child(body)
	return body

func connect_bodies(kind: String, a: RigidBody2D, b: RigidBody2D) -> Node:
	return system.add_connection(kind, a, a.global_position, b, b.global_position)

func cleanup() -> void:
	system.clear_all()
	for object in objects.get_children():
		objects.remove_child(object)
		object.queue_free()

func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	objects = Node2D.new()
	world.add_child(objects)
	system = Connections.new()
	world.add_child(system)
	system.configure(objects)
	var a := spawn("box", Vector2(200, 100))
	var b := spawn("box", Vector2(400, 100))
	a.set_user_frozen(true)
	check(system.add_connection("rope", a, a.position, a, a.position) == null, "connection rejects same-body endpoints")
	var rope := connect_bodies("rope", a, b)
	check(rope != null and system.connections.size() == 1, "rope stores both anchor bodies")
	b.position = Vector2(300, 100)
	await frames(20)
	check(b.position.distance_to(Vector2(300, 100)) < 0.1, "slack rope does not push bodies apart")
	b.position = Vector2(550, 100)
	await frames(120)
	check(a.position.distance_to(b.position) < 203.0 and b.linear_velocity.is_finite(), "taut rope limits separation with physical impulses")
	check(a.get_collision_exceptions().has(b) and b.get_collision_exceptions().has(a), "physical connection excludes mutual collisions")
	system.remove_connection(rope)
	check(not a.get_collision_exceptions().has(b) and not b.get_collision_exceptions().has(a), "removing rope restores original collision pair")
	a.add_collision_exception_with(b)
	b.add_collision_exception_with(a)
	rope = connect_bodies("rope", a, b)
	system.remove_connection(rope)
	check(a.get_collision_exceptions().has(b) and b.get_collision_exceptions().has(a), "connection removal preserves existing ragdoll exclusions")
	cleanup()
	await frames(2)

	a = spawn("box", Vector2(200, 100))
	b = spawn("box", Vector2(350, 100))
	a.set_user_frozen(true)
	b.gravity_scale = 1.0
	connect_bodies("rope", a, b)
	await frames(150)
	check(a.position.distance_to(b.position) < 156 and b.position.y > 130, "rope allows pendulum swing under gravity")
	var record: Dictionary = system.connections[0]
	var current_points: Array[Vector2] = system.endpoints(record)
	check(current_points.size() == 2 and current_points[1].distance_to(b.global_position) < 0.01, "rope visual endpoints follow moving bodies")
	system.world_paused = true
	a.set_world_paused(true)
	b.set_world_paused(true)
	var paused_pos := b.position
	await frames(10)
	check(b.position.distance_to(paused_pos) < 0.01, "paused ropes leave bodies stationary")
	system.world_paused = false
	cleanup()
	await frames(2)

	a = spawn("box", Vector2(100, 100))
	b = spawn("box", Vector2(240, 130))
	var local_pose := a.to_local(b.global_position)
	var weld := connect_bodies("weld", a, b)
	check(weld.get_child_count() == 2, "weld uses separated physical pins")
	b.apply_impulse(Vector2(0, 180), Vector2(25, 0))
	await frames(180)
	check(a.to_local(b.global_position).distance_to(local_pose) < 3.0, "weld holds relative translation under impact")
	check(absf(wrapf(b.rotation - a.rotation, -PI, PI)) < 0.08, "weld holds relative rotation under impact")
	rope = connect_bodies("rope", a, b)
	system.remove_connection(weld)
	check(a.get_collision_exceptions().has(b), "parallel physical link retains collision exclusion")
	system.remove_connection(rope)
	check(not a.get_collision_exceptions().has(b), "last physical link restores collision exclusion")
	cleanup()
	await frames(2)

	a = spawn("box", Vector2(100, 100))
	b = spawn("box", Vector2(240, 100))
	var anchored: Node = system.add_connection("wire", a, a.position + Vector2(36, 0), b, b.position)
	record = system.connections[0]
	a.resize_object(Vector2(100, 50))
	current_points = system.endpoints(record)
	check(current_points[0].is_equal_approx(a.position + Vector2(72, 0)), "normalized anchors track object resize")
	a.flip_object()
	current_points = system.endpoints(record)
	check(current_points[0].is_equal_approx(a.position - Vector2(72, 0)), "normalized anchors track object flip")
	check(not a.get_collision_exceptions().has(b), "electrical wires do not disable collisions")
	system.remove_connection(anchored)
	cleanup()
	await frames(2)

	# Electrical tests drive exact ticks so propagation order is deterministic.
	system.set_physics_process(false)
	var source_a := spawn("lever", Vector2(100, 100))
	var source_b := spawn("lever", Vector2(300, 100))
	var load_body := spawn("box", Vector2(700, 100))
	for kind in ["and_gate", "or_gate", "xor_gate", "not_gate"]:
		var gate := spawn(kind, Vector2(500, 100))
		connect_bodies("wire", source_a, gate)
		if kind != "not_gate": connect_bodies("wire", source_b, gate)
		connect_bodies("wire", gate, load_body)
		for bits in 4:
			source_a.activated = bool(bits & 1)
			source_b.activated = bool(bits & 2)
			source_a.output_power = source_a.activated
			source_b.output_power = source_b.activated
			system.propagate_power(1.0 / 120)
			var expected := false
			match kind:
				"and_gate": expected = source_a.activated and source_b.activated
				"or_gate": expected = source_a.activated or source_b.activated
				"xor_gate": expected = source_a.activated != source_b.activated
				"not_gate": expected = not source_a.activated
			check(gate.output_power == expected, "%s truth table inputs %d" % [kind, bits])
			system.propagate_power(1.0 / 120)
			check(load_body.powered == expected, "%s drives downstream wire after one tick" % kind)
		system.remove_for(gate)
		objects.remove_child(gate)
		gate.queue_free()
		system.propagate_power(1.0 / 120)
		check(not load_body.powered, "disconnecting gate removes downstream power")
	var cpu := spawn("cpu", Vector2(500, 100))
	check(cpu.set_program("extends RefCounted\nfunc tick(cpu, delta):\n\tcpu.set_meta(\"ticks\", cpu.get_meta(\"ticks\", 0) + 1)\n\tcpu.output_power = true\n"), "CPU program compiles for wire execution")
	connect_bodies("wire", source_a, cpu)
	source_a.activated = true
	source_a.output_power = true
	system.propagate_power(1.0 / 120)
	system.propagate_power(1.0 / 120)
	check(cpu.get_meta("ticks", 0) == 2 and cpu.output_power, "powered CPU executes GDScript every tick")
	source_a.activated = false
	source_a.output_power = false
	system.propagate_power(1.0 / 120)
	check(cpu.get_meta("ticks", 0) == 2 and not cpu.output_power, "unpowered CPU stops executing")
	source_a.activated = true
	source_a.output_power = true
	system.world_paused = true
	system.propagate_power(1.0 / 120)
	check(cpu.get_meta("ticks", 0) == 2, "simulation pause stops wire propagation and CPU code")
	system.world_paused = false
	var not_a := spawn("not_gate", Vector2(100, 400))
	var not_b := spawn("not_gate", Vector2(300, 400))
	connect_bodies("wire", not_a, not_b)
	connect_bodies("wire", not_b, not_a)
	system.propagate_power(1.0 / 120)
	check(not_a.output_power and not_b.output_power, "feedback loop reads synchronous old outputs")
	system.propagate_power(1.0 / 120)
	check(not not_a.output_power and not not_b.output_power, "feedback loop advances deterministically next tick")
	system.remove_for(cpu)
	check(system.connections.size() == 2, "remove_for removes only connections incident to owner")
	objects.remove_child(not_a)
	not_a.queue_free()
	await process_frame
	await process_frame
	check(system.connections.is_empty(), "deleted endpoint automatically removes stale links")
	cleanup()
	print("Connection checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
