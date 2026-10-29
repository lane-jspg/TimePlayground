extends SceneTree

var failures := 0

func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS: " + description)
	else:
		push_error("FAIL: " + description)
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var prop = scene.selected
	await frames(240)
	check(prop.position.y > 570 and prop.position.y < 600, "gravity and floor collision")
	check(absf(prop.linear_velocity.y) < 15, "object rests on floor")
	check(scene.pick_prop(prop.position) == prop, "mouse query selects body")
	prop.dragging = true
	prop.sleeping = false
	prop.local_grab = Vector2.ZERO
	prop.drag_target = Vector2(800, 250)
	await frames(40)
	check(prop.position.y < 550, "mouse spring lifts body")
	prop.drag_target = Vector2(1100, 150)
	await frames(10)
	prop.dragging = false
	var release_velocity: Vector2 = prop.linear_velocity
	await frames(2)
	check(release_velocity.length() > 100 and prop.linear_velocity.length() > 100, "release retains throw momentum")
	prop.rotation_input = 1.0
	await frames(20)
	check(prop.angular_velocity > 0.1, "rotation applies torque")
	prop.rotation_input = 0.0
	scene.slow = true
	scene.update_time()
	check(is_equal_approx(Engine.time_scale, 0.2), "slow motion enabled")
	scene.slow = false
	scene.paused = true
	scene.update_time()
	await frames(2)
	var stopped: Vector2 = prop.position
	await frames(10)
	check(prop.position.distance_to(stopped) < 0.01, "pause freezes physics")
	scene.paused = false
	scene.update_time()
	scene.reset_world()
	check(scene.objects.get_child_count() == 1, "reset leaves one object")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	event.pressed = true
	scene._unhandled_input(event)
	event.physical_keycode = KEY_E
	scene._unhandled_input(event)
	check(scene.objects.get_child_count() == 3, "Q and E spawn objects")
	check(is_equal_approx(scene.selected.rotation, PI / 2), "E spawns horizontal object")
	event.physical_keycode = KEY_DELETE
	scene._unhandled_input(event)
	await process_frame
	check(scene.objects.get_child_count() == 2, "delete removes selection")
	print("Smoke test failures: ", failures)
	quit(1 if failures else 0)
