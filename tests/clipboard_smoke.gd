extends SceneTree

const Clipboard = preload("res://scripts/object_clipboard.gd")

class Sandbox extends Node2D:
	const Prop = preload("res://scripts/prop.gd")
	const Ragdoll = preload("res://scripts/ragdoll.gd")
	const Connections = preload("res://scripts/connection_system.gd")
	var objects: Node2D
	var connection_system: Node2D
	func _ready() -> void:
		objects = Node2D.new()
		add_child(objects)
		connection_system = Connections.new()
		add_child(connection_system)
		connection_system.configure(objects)
		connection_system.world_paused = true
	func create_object(kind: String, at: Vector2, angle := 0.0) -> Node2D:
		var object
		if kind == "ragdoll":
			object = Ragdoll.new()
		else:
			object = Prop.new()
			object.configure(kind)
		object.position = at
		object.rotation = angle
		objects.add_child(object)
		object.set_world_paused(true)
		return object

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS clipboard: ", label)
	else:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func contains_object(value: Variant) -> bool:
	if value is Object: return true
	if value is Array:
		for child in value:
			if contains_object(child): return true
	if value is Dictionary:
		for child in value.values():
			if contains_object(child): return true
	return false

func run() -> void:
	var world := Sandbox.new()
	root.add_child(world)
	var box = world.create_object("box", Vector2(300, 300), 0.4)
	box.resize_object(Vector2(75, 25))
	box.flip_object()
	box.set_user_frozen(true)
	box.paused_velocity = Vector2(120, 50)
	var lever = world.create_object("lever", Vector2(440, 330), -0.2)
	lever.activated = true
	var cpu = world.create_object("cpu", Vector2(560, 330))
	var source := "extends RefCounted\nfunc tick(cpu, _delta):\n\tcpu.set_meta(\"copied_tick\", true)\n\tcpu.output_power = true\n"
	check(cpu.set_program(source), "CPU custom program compiles before copying")
	var doll = world.create_object("ragdoll", Vector2(700, 420))
	doll.resize_object(Vector2(60, 80))
	doll.flip_object()
	doll.set_user_frozen(true)
	var head: RigidBody2D = doll.get_node("head")
	head.rotation = 0.15
	var external = world.create_object("wheel", Vector2(1000, 200))
	world.connection_system.add_connection("rope", box, box.global_position + Vector2(10, 0), lever, lever.global_position)
	world.connection_system.connections[0].rest_length = 250.0
	world.connection_system.add_connection("wire", lever, lever.global_position, cpu, cpu.global_position)
	world.connection_system.add_connection("weld", cpu, cpu.global_position, head, head.global_position)
	world.connection_system.add_connection("wire", cpu, cpu.global_position, external, external.global_position)
	var clipboard := Clipboard.new()
	check(clipboard.copy_objects([box, lever, cpu, doll, box], world.connection_system), "copies group and deduplicates owners")
	check(clipboard.snapshot.objects.size() == 4, "snapshot has four unique owners")
	check(clipboard.snapshot.connections.size() == 3, "only internal ropes, welds and wires copied")
	check(not contains_object(clipboard.snapshot), "snapshot stores no live Node references")
	var frozen_snapshot := clipboard.snapshot.duplicate(true)
	world.connection_system.clear_all()
	for object in world.objects.get_children():
		world.objects.remove_child(object)
		object.queue_free()
	await process_frame
	check(world.objects.get_child_count() == 0, "originals can be deleted before paste")
	var pasted: Array = clipboard.paste_into(world, Vector2(1200, 300))
	check(pasted.size() == 4, "paste restores every owner after original deletion")
	check(world.connection_system.connections.size() == 3, "paste restores internal connections")
	check(pasted[0].body_size.is_equal_approx(Vector2(108, 36)), "independent resize dimensions preserved")
	check(pasted[0].flipped and pasted[0].user_frozen and pasted[0].world_paused, "flip and frozen/paused states preserved")
	check(pasted[0].linear_velocity == Vector2.ZERO and pasted[0].paused_velocity == Vector2.ZERO, "clone momentum starts at zero")
	check(pasted[1].activated, "lever activation preserved")
	check(pasted[2].program_source == source, "CPU custom program preserved")
	check(pasted[3].bodies().size() == 11 and pasted[3].flipped and pasted[3].user_frozen, "ragdoll structure, flip and freeze preserved")
	check(is_equal_approx(pasted[3].get_node("head").rotation, 0.15), "ragdoll limb pose preserved")
	check(is_equal_approx(world.connection_system.connections[0].rest_length, 250.0), "slack rope keeps original rest length")
	var all_offsets_match := true
	for index in pasted.size():
		var entry: Dictionary = frozen_snapshot.objects[index]
		for part in entry.bodies:
			var body: Node2D = pasted[index] if pasted[index] is RigidBody2D else pasted[index].get_node(NodePath(part.name))
			all_offsets_match = all_offsets_match and body.global_position.is_equal_approx(Vector2(1200, 300) + part.position)
	check(all_offsets_match, "relative group layout and all ragdoll body positions preserved")
	var twice: Array = clipboard.paste_into(world, Vector2(1700, 200))
	check(twice.size() == 4 and world.objects.get_child_count() == 8, "repeated paste creates independent owners")
	check(world.connection_system.connections.size() == 6, "repeated paste creates independent links")
	check(not clipboard.copy_objects([], world.connection_system) and clipboard.snapshot == frozen_snapshot, "empty copy preserves useful clipboard")
	check(twice[0].get_instance_id() != pasted[0].get_instance_id(), "copies have independent identities")
	print("Clipboard checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
