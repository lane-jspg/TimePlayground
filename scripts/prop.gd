class_name PlaygroundProp
extends RigidBody2D

const SIZE := Vector2(46, 76)
var selected := false
var dragging := false
var drag_target := Vector2.ZERO
var local_grab := Vector2.ZERO
var rotation_input := 0.0

func _ready() -> void:
	mass = 2.0
	linear_damp = 0.15
	angular_damp = 0.8
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 4
	var material := PhysicsMaterial.new()
	material.friction = 0.65
	material.bounce = 0.12
	physics_material_override = material
	var shape := RectangleShape2D.new()
	shape.size = SIZE
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if dragging:
		# A damped spring at the actual grab point preserves collisions and momentum.
		var offset := local_grab.rotated(state.transform.get_rotation())
		var point := state.transform.origin + offset
		var point_velocity := state.linear_velocity + Vector2(-offset.y, offset.x) * state.angular_velocity
		var force := ((drag_target - point) * 110.0 - point_velocity * 24.0).limit_length(16000.0)
		state.apply_force(force, offset)
	if not is_zero_approx(rotation_input):
		state.apply_torque(rotation_input * 18000.0 - state.angular_velocity * 1800.0)

func _draw() -> void:
	var rect := Rect2(-SIZE / 2.0, SIZE)
	draw_rect(rect, Color("d3a66c"))
	draw_rect(Rect2(rect.position + Vector2(5, 5), SIZE - Vector2(10, 10)), Color("ad8051"), false, 2)
	draw_line(Vector2(-16, -27), Vector2(16, 27), Color("d3a66c"), 3)
	for p in [Vector2(-16, -28), Vector2(16, -28), Vector2(-16, 28), Vector2(16, 28)]:
		draw_circle(p, 2, Color("634e3b"))
	if selected:
		draw_rect(rect.grow(4), Color("69e2cf"), false, 2)
