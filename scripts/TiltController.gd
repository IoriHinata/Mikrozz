extends Node
class_name TiltController

signal sensor_status_changed(available: bool, magnitude: float)

var filtered_tilt := Vector2.ZERO
var sensitivity := 1.65
var smoothing := 7.0
var dead_zone := 0.025
var gravity_force := 1150.0
var sensor_offset := Vector2.ZERO
var calibrated := false
var touch_direction := Vector2.ZERO
var sensor_available := false
var raw_sensor := Vector2.ZERO
var _status_timer := 0.0

func _ready() -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		call_deferred("calibrate")

func _process(delta: float) -> void:
	var target := Vector2.ZERO
	var has_sensor := false
	if OS.has_feature("android") or OS.has_feature("ios"):
		var accel := Input.get_accelerometer()
		var gravity := Input.get_gravity()
		var reading := accel
		if reading.length() < 1.0:
			reading = gravity
		if reading.length() > 1.0:
			has_sensor = true
			raw_sensor = Vector2(reading.x, -reading.y)
			if not calibrated:
				sensor_offset = raw_sensor
				calibrated = true
			target = (raw_sensor - sensor_offset) / 9.8
	else:
		target = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	sensor_available = has_sensor
	if touch_direction.length() > 0.01:
		target = touch_direction
	target = (target * sensitivity).limit_length(1.0)
	if target.length() < dead_zone:
		target = Vector2.ZERO
	filtered_tilt = filtered_tilt.lerp(target, clampf(delta * smoothing, 0.0, 1.0))
	_status_timer += delta
	if _status_timer >= 0.15:
		_status_timer = 0.0
		sensor_status_changed.emit(sensor_available, raw_sensor.length())

func calibrate() -> void:
	var accel := Input.get_accelerometer()
	var gravity := Input.get_gravity()
	var reading := accel if accel.length() > 1.0 else gravity
	if reading.length() > 1.0:
		raw_sensor = Vector2(reading.x, -reading.y)
		sensor_offset = raw_sensor
		calibrated = true
		filtered_tilt = Vector2.ZERO

func set_touch_direction(direction: Vector2) -> void:
	touch_direction = direction.limit_length(1.0)

func get_force() -> Vector2:
	return filtered_tilt * gravity_force
