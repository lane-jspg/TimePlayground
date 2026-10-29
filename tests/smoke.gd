extends SceneTree

var failures := 0
var checks := 0

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

func key(scene: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	scene._unhandled_input(event)

func all_nodes(node: Node) -> Array:
	var result: Array = [node]
	for child in node.get_children():
		result.append_array(all_nodes(child))
	return result

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var prop = scene.selected
	check(scene.main_menu.visible and not scene.game_ui.visible and prop.freeze, "main menu pauses simulation")
	check(not paused, "editing uses live SceneTree rather than pausing input")
	scene.play_game()
	check(not scene.main_menu.visible and scene.game_ui.visible and not prop.freeze, "play starts physics and palette")
	await frames(240)
	check(absf(prop.position.y - 584.0) < 3.0, "gravity settles textured box on floor")
	check(absf(prop.linear_velocity.y) < 15, "object rests on floor")
	check(scene.pick_prop(prop.global_position) == prop, "mouse query selects body")
	check(prop.sprite != null and prop.sprite.texture.resource_path.ends_with("box.png"), "box renders supplied texture")
	var has_line := false
	var has_old_hints := false
	var texture_buttons := 0
	for node in all_nodes(scene):
		has_line = has_line or node is Line2D
		if node is Label:
			has_old_hints = has_old_hints or "ЛКМ" in node.text or "Q / E" in node.text
		if node is TextureButton and node.texture_normal != null:
			texture_buttons += 1
	check(not has_line and not has_old_hints, "spring line and old bottom hints are absent")
	check(texture_buttons >= 5, "supplied spawn/play/exit button textures are present")
	scene.begin_grab(prop, prop.global_position)
	scene.move_grab(Vector2(800, 250))
	await frames(40)
	check(prop.position.y < 550, "mouse spring physically lifts body")
	scene.move_grab(Vector2(1100, 150))
	await frames(10)
	scene.release_grab()
	var release_velocity: Vector2 = prop.linear_velocity
	await frames(2)
	check(release_velocity.length() > 100 and prop.linear_velocity.length() > 100, "release retains throw momentum")
	scene.rotate_selection(1.0)
	await frames(20)
	check(prop.angular_velocity > 0.1, "rotation applies physical torque")
	prop.rotation_input = 0.0
	key(scene, KEY_G)
	check(is_equal_approx(Engine.time_scale, 0.2), "G enables slow motion")
	key(scene, KEY_G)
	check(is_equal_approx(Engine.time_scale, 1.0), "G restores normal time")

	prop.linear_velocity = Vector2(230, -30)
	prop.angular_velocity = 0.6
	var pre_pause_velocity: Vector2 = prop.linear_velocity
	var pre_pause_spin: float = prop.angular_velocity
	key(scene, KEY_SPACE)
	await frames(2)
	var stopped: Vector2 = prop.position
	await frames(10)
	check(prop.position.distance_to(stopped) < 0.01 and prop.world_paused, "pause stops physics")
	scene.begin_grab(prop, prop.global_position)
	var edit_target: Vector2 = prop.global_position + Vector2(120, -80)
	scene.move_grab(edit_target)
	scene.release_grab()
	await frames(3)
	check(prop.global_position.distance_to(edit_target) < 0.01, "paused objects remain draggable")
	var old_angle: float = prop.rotation
	scene.rotate_selection(0.25)
	check(is_equal_approx(prop.rotation, old_angle + 0.25), "paused objects remain rotatable")
	check(prop.paused_velocity.is_equal_approx(pre_pause_velocity) and is_equal_approx(prop.paused_spin, pre_pause_spin), "paused editing preserves saved momentum")
	key(scene, KEY_SPACE)
	check(prop.linear_velocity.is_equal_approx(pre_pause_velocity) and is_equal_approx(prop.angular_velocity, pre_pause_spin), "resume restores pre-pause momentum")
	await frames(5)
	check(prop.position.is_finite() and not prop.freeze, "physics resumes after paused editing")

	scene.open_context(prop, Vector2(1270, 710))
	check(scene.context_menu.visible and scene.freeze_button.text == "Freeze", "context menu opens with Freeze action")
	check(scene.context_menu.position.x <= 1110 and scene.context_menu.position.y <= 560, "context menu remains inside viewport")
	scene.context_action("freeze")
	check(prop.user_frozen and prop.freeze, "Freeze makes body static")
	scene.begin_grab(prop, prop.global_position)
	var frozen_target: Vector2 = prop.global_position + Vector2(-70, -40)
	scene.move_grab(frozen_target)
	scene.release_grab()
	await frames(5)
	check(prop.global_position.distance_to(frozen_target) < 0.01, "frozen objects remain draggable")
	scene.open_context(prop, Vector2(600, 300))
	check(scene.freeze_button.text == "Unfreeze", "frozen context offers Unfreeze")
	scene.context_action("freeze")
	check(not prop.user_frozen and not prop.freeze, "Unfreeze re-enables physics")
	scene.paused = true
	scene.update_time()
	scene.open_context(prop, Vector2(600, 300))
	scene.context_action("follow")
	check(scene.followed == prop, "Follow tracks selected body")
	var old_distance: float = scene.camera.position.distance_to(prop.global_position)
	scene._process(1.0 / 60.0)
	check(scene.camera.position.distance_to(prop.global_position) < old_distance, "camera follows object while time is paused")
	scene.open_context(prop, Vector2(600, 300))
	check(scene.follow_button.text == "Unfollow", "followed context offers Unfollow")
	scene.context_action("follow")
	check(scene.followed == null, "Unfollow stops tracking")
	scene.open_context(prop, Vector2(600, 300))
	scene.context_action("follow")
	var old_camera_position: Vector2 = scene.camera.position
	scene.move_camera(Vector2(40, -25))
	check(scene.followed == null and scene.camera.position.is_equal_approx(old_camera_position + Vector2(40, -25)), "manual camera movement cancels follow")
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	scene._unhandled_input(middle)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20, 15)
	old_camera_position = scene.camera.position
	scene._input(motion)
	check(scene.panning and scene.camera.position.is_equal_approx(old_camera_position - motion.relative), "held middle mouse pans camera")
	middle.pressed = false
	scene._input(middle)
	check(not scene.panning, "middle mouse release ends panning")
	var arrow := InputEventKey.new()
	arrow.physical_keycode = KEY_RIGHT
	arrow.keycode = KEY_RIGHT
	arrow.pressed = true
	Input.parse_input_event(arrow)
	Input.flush_buffered_events()
	await process_frame
	old_camera_position = scene.camera.position
	scene._process(1.0 / 60.0)
	var arrow_release := arrow.duplicate() as InputEventKey
	arrow_release.pressed = false
	Input.parse_input_event(arrow_release)
	Input.flush_buffered_events()
	check(scene.camera.position.x > old_camera_position.x, "arrow keys pan camera while paused")

	scene.open_context(prop, Vector2(600, 300))
	scene.context_action("resize")
	check(scene.resize_panel.visible and scene.resize_target == prop, "Resize opens size editor")
	scene.resize_x.value = 100
	scene.resize_y.value = 25
	scene.apply_resize()
	check(prop.body_size.is_equal_approx(Vector2(144, 36)) and not scene.resize_panel.visible, "resize scales X/Y independently")
	scene.open_resize(prop)
	scene.resize_x.value = 0
	scene.resize_y.value = 0
	scene.apply_resize()
	check(prop.body_size.x > 0 and prop.body_size.y > 0 and prop.body_size.x < 1, "zero resize remains nonzero for stable collision geometry")
	scene.open_resize(prop)
	scene.resize_x.value = 50
	scene.resize_y.value = 50
	scene.apply_resize()
	check(prop.body_size.is_equal_approx(Vector2(72, 72)) and prop.world_paused, "normal size restores geometry and preserves pause")

	scene.open_context(prop, Vector2(600, 300))
	scene.context_action("delete")
	check(scene.objects.get_child_count() == 0 and scene.selected == null, "context Delete removes selected owner")
	for kind in ["box", "wheel", "bottle"]:
		scene.spawn_from_palette(kind)
		check(scene.selected.kind == kind and scene.selected.sprite.texture != null and scene.selected.world_paused, "palette spawns textured %s while paused" % kind)
	key(scene, KEY_Q)
	check(scene.objects.get_child_count() == 4 and scene.selected.kind == "bottle", "Q spawns selected palette object")
	key(scene, KEY_E)
	check(scene.objects.get_child_count() == 5 and is_equal_approx(scene.selected.rotation, PI / 2), "E spawns rotated selected object")
	key(scene, KEY_R)
	check(scene.objects.get_child_count() == 4 and scene.selected == null, "R deletes selection")
	key(scene, KEY_C)
	check(scene.objects.get_child_count() == 0, "C clears every object without respawning")
	scene.spawn_from_palette("ragdoll")
	var doll = scene.selected.object_owner
	check(doll.bodies().size() == 11 and scene.selected.world_paused, "ragdoll palette spawns paused jointed test AI")
	var initial_positions: Array[Vector2] = []
	for body in doll.bodies(): initial_positions.append(body.global_position)
	scene.begin_grab(scene.selected, scene.selected.global_position)
	scene.move_grab(scene.selected.global_position + Vector2(100, -40))
	scene.release_grab()
	var aligned := true
	for i in doll.bodies().size():
		aligned = aligned and doll.bodies()[i].global_position.is_equal_approx(initial_positions[i] + Vector2(100, -40))
	check(aligned, "paused ragdoll drag moves all limbs together")
	scene.open_context(scene.selected, Vector2(600, 300))
	scene.context_action("freeze")
	var all_frozen := true
	for body in doll.bodies(): all_frozen = all_frozen and body.user_frozen
	check(all_frozen, "ragdoll Freeze applies to every segment")
	scene.open_resize(doll)
	scene.resize_x.value = 75
	scene.resize_y.value = 60
	scene.apply_resize()
	check(is_instance_valid(scene.selected) and scene.selected.object_owner == doll and doll.bodies().size() == 11, "ragdoll resize reselects rebuilt valid body")
	key(scene, KEY_R)
	check(scene.objects.get_child_count() == 0, "R deletes whole ragdoll rather than single limb")
	scene.paused = false
	scene.update_time()
	scene.spawn_from_palette("box")
	var previous_count: int = scene.objects.get_child_count()
	key(scene, KEY_ESCAPE)
	check(scene.main_menu.visible and scene.selected.world_paused, "Escape returns to main menu and stops physics")
	key(scene, KEY_Q)
	check(scene.objects.get_child_count() == previous_count, "main menu blocks gameplay spawn hotkeys")
	key(scene, KEY_ESCAPE)
	check(not scene.main_menu.visible and not scene.selected.world_paused, "Escape resumes game from menu")
	print("Smoke checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
