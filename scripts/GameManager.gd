extends Node2D
const BallScript = preload("res://scripts/Ball.gd")
const MazeScript = preload("res://scripts/MazeGenerator.gd")
const TiltScript = preload("res://scripts/TiltController.gd")
const UIScript = preload("res://scripts/UI.gd")
var level := 1
var lives := 3
var score := 0
var coins_total := 0
var best_score := 0
var maze
var ball
var tilt
var ui
var level_locked := false
var viewport_size := Vector2.ZERO
var start_point := Vector2.ZERO
var total_run_score := 0

func _ready() -> void:
	randomize()
	viewport_size = get_viewport_rect().size
	var config := ConfigFile.new()
	if config.load("user://records.cfg") == OK:
		best_score = int(config.get_value("records", "best_score", 0))
	tilt = TiltScript.new()
	add_child(tilt)
	ui = UIScript.new()
	add_child(ui)
	ui.setup(viewport_size)
	ui.gate_pressed.connect(_on_gate_pressed)
	ui.restart_requested.connect(_restart_run)
	ui.next_level_requested.connect(_next_level)
	ui.calibrate_requested.connect(_calibrate_tilt)
	ui.touch_direction_changed.connect(_set_touch_direction)
	tilt.sensor_status_changed.connect(_on_sensor_status)
	_start_run()

func _start_run() -> void:
	level = 1
	lives = 3
	total_run_score = 0
	_start_level()

func _start_level() -> void:
	level_locked = false
	score = 0
	_build_level()

func _build_level() -> void:
	if is_instance_valid(maze):
		maze.queue_free()
	maze = MazeScript.new()
	add_child(maze)
	maze.hazard_created.connect(_connect_hazard)
	maze.exit_created.connect(_connect_exit)
	maze.coin_body_created.connect(_connect_coin)
	maze.generate(level, viewport_size)
	start_point = maze.start_position
	coins_total = _count_coins()
	ui.make_gate_buttons(maze.gate_bodies.size())
	_spawn_ball()
	ui.hide_result()
	ui.set_message("Collect every pearl • Hold a gate button to pass")
	_update_hud()

func _count_coins() -> int:
	var total := 0
	for child in maze.get_children():
		if child is RigidBody2D and child.is_in_group("coins"):
			total += 1
	return total

func _spawn_ball() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	ball = BallScript.new()
	ball.position = start_point
	ball.set("tilt_controller", tilt)
	add_child(ball)

func _connect_hazard(area: Area2D) -> void:
	area.body_entered.connect(_on_hazard_body)

func _connect_exit(area: Area2D) -> void:
	area.body_entered.connect(_on_exit_body)

func _connect_coin(coin: RigidBody2D) -> void:
	coin.set("tilt_controller", tilt)
	coin.body_entered.connect(_on_coin_body.bind(coin))

func _on_coin_body(body: Node, coin: Node2D) -> void:
	if body.is_in_group("player") and is_instance_valid(coin) and not level_locked:
		score += 1
		total_run_score += 1
		coin.queue_free()
		_update_hud()
		if score >= coins_total:
			ui.set_message("All pearls found! Reach the golden exit")

func _on_hazard_body(body: Node) -> void:
	if body.is_in_group("player"):
		_lose_life()

func _on_exit_body(body: Node) -> void:
	if not body.is_in_group("player") or level_locked:
		return
	if score < coins_total:
		ui.set_message("Find all %d pearls first (%d/%d)" % [coins_total, score, coins_total])
		return
	level_locked = true
	best_score = maxi(best_score, total_run_score)
	var config := ConfigFile.new()
	config.set_value("records", "best_score", best_score)
	config.save("user://records.cfg")
	ui.show_result("MAZE CLEARED!", "Level %d • Run score %d • Best %d" % [level, total_run_score, best_score], true)

func _lose_life() -> void:
	if level_locked:
		return
	level_locked = true
	lives -= 1
	_update_hud()
	if lives <= 0:
		ui.show_result("OUT OF LIVES", "Run score: %d" % total_run_score, false)
	else:
		_respawn_all.call_deferred()

func _respawn_all() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	if is_instance_valid(maze):
		maze.queue_free()
	maze = MazeScript.new()
	add_child(maze)
	maze.hazard_created.connect(_connect_hazard)
	maze.exit_created.connect(_connect_exit)
	maze.coin_body_created.connect(_connect_coin)
	maze.generate(level, viewport_size)
	start_point = maze.start_position
	coins_total = _count_coins()
	score = 0
	ui.make_gate_buttons(maze.gate_bodies.size())
	_spawn_ball()
	level_locked = false
	ui.set_message("Room reset — try another route")
	_update_hud()

func _on_gate_pressed(index: int, pressed: bool) -> void:
	if is_instance_valid(maze):
		maze.set_gate_open(index, pressed)

func _update_hud() -> void:
	ui.set_hud(level, lives, score, coins_total)

func _next_level() -> void:
	level += 1
	_start_level()

func _restart_run() -> void:
	_start_run()

func _calibrate_tilt() -> void:
	tilt.calibrate()
	ui.set_message("Tilt calibrated — keep phone level for a moment")

func _set_touch_direction(direction: Vector2) -> void:
	tilt.set_touch_direction(direction)

func _on_sensor_status(available: bool, magnitude: float) -> void:
	ui.set_sensor_status(available, magnitude)
