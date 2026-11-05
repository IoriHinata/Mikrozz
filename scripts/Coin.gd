extends RigidBody2D
class_name MikrozzCoin

var tilt_controller

func _ready() -> void:
	add_to_group("coins")
	gravity_scale = 0.0
	mass = 0.32
	linear_damp = 0.8
	angular_damp = 1.5
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 4
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if tilt_controller != null:
		apply_central_force(tilt_controller.get_force() * 0.72)

func _draw() -> void:
	draw_circle(Vector2(0, 1), 9.0, Color("#d5b96d", 0.28))
	draw_circle(Vector2.ZERO, 7.5, Color("#f5d98d"))
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 32, Color("#fff4c9"), 1.5)
	draw_circle(Vector2(-2, -2), 1.8, Color("#fff9df"))
