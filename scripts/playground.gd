extends Node2D

const Prop = preload("res://scripts/prop.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
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

func _ready() -> void:
	get_window().focus_exited.connect(release_grab)
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
	var palette := texture_rect("spawn_object_menu", Vector2(16, 80), Vector2(224, 362))
	palette.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(palette)
	for i in 3:
		var kinds := ["box", "wheel", "bottle"]
		var icons := ["box_spawn", "wheel_spawn", "soda_spawn"]
		var button := texture_button(icons[i], Vector2(12 + i * 68, 42), Vector2(56, 54))
		button.pressed.connect(spawn_from_palette.bind(kinds[i]))
		palette.add_child(button)
	var ragdoll_button := text_button("＋  Ragdoll", spawn_from_palette.bind("ragdoll"))
	ragdoll_button.position = Vector2(12, 114)
	ragdoll_button.size = Vector2(200, 42)
	palette.add_child(ragdoll_button)
	kind_label = Label.new()
	kind_label.position = Vector2(14, 180)
	kind_label.text = "Box"
	palette.add_child(kind_label)
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

func make_context_menu() -> void:
	context_menu = PanelContainer.new()
	context_menu.visible = false
	ui.add_child(context_menu)
	var list := VBoxContainer.new()
	context_menu.add_child(list)
	freeze_button = text_button("Freeze", context_action.bind("freeze"))
	follow_button = text_button("Follow", context_action.bind("follow"))
	list.add_child(freeze_button)
	list.add_child(follow_button)
	list.add_child(text_button("Delete", context_action.bind("delete")))
	list.add_child(text_button("Resize", context_action.bind("resize")))

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
	return paused or main_menu.visible

func show_main_menu() -> void:
	release_grab()
	context_menu.hide()
	close_resize()
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
	time_button.text = "▶" if paused else "Ⅱ"
	slow_button.text = "×0.2" if slow else "×1"

func spawn_from_palette(kind: String) -> void:
	selected_kind = kind
	kind_label.text = {"box": "Box", "wheel": "Wheel", "bottle": "Soda", "ragdoll": "Ragdoll"}[kind]
	spawn_prop(camera.get_screen_center_position())

func spawn_prop(at: Vector2, angle := 0.0) -> RigidBody2D:
	if selected_kind == "ragdoll":
		var doll := Ragdoll.new()
		doll.position = Vector2(at.x, minf(at.y, FLOOR_Y - 80))
		objects.add_child(doll)
		doll.set_world_paused(effective_pause() if main_menu else paused)
		select_prop(doll.torso)
		return doll.torso
	var prop := Prop.new()
	prop.configure(selected_kind)
	prop.position = Vector2(at.x, minf(at.y, FLOOR_Y - 80))
	prop.rotation = angle
	objects.add_child(prop)
	prop.set_world_paused(effective_pause() if main_menu else paused)
	select_prop(prop)
	return prop

func select_prop(prop: RigidBody2D) -> void:
	release_grab()
	if is_instance_valid(selected):
		selected.selected = false
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

func begin_grab(prop: RigidBody2D, at: Vector2) -> void:
	select_prop(prop)
	if not is_instance_valid(selected): return
	selected.local_grab = at - selected.global_position
	selected.local_grab = selected.local_grab.rotated(-selected.rotation)
	selected.drag_target = at
	selected.dragging = true
	selected.sleeping = false

func release_grab() -> void:
	panning = false
	if is_instance_valid(selected):
		selected.dragging = false
		selected.rotation_input = 0.0

func move_grab(at: Vector2) -> void:
	if not is_instance_valid(selected) or not selected.dragging: return
	selected.drag_target = at
	if selected.world_paused or selected.user_frozen:
		var target_position: Vector2 = at - selected.local_grab.rotated(selected.rotation)
		var offset: Vector2 = target_position - selected.global_position
		# Translate every limb together so editing a frozen ragdoll keeps its joints.
		for body in owner_bodies(selected.object_owner):
			body.global_position += offset

func rotate_selection(amount: float) -> void:
	if not is_instance_valid(selected): return
	if selected.world_paused or selected.user_frozen:
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
	select_prop(prop)
	if not is_instance_valid(prop):
		context_menu.hide()
		return
	context_target = prop.object_owner
	freeze_button.text = "Unfreeze" if context_target.user_frozen else "Freeze"
	follow_button.text = "Unfollow" if is_instance_valid(followed) and followed.object_owner == context_target else "Follow"
	context_menu.position = at.clamp(Vector2.ZERO, get_viewport_rect().size - Vector2(170, 160))
	context_menu.show()

func context_action(action: String) -> void:
	context_menu.hide()
	if not is_instance_valid(context_target): return
	match action:
		"freeze": context_target.set_user_frozen(not context_target.user_frozen)
		"follow":
			if is_instance_valid(followed) and followed.object_owner == context_target:
				followed = null
			else:
				followed = owner_bodies(context_target)[0]
		"delete": delete_object(context_target)
		"resize": open_resize(context_target)

func delete_object(object: Node) -> void:
	if not is_instance_valid(object): return
	if is_instance_valid(followed) and followed.object_owner == object: followed = null
	if is_instance_valid(selected) and selected.object_owner == object: select_prop(null)
	if resize_target == object: close_resize()
	context_menu.hide()
	objects.remove_child(object)
	object.queue_free()
	context_target = null

func clear_world() -> void:
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
	object.resize_object(Vector2(resize_x.value, resize_y.value))
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
		if event.button_index == MOUSE_BUTTON_LEFT: release_grab()
		if event.button_index == MOUSE_BUTTON_MIDDLE: panning = false
	if event is InputEventMouseMotion and panning:
		move_camera(-event.relative / camera.zoom)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if context_menu.visible and not context_menu.get_global_rect().has_point(event.position):
			context_menu.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if resize_panel.visible: close_resize()
		elif context_menu.visible: context_menu.hide()
		elif main_menu.visible: play_game()
		else: show_main_menu()
		return
	if main_menu.visible or resize_panel.visible: return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				context_menu.hide()
				begin_grab(pick_prop(get_global_mouse_position()), get_global_mouse_position())
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
				if is_instance_valid(selected): delete_object(selected.object_owner)
			KEY_C: clear_world()

func _process(delta: float) -> void:
	if main_menu.visible: return
	# Camera and edit speed use real time, independent of simulation time scale.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	if not resize_panel.visible:
		var axis := Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
		if axis.length_squared() > 0: move_camera(axis.normalized() * CAMERA_SPEED * real_delta)
		if is_instance_valid(selected):
			var rotation_axis := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
			if selected.world_paused or selected.user_frozen:
				rotate_selection(rotation_axis * 2.5 * real_delta)
			else:
				selected.rotation_input = rotation_axis
				if not is_zero_approx(rotation_axis): selected.sleeping = false
			move_grab(get_global_mouse_position())
	if is_instance_valid(followed):
		camera.position = camera.position.lerp(followed.global_position, 1.0 - exp(-8.0 * real_delta))
		camera.force_update_scroll()

func _exit_tree() -> void:
	Engine.time_scale = 1.0
