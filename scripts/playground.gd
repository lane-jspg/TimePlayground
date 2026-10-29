extends Node2D

const Prop = preload("res://scripts/prop.gd")
const FLOOR_Y := 620.0
var selected: RigidBody2D
var slow := false
var paused := false
var status: Label
var objects: Node2D
var drag_line: Line2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().focus_exited.connect(release_grab)
	objects = Node2D.new()
	objects.name = "Objects"
	objects.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(objects)
	make_wall(Vector2(640, 660), Vector2(1280, 80))
	make_wall(Vector2(-25, 310), Vector2(50, 1400))
	make_wall(Vector2(1305, 310), Vector2(50, 1400))
	drag_line = Line2D.new()
	drag_line.width = 2
	drag_line.default_color = Color("69e2cf")
	add_child(drag_line)
	make_ui()
	spawn_prop(Vector2(640, 420))

func make_wall(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	var shape := RectangleShape2D.new()
	shape.size = size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func make_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "TIME / PLAYGROUND"
	title.position = Vector2(32, 24)
	title.add_theme_font_size_override("font_size", 26)
	layer.add_child(title)
	var hint := Label.new()
	hint.text = "ФИЗИЧЕСКАЯ ПЕСОЧНИЦА   /   01"
	hint.position = Vector2(34, 62)
	hint.modulate = Color("8394a7")
	layer.add_child(hint)
	status = Label.new()
	status.position = Vector2(32, 100)
	status.modulate = Color("69e2cf")
	layer.add_child(status)
	var controls := Label.new()
	controls.position = Vector2(32, 651)
	controls.text = "Q / E  создать ящик    •    ЛКМ  схватить / бросить    •    A / D  вращать\nT  время ×0.2    •    Пробел  пауза    •    Delete  удалить    •    R  сбросить"
	controls.add_theme_font_size_override("font_size", 17)
	layer.add_child(controls)

func spawn_prop(at: Vector2, angle := 0.0) -> RigidBody2D:
	var prop := Prop.new()
	prop.position = Vector2(clampf(at.x, 30, 1250), clampf(at.y, 45, FLOOR_Y - 45))
	prop.rotation = angle
	objects.add_child(prop)
	select_prop(prop)
	return prop

func select_prop(prop: RigidBody2D) -> void:
	if is_instance_valid(selected):
		selected.dragging = false
		selected.selected = false
		selected.rotation_input = 0.0
		selected.queue_redraw()
	selected = prop
	if is_instance_valid(selected):
		selected.selected = true
		selected.queue_redraw()

func pick_prop(at: Vector2) -> RigidBody2D:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = at
	var hits := get_world_2d().direct_space_state.intersect_point(query, 64)
	for i in range(hits.size() - 1, -1, -1):
		if hits[i].collider is PlaygroundProp:
			return hits[i].collider
	return null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			select_prop(pick_prop(get_global_mouse_position()))
			if is_instance_valid(selected):
				selected.local_grab = selected.to_local(get_global_mouse_position())
				selected.drag_target = get_global_mouse_position()
				selected.dragging = true
				selected.sleeping = false
		elif is_instance_valid(selected):
			# Do not clear velocity: release retains the spring's physical impulse.
			selected.dragging = false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q: spawn_prop(get_global_mouse_position())
			KEY_E: spawn_prop(get_global_mouse_position(), PI / 2)
			KEY_T:
				slow = not slow
				update_time()
			KEY_SPACE:
				paused = not paused
				update_time()
			KEY_DELETE:
				if is_instance_valid(selected):
					selected.queue_free()
					selected = null
			KEY_R: reset_world()

func release_grab() -> void:
	if is_instance_valid(selected):
		selected.dragging = false
		selected.rotation_input = 0.0

func update_time() -> void:
	Engine.time_scale = 0.2 if slow else 1.0
	# Freeze bodies without freezing input, drawing, or the interface.
	get_tree().paused = paused

func reset_world() -> void:
	select_prop(null)
	for prop in objects.get_children():
		objects.remove_child(prop)
		prop.queue_free()
	spawn_prop(Vector2(640, 420))

func _process(_delta: float) -> void:
	status.text = "%s   /   %d ОБЪЕКТОВ" % ["ПАУЗА" if paused else ("ВРЕМЯ ×0.2" if slow else "ВРЕМЯ ×1.0"), objects.get_child_count()]
	drag_line.clear_points()
	if is_instance_valid(selected):
		selected.drag_target = get_global_mouse_position()
		selected.rotation_input = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		if not is_zero_approx(selected.rotation_input):
			selected.sleeping = false
		if selected.dragging:
			drag_line.add_point(selected.to_global(selected.local_grab))
			drag_line.add_point(selected.drag_target)

func _draw() -> void:
	for x in range(0, 1281, 40):
		draw_line(Vector2(x, 0), Vector2(x, FLOOR_Y), Color(0.1, 0.14, 0.19, 0.45))
	for y in range(20, 621, 40):
		draw_line(Vector2(0, y), Vector2(1280, y), Color(0.1, 0.14, 0.19, 0.45))
	draw_rect(Rect2(0, FLOOR_Y, 1280, 100), Color("1c2531"))
	draw_line(Vector2(0, FLOOR_Y), Vector2(1280, FLOOR_Y), Color("637688"), 3)
	for x in range(0, 1280, 24):
		draw_line(Vector2(x, FLOOR_Y + 5), Vector2(x - 12, FLOOR_Y + 17), Color("344352"), 2)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
