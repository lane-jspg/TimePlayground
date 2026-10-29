extends SceneTree
## Rendered UI regression test. Requires a real or virtual X11 display.
## Optional -- --screenshots writes validation images under /tmp.

var world
var failures := 0
func _initialize() -> void:
	call_deferred("capture")
func check(ok: bool, text: String) -> void:
	if ok: print("PASS rendered input: ",text)
	else:
		failures += 1
		push_error(text)
func click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	Input.warp_mouse(at)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func screenshot(path: String) -> void:
	if OS.get_cmdline_user_args().has("--screenshots"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
func capture() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await screenshot("/tmp/timeplayground-menu-fixed.png")
	await click(Vector2(640,385))
	check(not world.main_menu.visible,"Play button opens game")
	await click(Vector2(124,148))
	check(world.selected_kind == "wheel" and world.objects.get_child_count()==2,"palette wheel creates wheel")
	await click(Vector2(128,214))
	check(world.selected_kind == "ragdoll" and world.objects.get_child_count()==3,"palette ragdoll creates ragdoll")
	for i in 90: await physics_frame
	world.selected_kind = "bottle"
	world.spawn_prop(Vector2(900,500))
	for i in 90: await physics_frame
	world.toggle_pause()
	# Test actual right-click dispatch against a physical body's screen location.
	var body = world.selected
	var at: Vector2 = world.get_viewport().get_canvas_transform() * body.global_position
	await click(at, MOUSE_BUTTON_RIGHT)
	check(world.context_menu.visible,"right click opens context for body")
	await screenshot("/tmp/timeplayground-game-fixed.png")
	var menu_at: Vector2 = world.context_menu.position
	await click(menu_at+Vector2(75,18))
	check(body.user_frozen,"Freeze menu button freezes object")
	await click(at, MOUSE_BUTTON_RIGHT)
	await click(world.context_menu.position+Vector2(75,132))
	check(world.resize_panel.visible,"Resize menu button opens editor")
	await screenshot("/tmp/timeplayground-resize.png")
	world.resize_x.value=75
	world.resize_y.value=25
	await click(Vector2(635,380))
	check(not world.resize_panel.visible,"Apply resize button closes editor")
	check(body.body_size == body.base_size*Vector2(1.5,0.5),"Apply resize changes body dimensions")
	print("Rendered input failures: ",failures)
	quit(1 if failures else 0)
