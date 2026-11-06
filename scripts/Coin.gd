extends RigidBody2D
class_name MikrozzCoin

var tilt_controller

# Pearls are deliberately slower and slightly larger than the player ball.
# This keeps them collectible and gives CCD enough time to resolve wall contacts.
const MAX_PEARL_SPEED := 185.0
const PEARL_RADIUS := 10.0

func _ready() -> void:
	add_to_group("coins")
	gravity_scale = 0.0
	mass = 0.8
	linear_damp = 3.2
	angular_damp = 2.5
	lock_rotation = true
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = 1
	collision_mask = 1
	var shape := CircleShape2D.new()
	shape.radius = PEARL_RADIUS
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if tilt_controller != null:
		# A pearl should drift gently with the board, not accelerate like the player.
		apply_central_force(tilt_controller.get_force() * 0.32)
	var speed := linear_velocity.length()
	if speed > MAX_PEARL_SPEED:
		linear_velocity = linear_velocity * (MAX_PEARL_SPEED / speed)

func _draw() -> void:
	draw_circle(Vector2(0, 1), 11.5, Color("#d5b96d", 0.28))
	draw_circle(Vector2.ZERO, 9.5, Color("#f5d98d"))
	draw_arc(Vector2.ZERO, 7.5, 0.0, TAU, 32, Color("#fff4c9"), 1.8)
	draw_circle(Vector2(-2.5, -2.5), 2.0, Color("#fff9df"))
