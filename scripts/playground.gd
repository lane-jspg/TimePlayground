extends Node2D

const Prop = preload("res://scripts/prop.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
const Connections = preload("res://scripts/connection_system.gd")
const Clipboard = preload("res://scripts/object_clipboard.gd")
const FLOOR_Y := 620.0
const CAMERA_SPEED := 540.0
var selected: RigidBody2D
var followed: RigidBody2D
var slow := false
var paused := false
var selected_kind := "box"
var objects: Node2D
var camera: Camera2D
var panning := false
var ui: CanvasLayer
var main_menu: Control
var game_ui: Control
var context_menu: PanelContainer
var freeze_button: Button
var follow_button: Button
var resize_panel: PanelContainer
var resize_x: SpinBox
var resize_y: SpinBox
var time_button: Button
var slow_button: Button
var kind_label: Label
var context_target: Node
var resize_target: Node
var connection_system: Node2D
var clipboard = Clipboard.new()
var selected_owners: Array = []
var group_selection := false
var marquee := false
var marquee_start := Vector2.ZERO
var marquee_end := Vector2.ZERO
var tool := "hand"
var tool_buttons: Dictionary = {}
var link_body: RigidBody2D
var link_anchor := Vector2.ZERO
var context_position := Vector2.ZERO
var context_buttons: Dictionary = {}
var category := "objects"
var palette_items: Control
var category_title: Label
var cpu_panel: PanelContainer
var code_editor: CodeEdit
var code_status: Label
var cpu_target: RigidBody2D

func _ready() -> void:
	get_window().focus_exited.connect(cancel_interaction)
	make_world()
	make_ui()
	spawn_prop(Vector2(640, 440))
	show_main_menu()

func make_world() -> void:
	var texture := preload("res://assets/textures/game_background.png")
	# Both the wall and floor reuse the supplied background. A darker tint
	# distinguishes solid ground; no old procedural grid or floor art remains.
	for ground in [false, true]:
		var background := Sprite2D.new()
		background.texture = texture
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/grid_repeat.gdshader")
		background.material = material
		background.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		background.show_behind_parent = true
		background.centered = false
		background.region_enabled = true
		background.region_rect = Rect2(0, 0, 32768, 8192 if ground else 16384)
		background.position = Vector2(-16384, FLOOR_Y if ground else -8192)
		if ground:
			background.modulate = Color(0.58, 0.58, 0.58)
		add_child(background)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(0, FLOOR_Y + 4096)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(32768, 8192)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	add_child(floor_body)
	objects = Node2D.new()
	objects.name = "Objects"
	add_child(objects)
	connection_system = Connections.new()
	add_child(connection_system)
	connection_system.configure(objects)
	camera = Camera2D.new()
	camera.position = Vector2(640, 360)
	add_child(camera)
	camera.make_current()

func make_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	game_ui = Control.new()
	game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(game_ui)
	var logo := texture_rect("logo", Vector2(16, 18), Vector2(221, 35))
	game_ui.add_child(logo)
	make_palette()
	var clear_button := text_button("Clear Everything", clear_world)
	clear_button.position = Vector2(940, 18)
	clear_button.size = Vector2(180, 36)
	game_ui.add_child(clear_button)
	make_tool_picker()
	time_button = text_button("Ⅱ", toggle_pause)
	time_button.custom_minimum_size = Vector2.ZERO
	time_button.position = Vector2(1140, 18)
	time_button.size = Vector2(48, 36)
	game_ui.add_child(time_button)
	slow_button = text_button("×1", toggle_slow)
	slow_button.custom_minimum_size = Vector2.ZERO
	slow_button.position = Vector2(1196, 18)
	slow_button.size = Vector2(64, 36)
	game_ui.add_child(slow_button)
	make_context_menu()
	make_resize_menu()
	make_cpu_editor()
	main_menu = Control.new()
	main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(main_menu)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	main_menu.add_child(shade)
	main_menu.add_child(texture_rect("logo", Vector2(419, 220), Vector2(442, 70)))
	var play := texture_button("play_button", Vector2(580, 350), Vector2(120, 72))
	play.pressed.connect(play_game)
	main_menu.add_child(play)
	var exit := texture_button("exit_button", Vector2(587, 440), Vector2(106, 72))
	exit.pressed.connect(func(): get_tree().quit())
	main_menu.add_child(exit)

func texture_rect(asset: String, at: Vector2, dimensions: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = load("res://assets/textures/%s.png" % asset)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.position = at
	image.size = dimensions
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func texture_button(asset: String, at: Vector2, dimensions: Vector2) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load("res://assets/textures/%s.png" % asset)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.position = at
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_entered.connect(func(): button.modulate = Color(0.8, 0.8, 0.8))
	button.mouse_exited.connect(func(): button.modulate = Color.WHITE)
	return button

func text_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 34)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("262626")
	style.content_margin_left = 12
	style.content_margin_right = 12
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color("3a3a3a")
	button.add_theme_stylebox_override("hover", hover)
	button.pressed.connect(action)
	return button

func make_palette() -> void:
	var panel := Panel.new()
	panel.position = Vector2(16, 80)
	panel.size = Vector2(224, 432)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1f1f1f")
	panel.add_theme_stylebox_override("panel", style)
	game_ui.add_child(panel)
	category_title = Label.new()
	category_title.position = Vector2(12, 8)
	category_title.text = "Objects"
	category_title.add_theme_font_size_override("font_size", 20)
	panel.add_child(category_title)
	var categories := ["objects", "gates", "electronics"]
	for i in 3:
		var button := texture_button(categories[i] + "_category", Vector2(12 + i * 68, 42), Vector2(52, 52))
		button.tooltip_text = categories[i].capitalize()
		button.pressed.connect(show_category.bind(categories[i]))
		panel.add_child(button)
	palette_items = Control.new()
	palette_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette_items.position = Vector2(12, 112)
	panel.add_child(palette_items)
	kind_label = Label.new()
	kind_label.position = Vector2(14, 370)
	kind_label.text = "Box"
	panel.add_child(kind_label)
	show_category("objects")

func show_category(value: String) -> void:
	category = value
	category_title.text = value.capitalize()
	for child in palette_items.get_children():
		palette_items.remove_child(child)
		child.queue_free()
	var kinds: Array = {"objects": ["box", "wheel", "bottle"], "gates": ["and_gate", "not_gate", "or_gate", "xor_gate"], "electronics": ["cpu", "lever"]}[value]
	for i in kinds.size():
		var kind: String = kinds[i]
		var icon := "soda_spawn" if kind == "bottle" else kind + "_spawn"
		var button := texture_button(icon, Vector2((i % 3) * 68, floori(i / 3.0) * 68), Vector2(56, 54))
		button.pressed.connect(spawn_from_palette.bind(kind))
		palette_items.add_child(button)
	if value == "objects":
		var doll_button := text_button("Ragdoll", spawn_from_palette.bind("ragdoll"))
		doll_button.position = Vector2(0, 76)
		doll_button.size = Vector2(200, 42)
		palette_items.add_child(doll_button)

func make_tool_picker() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	row.offset_left = -412
	row.offset_top = -60
	row.offset_right = -16
	row.offset_bottom = -20
	game_ui.add_child(row)
	for name in ["hand", "rope", "weld", "wire"]:
		var button := text_button(name.capitalize(), set_tool.bind(name))
		button.custom_minimum_size = Vector2(94, 40)
		button.tooltip_text = "Source → target" if name == "wire" else ""
		row.add_child(button)
		tool_buttons[name] = button
	set_tool("hand")

func set_tool(value: String) -> void:
	release_grab()
	marquee = false
	link_body = null
	tool = value
	for name in tool_buttons:
		tool_buttons[name].modulate = Color.WHITE if name == value else Color(0.6, 0.6, 0.6)
	queue_redraw()

func make_context_menu() -> void:
	context_menu = PanelContainer.new()
	context_menu.visible = false
	ui.add_child(context_menu)
	var list := VBoxContainer.new()
	context_menu.add_child(list)
	for action in ["freeze", "follow", "activate", "flip", "copy", "paste", "disconnect", "delete", "resize", "edit instructions"]:
		var button := text_button(action.capitalize(), context_action.bind(action))
		list.add_child(button)
		context_buttons[action] = button
	freeze_button = context_buttons["freeze"]
	follow_button = context_buttons["follow"]

func make_cpu_editor() -> void:
	cpu_panel = PanelContainer.new()
	cpu_panel.position = Vector2(220, 94)
	cpu_panel.custom_minimum_size = Vector2(840, 540)
	cpu_panel.hide()
	ui.add_child(cpu_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	cpu_panel.add_child(margin)
	var list := VBoxContainer.new()
	margin.add_child(list)
	var title := Label.new()
	title.text = "CPU / Edit instructions — GDScript"
	list.add_child(title)
	var description := Label.new()
	description.text = "tick(cpu, delta) runs while powered; set cpu.output_power. Native Godot API: each tick must return."
	list.add_child(description)
	code_editor = CodeEdit.new()
	code_editor.custom_minimum_size = Vector2(800, 340)
	code_editor.gutters_draw_line_numbers = true
	code_editor.indent_use_spaces = false
	var highlighter := CodeHighlighter.new()
	for word in ["extends", "func", "var", "if", "else", "return", "true", "false"]:
		highlighter.add_keyword_color(word, Color("d69fe8"))
	code_editor.syntax_highlighter = highlighter
	list.add_child(code_editor)
	code_status = Label.new()
	code_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_status.custom_minimum_size.x = 800
	list.add_child(code_status)
	list.add_child(text_button("Apply instructions", save_cpu_program))
	list.add_child(text_button("Cancel", close_cpu_editor))

func open_cpu_editor(body: RigidBody2D) -> void:
	if body.kind != "cpu": return
	release_grab()
	cpu_target = body
	code_editor.text = body.program_source
	code_status.text = ""
	cpu_panel.show()
	code_editor.grab_focus()
	update_time()

func save_cpu_program() -> void:
	if not is_instance_valid(cpu_target):
		close_cpu_editor()
		return
	if cpu_target.set_program(code_editor.text):
		close_cpu_editor()
	else:
		code_status.text = cpu_target.program_error

func close_cpu_editor() -> void:
	cpu_target = null
	if cpu_panel: cpu_panel.hide()
	if main_menu: update_time()

func make_resize_menu() -> void:
	resize_panel = PanelContainer.new()
	resize_panel.position = Vector2(490, 245)
	resize_panel.custom_minimum_size = Vector2(300, 220)
	resize_panel.visible = false
	ui.add_child(resize_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	resize_panel.add_child(margin)
	var list := VBoxContainer.new()
	margin.add_child(list)
	var title := Label.new()
	title.text = "Resize  /  50 = 1×"
	list.add_child(title)
	for axis in ["X", "Y"]:
		var row := HBoxContainer.new()
		list.add_child(row)
		var label := Label.new()
		label.text = axis
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size.x = 130
		row.add_child(slider)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 100
		spin.step = 1
		spin.custom_minimum_size.x = 85
		row.add_child(spin)
		slider.value_changed.connect(func(value): spin.set_value_no_signal(value))
		spin.value_changed.connect(func(value): slider.set_value_no_signal(value))
		spin.set_meta("slider", slider)
		if axis == "X": resize_x = spin
		else: resize_y = spin
	list.add_child(text_button("Apply", apply_resize))
	list.add_child(text_button("Cancel", close_resize))

func effective_pause() -> bool:
	return paused or main_menu.visible or cpu_panel.visible

func show_main_menu() -> void:
	cancel_interaction()
	context_menu.hide()
	close_resize()
	close_cpu_editor()
	main_menu.show()
	game_ui.hide()
	update_time()

func play_game() -> void:
	main_menu.hide()
	game_ui.show()
	update_time()

func toggle_pause() -> void:
	paused = not paused
	update_time()

func toggle_slow() -> void:
	slow = not slow
	update_time()

func update_time() -> void:
	Engine.time_scale = 0.2 if slow else 1.0
	# No SceneTree pause: physics bodies freeze, editing and the camera stay live.
	for object in objects.get_children():
		object.set_world_paused(effective_pause())
	connection_system.world_paused = effective_pause()
	time_button.text = "▶" if paused else "Ⅱ"
	slow_button.text = "×0.2" if slow else "×1"

func spawn_from_palette(kind: String) -> void:
	selected_kind = kind
	kind_label.text = kind.replace("_gate", "").capitalize()
	set_tool("hand")

func create_object(kind: String, at: Vector2, angle := 0.0) -> Node:
	if kind == "ragdoll":
		var doll := Ragdoll.new()
		doll.position = Vector2(at.x, minf(at.y, FLOOR_Y - 80))
		objects.add_child(doll)
		doll.set_world_paused(effective_pause())
		return doll
	var prop := Prop.new()
	prop.configure(kind)
	prop.position = Vector2(at.x, minf(at.y, FLOOR_Y - 80))
	prop.rotation = angle
	objects.add_child(prop)
	prop.set_world_paused(effective_pause())
	return prop

func spawn_prop(at: Vector2, angle := 0.0) -> RigidBody2D:
	var object := create_object(selected_kind, at, angle)
	select_prop(owner_bodies(object)[0])
	return selected

func select_prop(prop: RigidBody2D) -> void:
	release_grab()
	selected = prop
	selected_owners.clear()
	group_selection = false
	if is_instance_valid(prop): selected_owners.append(prop.object_owner)
	queue_redraw()

func select_owners(owners: Array) -> void:
	release_grab()
	selected_owners = owners.duplicate()
	group_selection = not owners.is_empty()
	selected = owner_bodies(owners[0])[0] if not owners.is_empty() else null
	queue_redraw()

func owner_bounds(object: Node) -> Rect2:
	var bounds := Rect2()
	var initialized := false
	for body in owner_bodies(object):
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var point: Vector2 = body.global_position + (body.body_size * 0.5 * corner).rotated(body.rotation)
			if not initialized:
				bounds = Rect2(point, Vector2.ZERO)
				initialized = true
			else: bounds = bounds.expand(point)
	return bounds

func begin_marquee(at: Vector2) -> void:
	select_prop(null)
	marquee = true
	marquee_start = at
	marquee_end = at

func finish_marquee(at: Vector2) -> void:
	if not marquee: return
	marquee = false
	marquee_end = at
	var rect := Rect2(marquee_start, marquee_end - marquee_start).abs()
	var owners: Array = []
	if rect.size.length() > 5:
		for object in objects.get_children():
			if rect.intersects(owner_bounds(object)): owners.append(object)
	select_owners(owners)

func copy_selection() -> void:
	clipboard.copy_objects(selected_owners, connection_system)

func paste_selection(at: Vector2) -> void:
	select_owners(clipboard.paste_into(self, at))

func pick_prop(at: Vector2) -> RigidBody2D:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = at
	var hits := get_world_2d().direct_space_state.intersect_point(query, 64)
	for i in range(hits.size() - 1, -1, -1):
		if hits[i].collider is PlaygroundProp:
			return hits[i].collider
	return null

func begin_grab(prop: RigidBody2D, at: Vector2) -> void:
	if is_instance_valid(prop) and group_selection and selected_owners.has(prop.object_owner):
		release_grab()
		selected = prop
	else:
		select_prop(prop)
	if not is_instance_valid(selected): return
	if selected.user_frozen and not selected.world_paused: return
	selected.local_grab = at - selected.global_position
	selected.local_grab = selected.local_grab.rotated(-selected.rotation)
	selected.drag_target = at
	selected.dragging = true
	selected.sleeping = false

func cancel_interaction() -> void:
	release_grab()
	marquee = false
	link_body = null
	queue_redraw()

func release_grab() -> void:
	panning = false
	if is_instance_valid(selected):
		selected.dragging = false
		selected.rotation_input = 0.0

func move_grab(at: Vector2) -> void:
	if not is_instance_valid(selected) or not selected.dragging: return
	selected.drag_target = at
	if selected.user_frozen and not selected.world_paused: return
	if selected.world_paused:
		var target_position: Vector2 = at - selected.local_grab.rotated(selected.rotation)
		var offset: Vector2 = target_position - selected.global_position
		# Translate every limb together so editing a frozen ragdoll keeps its joints.
		for object in selected_owners:
			for body in owner_bodies(object):
				body.global_position += offset

func rotate_selection(amount: float) -> void:
	if not is_instance_valid(selected): return
	if selected.user_frozen and not selected.world_paused: return
	if selected.world_paused:
		var pivot: Vector2 = selected.global_position
		for body in owner_bodies(selected.object_owner):
			body.global_position = pivot + (body.global_position - pivot).rotated(amount)
			body.rotation += amount
	else:
		selected.rotation_input = amount
		selected.sleeping = false

func owner_bodies(object: Node) -> Array:
	return [object] if object is RigidBody2D else object.bodies()

func open_context(prop: RigidBody2D, at: Vector2) -> void:
	release_grab()
	if is_instance_valid(prop):
		if not selected_owners.has(prop.object_owner): select_prop(prop)
		selected = prop
	context_target = prop.object_owner if is_instance_valid(prop) else (selected_owners[0] if not selected_owners.is_empty() else null)
	context_position = get_global_mouse_position()
	var has_target := is_instance_valid(context_target)
	for action in context_buttons:
		context_buttons[action].visible = has_target or action == "paste"
	context_buttons["paste"].disabled = clipboard.snapshot.is_empty()
	context_buttons["activate"].visible = has_target and context_target is RigidBody2D and context_target.kind in ["lever", "and_gate", "not_gate", "or_gate", "xor_gate", "cpu"]
	context_buttons["edit instructions"].visible = has_target and context_target is RigidBody2D and context_target.kind == "cpu"
	if has_target:
		freeze_button.text = "Unfreeze" if context_target.user_frozen else "Freeze"
		follow_button.text = "Unfollow" if is_instance_valid(followed) and followed.object_owner == context_target else "Follow"
		context_buttons["activate"].text = "Deactivate" if context_buttons["activate"].visible and context_target.activated else "Activate"
	context_menu.reset_size()
	var menu_size := context_menu.get_combined_minimum_size()
	context_menu.position = at.clamp(Vector2.ZERO, get_viewport_rect().size - menu_size)
	context_menu.show()

func context_action(action: String) -> void:
	context_menu.hide()
	if action == "paste":
		paste_selection(context_position)
		return
	if action == "copy":
		copy_selection()
		return
	if not is_instance_valid(context_target): return
	match action:
		"freeze":
			var freeze_state: bool = not context_target.user_frozen
			for object in selected_owners: object.set_user_frozen(freeze_state)
		"follow":
			if is_instance_valid(followed) and followed.object_owner == context_target: followed = null
			else: followed = owner_bodies(context_target)[0]
		"activate": activate_selection()
		"flip":
			for object in selected_owners:
				object.flip_object()
				connection_system.refresh_for(object)
		"disconnect":
			for object in selected_owners: connection_system.remove_for(object)
		"delete":
			for object in selected_owners.duplicate(): delete_object(object)
		"resize": open_resize(context_target)
		"edit instructions": open_cpu_editor(context_target)

func activate_selection() -> void:
	for object in selected_owners:
		if object is RigidBody2D and object.has_method("toggle_activation"):
			object.toggle_activation()

func link_click(body: RigidBody2D, at: Vector2) -> void:
	if not is_instance_valid(body):
		link_body = null
	elif not is_instance_valid(link_body):
		link_body = body
		link_anchor = (at - body.global_position).rotated(-body.rotation) / body.body_size
	elif body != link_body:
		connection_system.add_connection(tool, link_body, link_body.global_position + (link_anchor * link_body.body_size).rotated(link_body.rotation), body, at)
		link_body = null
	queue_redraw()

func delete_object(object: Node) -> void:
	if not is_instance_valid(object): return
	connection_system.remove_for(object)
	selected_owners.erase(object)
	if cpu_target == object: close_cpu_editor()
	if is_instance_valid(followed) and followed.object_owner == object: followed = null
	if is_instance_valid(selected) and selected.object_owner == object: selected = null
	if resize_target == object: close_resize()
	context_menu.hide()
	objects.remove_child(object)
	object.queue_free()
	context_target = null

func clear_world() -> void:
	connection_system.clear_all()
	link_body = null
	marquee = false
	close_cpu_editor()
	select_prop(null)
	followed = null
	context_target = null
	context_menu.hide()
	close_resize()
	for object in objects.get_children():
		objects.remove_child(object)
		object.queue_free()

func open_resize(object: Node) -> void:
	release_grab()
	resize_target = object
	var percent: Vector2 = object.get_resize_percent()
	resize_x.value = percent.x
	resize_y.value = percent.y
	resize_x.get_meta("slider").value = percent.x
	resize_y.get_meta("slider").value = percent.y
	resize_panel.show()

func close_resize() -> void:
	resize_target = null
	if resize_panel: resize_panel.hide()

func apply_resize() -> void:
	if not is_instance_valid(resize_target):
		close_resize()
		return
	var object := resize_target
	var was_followed: bool = is_instance_valid(followed) and followed.object_owner == object
	select_prop(null)
	if not object is RigidBody2D: connection_system.remove_for(object)
	object.resize_object(Vector2(resize_x.value, resize_y.value))
	connection_system.refresh_for(object)
	select_prop(owner_bodies(object)[0])
	if was_followed: followed = selected
	close_resize()

func move_camera(offset: Vector2) -> void:
	followed = null
	camera.position += offset
	camera.force_update_scroll()

func _input(event: InputEvent) -> void:
	# Releases must also arrive when the pointer ends its drag over a UI control.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if marquee: finish_marquee(get_global_mouse_position())
			release_grab()
		if event.button_index == MOUSE_BUTTON_MIDDLE: panning = false
	if event is InputEventMouseMotion and panning:
		move_camera(-event.relative / camera.zoom)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if context_menu.visible and not context_menu.get_global_rect().has_point(event.position):
			context_menu.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if cpu_panel.visible: close_cpu_editor()
		elif resize_panel.visible: close_resize()
		elif context_menu.visible: context_menu.hide()
		elif main_menu.visible: play_game()
		else: show_main_menu()
		return
	if main_menu.visible or resize_panel.visible or cpu_panel.visible: return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				context_menu.hide()
				var at := get_global_mouse_position()
				var body := pick_prop(at)
				if tool != "hand": link_click(body, at)
				elif body: begin_grab(body, at)
				else: begin_marquee(at)
			MOUSE_BUTTON_RIGHT: open_context(pick_prop(get_global_mouse_position()), event.position)
			MOUSE_BUTTON_MIDDLE:
				release_grab()
				panning = true
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q: spawn_prop(get_global_mouse_position())
			KEY_E: spawn_prop(get_global_mouse_position(), PI / 2)
			KEY_G: toggle_slow()
			KEY_SPACE: toggle_pause()
			KEY_R:
				for object in selected_owners.duplicate(): delete_object(object)
			KEY_C: copy_selection()
			KEY_V: paste_selection(get_global_mouse_position())
			KEY_F: activate_selection()

func _process(delta: float) -> void:
	if main_menu.visible: return
	# Camera and edit speed use real time, independent of simulation time scale.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	if not resize_panel.visible and not cpu_panel.visible:
		var axis := Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
		if axis.length_squared() > 0: move_camera(axis.normalized() * CAMERA_SPEED * real_delta)
		if is_instance_valid(selected):
			var rotation_axis := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
			if selected.world_paused:
				rotate_selection(rotation_axis * 2.5 * real_delta)
			elif not selected.user_frozen:
				selected.rotation_input = rotation_axis
				if not is_zero_approx(rotation_axis): selected.sleeping = false
			move_grab(get_global_mouse_position())
	if marquee: marquee_end = get_global_mouse_position()
	if marquee or group_selection or is_instance_valid(link_body): queue_redraw()
	if is_instance_valid(followed):
		camera.position = camera.position.lerp(followed.global_position, 1.0 - exp(-8.0 * real_delta))
		camera.force_update_scroll()

func _draw() -> void:
	if marquee:
		var rect := Rect2(marquee_start, marquee_end - marquee_start).abs()
		draw_rect(rect, Color(0.8, 0.8, 1, 0.12))
		draw_rect(rect, Color(0.8, 0.8, 1, 0.8), false, 1)
	elif group_selection and (not is_instance_valid(selected) or not selected.dragging):
		for object in selected_owners:
			if is_instance_valid(object): draw_rect(owner_bounds(object).grow(3), Color(1, 1, 1, 0.65), false, 1)
	if is_instance_valid(link_body):
		var point: Vector2 = link_body.global_position + (link_anchor * link_body.body_size).rotated(link_body.rotation)
		draw_circle(point, 4, Color.WHITE)
		draw_line(point, get_global_mouse_position(), Color(0.8, 0.8, 0.8, 0.7), 1)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
