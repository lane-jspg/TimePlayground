extends SceneTree

const Ragdoll = preload("res://scripts/ragdoll.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + message)
	else:
		push_error("FAIL: " + message)
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func _initialize() -> void:
	call_deferred("run")

func assert_stable(puppet: Node2D, description: String) -> void:
	var stable := true
	for body in puppet.bodies():
		stable = stable and body.global_position.is_finite()
		stable = stable and body.linear_velocity.is_finite()
		stable = stable and body.global_position.distance_to(puppet.torso.global_position) < 400.0
		stable = stable and body.linear_velocity.length() < 10000.0
	check(stable, description)

func exclusion_count(puppet: Node2D) -> int:
	var result := 0
	for body in puppet.bodies():
		for other in puppet.bodies():
			if body != other and body.get_collision_exceptions().has(other):
				result += 1
	return result

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(500, 660)
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(4000, 80)
	var collider := CollisionShape2D.new()
	collider.shape = floor_shape
	floor_body.add_child(collider)
	world.add_child(floor_body)
	var puppet := Ragdoll.new()
	puppet.position = Vector2(500, 540)
	world.add_child(puppet)
	check(puppet.bodies().size() == 11, "ragdoll has eleven physical segments")
	var joints := 0
	for child in puppet.get_children():
		if child is PinJoint2D:
			joints += 1
	check(joints == 10, "ragdoll has ten physical joints")
	check(exclusion_count(puppet) == 110, "all 110 directional self collision exclusions exist after joints")
	var initial_phase: float = puppet._phase
	var touched_floor := false
	var max_torso_angle := 0.0
	var max_torso_spin := 0.0
	for i in 600:
		await physics_frame
		max_torso_angle = maxf(max_torso_angle, absf(puppet.torso.rotation))
		max_torso_spin = maxf(max_torso_spin, absf(puppet.torso.angular_velocity))
		for body in puppet.bodies():
			touched_floor = touched_floor or body.get_contact_count() > 0
	assert_stable(puppet, "ragdoll stays finite and joints remain together")
	check(exclusion_count(puppet) == 110, "all exclusions persist after live simulation")
	check(max_torso_angle < 0.8 and max_torso_spin < 3.0, "grounded AI stays upright without uncontrolled flips over five seconds")
	var above_floor := true
	for body in puppet.bodies():
		above_floor = above_floor and body.global_position.y < 630.0
	check(above_floor and touched_floor, "ragdoll collides with floor")
	check(puppet._phase > initial_phase, "AI controller advances")
	check(puppet._is_grounded(), "AI detects floor under feet")
	puppet.set_user_frozen(true)
	var frozen_position: Vector2 = puppet.torso.position
	var frozen_phase: float = puppet._phase
	await frames(20)
	check(puppet.torso.position.distance_to(frozen_position) < 0.01, "freeze stops ragdoll")
	check(is_equal_approx(puppet._phase, frozen_phase), "freeze stops AI")
	# A foreign falling box must still collide with the frozen puppet: broad
	# collision-mask disabling would incorrectly pass self-exclusion checks.
	var foreign = load("res://scripts/prop.gd").new()
	foreign.configure("box")
	foreign.position = puppet._parts["head"].global_position - Vector2(0, 140)
	world.add_child(foreign)
	var external_contact := false
	for i in 150:
		await physics_frame
		for body in foreign.get_colliding_bodies():
			if puppet.bodies().has(body): external_contact = true
	check(external_contact, "foreign dynamic box still collides with ragdoll")
	var excludes_only_self := true
	for body in puppet.bodies():
		excludes_only_self = excludes_only_self and not body.get_collision_exceptions().has(floor_body)
		excludes_only_self = excludes_only_self and not body.get_collision_exceptions().has(foreign)
	check(excludes_only_self, "floor and foreign bodies are never added to exclusions")
	world.remove_child(foreign)
	foreign.queue_free()
	var original_positions: Array[Vector2] = []
	var original_rotations: Array[float] = []
	for body in puppet.bodies():
		original_positions.append(body.global_position)
		original_rotations.append(body.rotation)
	var pivot: Vector2 = puppet.torso.global_position
	puppet.flip_object()
	var mirrored := true
	for i in puppet.bodies().size():
		var body = puppet.bodies()[i]
		var expected := Vector2(2.0 * pivot.x - original_positions[i].x, original_positions[i].y)
		mirrored = mirrored and body.global_position.is_equal_approx(expected)
		mirrored = mirrored and is_equal_approx(body.rotation, -original_rotations[i]) and body.flipped
	check(puppet.flipped and mirrored, "flip mirrors every limb pose and visual around current torso")
	check(exclusion_count(puppet) == 110, "flip retains all self collision exclusions after reanchoring joints")
	puppet.flip_object()
	var restored := true
	for i in puppet.bodies().size():
		restored = restored and puppet.bodies()[i].global_position.is_equal_approx(original_positions[i])
		restored = restored and is_equal_approx(puppet.bodies()[i].rotation, original_rotations[i])
	check(not puppet.flipped and restored, "double flip restores original physical pose")
	puppet.set_user_frozen(false)
	puppet.set_world_paused(true)
	var paused_position: Vector2 = puppet.torso.position
	var paused_phase: float = puppet._phase
	await frames(20)
	check(puppet.torso.position.distance_to(paused_position) < 0.01, "world pause stops ragdoll")
	check(is_equal_approx(puppet._phase, paused_phase), "world pause stops AI")
	for percent in [Vector2.ZERO, Vector2(100, 100), Vector2(50, 50), Vector2(25, 75)]:
		puppet.resize_object(percent)
		await frames(2)
		check(puppet.get_resize_percent() == percent and puppet.bodies().size() == 11, "resize %s keeps eleven parts and requested values" % percent)
		assert_stable(puppet, "resize %s remains finite while paused" % percent)
		check(puppet.torso.freeze, "resize %s preserves pause" % percent)
		check(exclusion_count(puppet) == 110, "resize %s restores all self collision exclusions" % percent)
	puppet.flip_object()
	puppet.resize_object(Vector2(50, 50))
	check(puppet.flipped and puppet.torso.flipped, "resize preserves mirrored visual state")
	puppet.set_world_paused(false)
	await frames(120)
	assert_stable(puppet, "resized ragdoll resumes physics")
	print("Ragdoll smoke checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
