extends SceneTree

const Ragdoll = preload("res://scripts/ragdoll.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
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
	var initial_phase: float = puppet._phase
	var touched_floor := false
	for i in 240:
		await physics_frame
		for body in puppet.bodies():
			touched_floor = touched_floor or body.get_contact_count() > 0
	assert_stable(puppet, "ragdoll stays finite and joints remain together")
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
	puppet.resize_object(Vector2(50, 50))
	puppet.set_world_paused(false)
	await frames(120)
	assert_stable(puppet, "resized ragdoll resumes physics")
	print("Ragdoll smoke test failures: ", failures)
	quit(1 if failures else 0)
