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
var maze: MazeGenerator
var ball: MikrozzBall
var tilt: TiltController
var ui: MikrozzUI
var level_locked := false
var viewport_size := Vector2.ZERO
var start_point := Vector2.ZERO

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
	# Connect before generate(): generation emits these signals synchronously.
	maze.hazard_created.connect(_connect_hazard)
	maze.exit_created.connect(_connect_exit)
	maze.coin_body_created.connect(_connect_coin)
	maze.generate(level, viewport_size)
	start_point = maze.start_position
	coins_total = maze.get_tree().get_nodes_in_group("coins").size()
	ui.make_gate_buttons(maze.gate_bodies.size())
	_spawn_ball()
	ui.hide_result()
	ui.set_message("Tilt to roll  •  Hold matching gates open")
	_update_hud()

func _spawn_ball() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	ball = BallScript.new()
	ball.position = start_point
	ball.tilt_controller = tilt
	add_child(ball)

func _connect_hazard(area: Area2D) -> void:
	area.body_entered.connect(_on_hazard_body)

func _connect_exit(area: Area2D) -> void:
	area.body_entered.connect(_on_exit_body)

func _connect_coin(coin: RigidBody2D) -> void:
	coin.body_entered.connect(_on_coin_body.bind(coin))

func _on_coin_body(body: Node, coin: Node2D) -> void:
	if body.is_in_group("player") and is_instance_valid(coin):
		score += 1
		coin.queue_free()
		_update_hud()
		if score >= coins_total:
			ui.set_message("All coins collected! Find the exit")

func _on_hazard_body(body: Node) -> void:
	if body.is_in_group("player"):
		_lose_life()
	elif body.is_in_group("coins"):
		body.queue_free()

func _on_exit_body(body: Node) -> void:
	if body.is_in_group("player") and not level_locked:
		level_locked = true
		var config := ConfigFile.new()
		best_score = maxi(best_score, score)
		config.set_value("records", "best_score", best_score)
		config.save("user://records.cfg")
		ui.show_result("MAZE CLEARED!", "Coins: %d / %d     Best: %d" % [score, coins_total, best_score], true)

func _lose_life() -> void:
	if level_locked:
		return
	level_locked = true
	lives -= 1
	_update_hud()
	if lives <= 0:
		best_score = maxi(best_score, score)
		var config := ConfigFile.new()
		config.set_value("records", "best_score", best_score)
		config.save("user://records.cfg")
		ui.show_result("OUT OF LIVES", "Level %d  •  Coins: %d" % [level, score], false)
	else:
		_respawn_all.call_deferred()

func _respawn_all() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	_build_level_preserving_lives()

func _build_level_preserving_lives() -> void:
	if is_instance_valid(maze):
		maze.queue_free()
	maze = MazeScript.new()
	add_child(maze)
	# Reconnect before procedural generation so no object signal is missed.
	maze.hazard_created.connect(_connect_hazard)
	maze.exit_created.connect(_connect_exit)
	maze.coin_body_created.connect(_connect_coin)
	maze.generate(level, viewport_size)
	start_point = maze.start_position
	coins_total = maze.get_tree().get_nodes_in_group("coins").size()
	ui.make_gate_buttons(maze.gate_bodies.size())
	_spawn_ball()
	level_locked = false
	ui.set_message("Room reset — coins restored")
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
	level = 1
	lives = 3
	_start_level()
