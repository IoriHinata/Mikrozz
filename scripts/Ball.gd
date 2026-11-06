extends RigidBody2D
class_name MikrozzBall

var tilt_controller
@export var radius := 13.0

func _ready() -> void:
	add_to_group("player")
	gravity_scale = 0.0
	mass = 1.0
	linear_damp = 2.8
	angular_damp = 2.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	var shape := CircleShape2D.new()
	shape.radius = radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if tilt_controller != null:
		apply_central_force(tilt_controller.get_force())
	var surface_mode := String(get_meta("surface_mode", "normal"))
	match surface_mode:
		"ice":
			linear_damp = 0.35
		"sand":
			linear_damp = 7.5
		"sticky":
			linear_damp = 10.0
			linear_velocity *= 0.985
		_:
			linear_damp = 2.8
	if linear_velocity.length() > 430.0:
		linear_velocity = linear_velocity.normalized() * 430.0

func _draw() -> void:
	draw_circle(Vector2(0, 2), radius + 1.5, Color("#d7e5dc"))
	draw_circle(Vector2.ZERO, radius, Color("#fffdf5"))
	draw_arc(Vector2.ZERO, radius - 1.0, 0.0, TAU, 48, Color("#b5cbbd"), 2.0)
	draw_circle(Vector2(-4, -4), 3.3, Color.WHITE)
