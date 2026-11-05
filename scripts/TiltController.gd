extends Node
class_name TiltController

var filtered_tilt := Vector2.ZERO
var sensitivity := 1.15
var smoothing := 9.0
var dead_zone := 0.035
var gravity_force := 650.0
var sensor_offset := Vector2.ZERO
var calibrated := false
var touch_direction := Vector2.ZERO

func _ready() -> void:
	if OS.has_feature("android"):
		calibrate()

func _process(delta: float) -> void:
	var target := Vector2.ZERO
	if OS.has_feature("android"):
		var raw := Input.get_accelerometer()
		if not calibrated:
			sensor_offset = Vector2(raw.x, -raw.y)
			calibrated = true
		target = (Vector2(raw.x, -raw.y) - sensor_offset) / 9.8
	else:
		target = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if touch_direction != Vector2.ZERO:
		target = touch_direction
	target = (target * sensitivity).limit_length(1.0)
	if target.length() < dead_zone:
		target = Vector2.ZERO
	filtered_tilt = filtered_tilt.lerp(target, clampf(delta * smoothing, 0.0, 1.0))

func calibrate() -> void:
	var raw := Input.get_accelerometer()
	sensor_offset = Vector2(raw.x, -raw.y)
	filtered_tilt = Vector2.ZERO
	calibrated = true

func set_touch_direction(direction: Vector2) -> void:
	touch_direction = direction.limit_length(1.0)

func get_force() -> Vector2:
	return filtered_tilt * gravity_force
