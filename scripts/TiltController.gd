extends Node
class_name TiltController

var filtered_tilt := Vector2.ZERO
var sensitivity := 1.0
var smoothing := 7.5
var dead_zone := 0.08
var gravity_force := 1250.0

func _process(delta: float) -> void:
	var target := Vector2.ZERO
	if OS.has_feature("android"):
		var raw := Input.get_accelerometer()
		target = Vector2(raw.x, -raw.y) / 9.8
	else:
		target = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	target = (target * sensitivity).limit_length(1.0)
	if target.length() < dead_zone:
		target = Vector2.ZERO
	filtered_tilt = filtered_tilt.lerp(target, clampf(delta * smoothing, 0.0, 1.0))

func get_force() -> Vector2:
	return filtered_tilt * gravity_force
