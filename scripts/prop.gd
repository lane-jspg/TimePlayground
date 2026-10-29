class_name PlaygroundProp
extends RigidBody2D

const TEXTURES := {
	"box": preload("res://assets/textures/box.png"),
	"wheel": preload("res://assets/textures/wheel.png"),
	"bottle": preload("res://assets/textures/bottle.png"),
}
var kind := "box"
var base_size := Vector2(72, 72)
var body_size := Vector2(72, 72)
var resize_percent := Vector2(50, 50)
var object_owner: Node
var is_head := false
var selected := false
var dragging := false
var drag_target := Vector2.ZERO
var local_grab := Vector2.ZERO
var rotation_input := 0.0
var user_frozen := false
var world_paused := false
var paused_velocity := Vector2.ZERO
var paused_spin := 0.0
var collider: CollisionShape2D
var sprite: Sprite2D

func configure(type: String) -> void:
	kind = type
	match kind:
		"wheel": base_size = Vector2(68, 68)
		"bottle": base_size = Vector2(24, 72)
		_: base_size = Vector2(72, 72)
	body_size = base_size

func configure_part(size: Vector2, head := false) -> void:
	kind = "ragdoll"
	base_size = size
	body_size = size
	is_head = head

func _ready() -> void:
	if object_owner == null:
		object_owner = self
	if kind != "ragdoll":
		mass = 0.6 if kind == "bottle" else 2.0
	linear_damp = 0.15
	angular_damp = 0.6
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	var material := PhysicsMaterial.new()
	material.friction = 0.85 if kind == "wheel" else 0.65
	material.bounce = 0.12
	physics_material_override = material
	collider = CollisionShape2D.new()
	add_child(collider)
	if TEXTURES.has(kind):
		sprite = Sprite2D.new()
		sprite.texture = TEXTURES[kind]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
	update_geometry()

func update_geometry() -> void:
	body_size = base_size * Vector2(maxf(0.01, resize_percent.x / 50.0), maxf(0.01, resize_percent.y / 50.0))
	if collider:
		if kind == "wheel" or is_head:
			var shape := ConvexPolygonShape2D.new()
			var points := PackedVector2Array()
			for i in 24:
				points.append(Vector2(cos(i * TAU / 24), sin(i * TAU / 24)) * body_size * 0.5)
			shape.points = points
			collider.shape = shape
		else:
			var shape := RectangleShape2D.new()
			shape.size = body_size
			collider.shape = shape
	if sprite:
		sprite.scale = body_size / sprite.texture.get_size()
	queue_redraw()

func resize_object(percent: Vector2) -> void:
	resize_percent = percent.clamp(Vector2.ZERO, Vector2(100, 100))
	update_geometry()
	sleeping = false

func get_resize_percent() -> Vector2:
	return resize_percent

func set_world_paused(value: bool) -> void:
	if world_paused == value:
		return
	world_paused = value
	if value:
		paused_velocity = linear_velocity
		paused_spin = angular_velocity
		freeze = true
	else:
		freeze = user_frozen
		if not user_frozen:
			linear_velocity = paused_velocity
			angular_velocity = paused_spin
			sleeping = false

func set_user_frozen(value: bool) -> void:
	user_frozen = value
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	paused_velocity = Vector2.ZERO
	paused_spin = 0.0
	freeze = user_frozen or world_paused
	sleeping = false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if dragging:
		var offset := local_grab.rotated(state.transform.get_rotation())
		var point := state.transform.origin + offset
		var point_velocity := state.linear_velocity + Vector2(-offset.y, offset.x) * state.angular_velocity
		var force := ((drag_target - point) * 90.0 - point_velocity * 19.0).limit_length(12000.0) * mass
		state.apply_force(force, offset)
	if not is_zero_approx(rotation_input):
		state.apply_torque((rotation_input * 16000.0 - state.angular_velocity * 1600.0) * mass)

func _draw() -> void:
	if kind == "ragdoll":
		var color := Color("989898")
		if is_head:
			draw_set_transform(Vector2.ZERO, 0, body_size * 0.5)
			draw_circle(Vector2.ZERO, 1, color)
			draw_set_transform(Vector2.ZERO)
			# A small eye makes the AI's facing visible without extra textures.
			draw_circle(Vector2(body_size.x * 0.2, -body_size.y * 0.1), maxf(1, body_size.x * 0.06), Color("444444"))
		else:
			draw_rect(Rect2(-body_size / 2.0, body_size), color)
	if selected:
		draw_rect(Rect2(-body_size / 2.0, body_size).grow(2), Color(1, 1, 1, 0.6), false, 1)
