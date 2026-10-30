extends SceneTree
## Real pointer/keyboard input regression test. Requires a graphical display.
## Optional -- --screenshots writes the rendered dialogs under /tmp.

var world
var failures := 0
var checks := 0
var held_buttons := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS rendered input: ", description)
	else:
		failures += 1
		push_error(description)

func frames(count: int) -> void:
	for i in count:
		await process_frame

func move_pointer(at: Vector2) -> void:
	Input.warp_mouse(at)
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = held_buttons
	Input.parse_input_event(event)
	await frames(2)

func mouse_button(at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = pressed
	if button == MOUSE_BUTTON_LEFT:
		if pressed: held_buttons |= MOUSE_BUTTON_MASK_LEFT
		else: held_buttons &= ~MOUSE_BUTTON_MASK_LEFT
	event.button_mask = held_buttons
	event.factor = 1.0
	Input.parse_input_event(event)
	await frames(2)

func click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await move_pointer(at)
	await mouse_button(at, true, button)
	await mouse_button(at, false, button)

func drag(from: Vector2, to: Vector2) -> void:
	await move_pointer(from)
	await mouse_button(from, true)
	await move_pointer(to)
	await mouse_button(to, false)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

func find_button(node: Node, label: String) -> Button:
	if node is Button and node.text.to_lower() == label.to_lower() and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := find_button(child, label)
		if found: return found
	return null

func click_text(label: String) -> void:
	var button := find_button(world, label)
	if not button:
		check(false, "visible button exists: " + label)
		return
	await click(button.get_global_rect().get_center())

func screenshot(path: String) -> void:
	if OS.get_cmdline_user_args().has("--screenshots"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await frames(2)
	await click(Vector2(640, 385))
	check(not world.main_menu.visible, "Play starts the game")
	var initial_count: int = world.objects.get_child_count()
	await click(Vector2(124, 218))
	check(world.selected_kind == "wheel" and world.objects.get_child_count() == initial_count, "choosing wheel selects it without spawning")
	await move_pointer(Vector2(800, 340))
	await key(KEY_Q)
	check(world.objects.get_child_count() == initial_count + 1 and world.selected.kind == "wheel", "Q spawns the selected wheel at the cursor")
	await click(Vector2(122, 148))
	check(world.category == "gates", "Gates category opens")
	await click(Vector2(56, 218))
	check(world.selected_kind == "and_gate" and world.objects.get_child_count() == initial_count + 1, "AND icon selects without spawning")
	await screenshot("/tmp/timeplayground-gates.png")
	await move_pointer(Vector2(950, 340))
	await key(KEY_E)
	check(world.selected.kind == "and_gate" and absf(wrapf(world.selected.rotation - PI / 2, -PI, PI)) < 0.1, "E creates a gate from selected category")
	# Pause before the group/CPU tests so physical movement cannot race clicks.
	await key(KEY_SPACE)
	check(world.paused, "Space pauses simulation through real keyboard input")
	var zoom_cursor := Vector2(880, 280)
	await move_pointer(zoom_cursor)
	var before_world: Vector2 = world.get_global_mouse_position()
	var original_zoom: Vector2 = world.camera.zoom
	await click(zoom_cursor, MOUSE_BUTTON_WHEEL_UP)
	check(world.camera.zoom.x > original_zoom.x, "mouse wheel up zooms the paused world")
	check(world.get_global_mouse_position().distance_to(before_world) < 0.1, "zoom preserves the world point beneath the cursor")
	await click(zoom_cursor, MOUSE_BUTTON_WHEEL_DOWN)
	check(world.camera.zoom.is_equal_approx(original_zoom) and world.get_global_mouse_position().distance_to(before_world) < 0.1, "mouse wheel down restores inverse zoom and cursor focus")
	await click(Vector2(56, 218), MOUSE_BUTTON_WHEEL_UP)
	check(world.camera.zoom.is_equal_approx(original_zoom), "scrolling over the object palette does not zoom the world")
	await click_text("Clear Everything")
	check(world.objects.get_child_count() == 0 and world.connection_system.connections.is_empty(), "Clear Everything removes objects and connections")
	await click(Vector2(54, 148))
	await click(Vector2(56, 218))
	await move_pointer(Vector2(500, 420))
	await key(KEY_Q)
	await move_pointer(Vector2(700, 420))
	await key(KEY_Q)
	check(world.objects.get_child_count() == 2, "two explicit Q presses create two boxes")
	await move_pointer(Vector2(400, 320))
	await mouse_button(Vector2(400, 320), true)
	await move_pointer(Vector2(800, 500))
	await screenshot("/tmp/timeplayground-marquee.png")
	await mouse_button(Vector2(800, 500), false)
	check(world.selected_owners.size() == 2 and world.group_selection, "empty-space drag rectangle selects both objects")
	await key(KEY_C)
	await move_pointer(Vector2(1000, 420))
	await key(KEY_V)
	check(world.objects.get_child_count() == 4 and world.selected_owners.size() == 2, "C/V copies and pastes the selected group")
	await click(Vector2(190, 148))
	check(world.category == "electronics", "Electronics category opens")
	await click(Vector2(124, 218))
	check(world.selected_kind == "lever" and world.objects.get_child_count() == 4, "lever icon selects without spawning")
	await move_pointer(Vector2(850, 250))
	await key(KEY_Q)
	check(world.selected.kind == "lever", "Q spawns lever")
	await key(KEY_F)
	check(world.selected.activated, "F activates selected lever")
	await click_text("Wire")
	check(world.tool == "wire", "bottom-right Wire tool is selectable")
	await click_text("Rope")
	check(world.tool == "rope", "bottom-right Rope tool is selectable")
	await click_text("Weld")
	check(world.tool == "weld", "bottom-right Weld tool is selectable")
	await click_text("Hand")
	await click(Vector2(56, 218))
	await move_pointer(Vector2(900, 360))
	await key(KEY_Q)
	check(world.selected.kind == "cpu", "CPU category icon and Q create CPU")
	var cpu = world.selected
	await click(Vector2(900, 360), MOUSE_BUTTON_RIGHT)
	check(world.context_menu.visible and find_button(world, "Edit instructions") != null, "CPU right-click exposes Edit instructions")
	check(world.context_menu.position.y + world.context_menu.size.y <= 720, "expanded CPU context menu stays inside viewport")
	await screenshot("/tmp/timeplayground-electronics.png")
	await click_text("Edit instructions")
	check(world.cpu_panel.visible and world.code_editor.has_focus(), "Edit instructions opens focused GDScript editor")
	await screenshot("/tmp/timeplayground-cpu-editor.png")
	var editor_zoom: Vector2 = world.camera.zoom
	await click(Vector2(600, 300), MOUSE_BUTTON_WHEEL_UP)
	check(world.camera.zoom.is_equal_approx(editor_zoom), "scrolling within CPU editor does not zoom the world")
	var count_before_typing: int = world.objects.get_child_count()
	await key(KEY_Q)
	check(world.objects.get_child_count() == count_before_typing, "typing Q in code editor does not spawn objects")
	world.code_editor.text = "extends RefCounted\n\nfunc tick(cpu, delta):\n\tcpu.output_power = true\n"
	await click_text("Apply instructions")
	check(not world.cpu_panel.visible and "cpu.output_power = true" in cpu.program_source, "Apply instructions compiles editor contents")
	await click_text("Rope")
	await click(Vector2(500, 420))
	await click(Vector2(700, 420))
	check(world.connection_system.connections.is_empty(), "separate clicks no longer create a connection")
	await drag(Vector2(500, 420), Vector2(600, 240))
	check(world.connection_system.connections.is_empty() and not is_instance_valid(world.link_body), "releasing a connection over empty space cancels the drag")
	await drag(Vector2(500, 420), Vector2(56, 218))
	check(world.connection_system.connections.is_empty() and not is_instance_valid(world.link_body), "releasing a connection over palette UI cancels the drag")
	await drag(Vector2(500, 420), Vector2(700, 420))
	check(world.connection_system.connections.size() == 1 and world.connection_system.connections[0].kind == "rope", "press-drag-release connects two bodies with rope")
	await click_text("Wire")
	await drag(Vector2(850, 250), Vector2(900, 360))
	check(world.connection_system.connections.size() == 2 and world.connection_system.connections[1].kind == "wire", "press-drag-release creates a directed lever-to-CPU wire")
	await click_text("Hand")
	await key(KEY_SPACE)
	for i in 8: await physics_frame
	check(cpu.powered and cpu.output_power, "activated lever powers CPU through the drawn wire")
	await screenshot("/tmp/timeplayground-wired-cpu.png")
	await click_text("Clear Everything")
	check(world.objects.get_child_count() == 0 and world.connection_system.connections.is_empty(), "Clear Everything also removes electronic objects and drawn wires")
	for i in 30: await click(Vector2(800, 300), MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(world.camera.zoom.x, 4.0), "repeated wheel-up clamps zoom at 4x")
	for i in 30: await click(Vector2(800, 300), MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(world.camera.zoom.x, 0.25), "repeated wheel-down clamps zoom at 0.25x")
	print("Rendered UI checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
