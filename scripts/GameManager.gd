extends Node2D
const BallScript = preload("res://scripts/Ball.gd")
const MazeScript = preload("res://scripts/MazeGenerator.gd")
const TiltScript = preload("res://scripts/TiltController.gd")
const UIScript = preload("res://scripts/UI.gd")
const AudioScript = preload("res://scripts/AudioManager.gd")
const PROGRESS_PATH := "user://progress.cfg"
const SETTINGS_PATH := "user://settings.cfg"

var level := 0
var lives := 3
var score := 0
var coins_total := 0
var best_score := 0
var total_run_score := 0
var tutorial_completed := false
var maze
var ball
var tilt
var ui
var audio
var level_locked := false
var viewport_size := Vector2.ZERO
var start_point := Vector2.ZERO
var extra_balls: Array[RigidBody2D] = []
var exit_balls_entered: Dictionary = {}
var exit_required := 1
var music_volume := 0.32
var sfx_volume := 0.75
var vibration_enabled := true

func _ready() -> void:
	randomize()
	viewport_size = get_viewport_rect().size
	_load_settings()
	_load_progress()
	var records := ConfigFile.new()
	if records.load("user://records.cfg") == OK:
		best_score = int(records.get_value("records", "best_score", 0))
	tilt = TiltScript.new()
	add_child(tilt)
	tilt.sensitivity = _saved_sensitivity
	audio = AudioScript.new()
	add_child(audio)
	audio.set_music_volume(music_volume)
	audio.set_sfx_volume(sfx_volume)
	ui = UIScript.new()
	add_child(ui)
	ui.setup(viewport_size)
	ui.set_settings_defaults(music_volume, sfx_volume, tilt.sensitivity, vibration_enabled)
	ui.gate_pressed.connect(_on_gate_pressed)
	ui.restart_requested.connect(_restart_run)
	ui.next_level_requested.connect(_next_level)
	ui.calibrate_requested.connect(_calibrate_tilt)
	ui.touch_direction_changed.connect(_set_touch_direction)
	ui.settings_changed.connect(_on_setting_changed)
	ui.settings_pause_changed.connect(_on_settings_pause_changed)
	ui.tutorial_finished.connect(_on_tutorial_finished)
	tilt.sensor_status_changed.connect(_on_sensor_status)
	_start_level()
	if level == 0:
		ui.show_tutorial()

var _saved_sensitivity := 1.65

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	_saved_sensitivity = clampf(float(cfg.get_value("controls", "sensitivity", _saved_sensitivity)), 0.5, 3.0)
	vibration_enabled = bool(cfg.get_value("controls", "vibration", vibration_enabled))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "sensitivity", tilt.sensitivity if is_instance_valid(tilt) else _saved_sensitivity)
	cfg.set_value("controls", "vibration", vibration_enabled)
	var error := cfg.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save settings: %s" % error)

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		level = maxi(0, int(cfg.get_value("progress", "level", 0)))
		total_run_score = maxi(0, int(cfg.get_value("progress", "total_score", 0)))
		tutorial_completed = bool(cfg.get_value("progress", "tutorial_completed", false))
		if not tutorial_completed:
			level = 0

func _save_progress(saved_level: int = -1) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "level", maxi(0, saved_level if saved_level >= 0 else level))
	cfg.set_value("progress", "total_score", total_run_score)
	cfg.set_value("progress", "best_score", best_score)
	cfg.set_value("progress", "last_level_score", score)
	cfg.set_value("progress", "tutorial_completed", tutorial_completed)
	var error := cfg.save(PROGRESS_PATH)
	if error != OK:
		push_warning("Could not save progress: %s" % error)

func _start_run() -> void:
	level = 1 if tutorial_completed else 0
	lives = 3
	total_run_score = 0
	_save_progress()
	_start_level()

func _start_level() -> void:
	level_locked = false
	score = 0
	_save_progress()
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
	maze.pressure_button_activated.connect(_on_pressure_button_activated)
	maze.pop_ball_popped.connect(_on_pop_ball_popped)
	maze.level_mechanic_event.connect(_on_level_mechanic_event)
	maze.boss_defeated.connect(_on_boss_defeated)
	start_point = maze.start_position
	exit_required = 2 if level >= 8 else 1
	exit_balls_entered.clear()
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
	for extra in extra_balls:
		if is_instance_valid(extra):
			extra.queue_free()
	extra_balls.clear()
	ball = BallScript.new()
	ball.position = start_point
	ball.set("tilt_controller", tilt)
	add_child(ball)
	if level >= 8:
		var partner: RigidBody2D = BallScript.new()
		partner.position = start_point + Vector2(maze.cell_size * 0.22, 0.0)
		partner.set("tilt_controller", tilt)
		partner.set_meta("echo_ball", true)
		add_child(partner)
		extra_balls.append(partner)

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
		_save_progress()
		if vibration_enabled and (OS.has_feature("android") or OS.has_feature("ios")):
			Input.vibrate_handheld(25)
		audio.play_coin()
		_update_hud()
		if score >= coins_total:
			ui.set_message("All pearls found! Reach the golden exit")

func _on_hazard_body(body: Node) -> void:
	if body.is_in_group("player"):
		_lose_life()

func _on_exit_body(body: Node) -> void:
	if not body.is_in_group("player") or level_locked:
		return
	exit_balls_entered[body.get_instance_id()] = true
	if exit_balls_entered.size() < exit_required:
		ui.set_message("Bring both pearls to the golden exit (%d/%d)" % [exit_balls_entered.size(), exit_required])
		return
	if score < coins_total:
		ui.set_message("Find all %d pearls first (%d/%d)" % [coins_total, score, coins_total])
		return
	level_locked = true
	best_score = maxi(best_score, total_run_score)
	var records := ConfigFile.new()
	records.set_value("records", "best_score", best_score)
	records.save("user://records.cfg")
	_save_progress(level + 1)
	audio.play_win()
	if vibration_enabled and (OS.has_feature("android") or OS.has_feature("ios")):
		Input.vibrate_handheld(90)
	ui.show_result("MAZE CLEARED!", "Level %d • Run score %d • Best %d" % [level, total_run_score, best_score], true)

func _lose_life() -> void:
	if level_locked:
		return
	level_locked = true
	exit_balls_entered.clear()
	lives -= 1
	audio.play_hit()
	if vibration_enabled and (OS.has_feature("android") or OS.has_feature("ios")):
		Input.vibrate_handheld(65)
	_update_hud()
	if lives <= 0:
		_save_progress()
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
	maze.pressure_button_activated.connect(_on_pressure_button_activated)
	maze.pop_ball_popped.connect(_on_pop_ball_popped)
	maze.level_mechanic_event.connect(_on_level_mechanic_event)
	maze.boss_defeated.connect(_on_boss_defeated)
	start_point = maze.start_position
	exit_required = 2 if level >= 8 else 1
	exit_balls_entered.clear()
	coins_total = _count_coins()
	score = 0
	_save_progress()
	ui.make_gate_buttons(maze.gate_bodies.size())
	_spawn_ball()
	level_locked = false
	ui.set_message("Room reset — try another route")
	_update_hud()

func _on_pressure_button_activated(index: int) -> void:
	if not is_instance_valid(maze):
		return
	total_run_score += 3
	for hazard in maze.get_children():
		if hazard is Area2D and hazard.is_in_group("hazard"):
			hazard.set_deferred("monitoring", false)
	get_tree().create_timer(4.0).timeout.connect(_restore_hazards.bind(maze))
	ui.set_message("Bonus plate %d: safe passage for 4 seconds! +3" % (index + 1))
	audio.play_win()
	if vibration_enabled and (OS.has_feature("android") or OS.has_feature("ios")):
		Input.vibrate_handheld(45)
	_save_progress()

func _restore_hazards(target_maze: Node) -> void:
	if not is_instance_valid(target_maze) or target_maze != maze:
		return
	for hazard in target_maze.get_children():
		if hazard is Area2D and hazard.is_in_group("hazard"):
			hazard.set_deferred("monitoring", true)

func _on_pop_ball_popped(red_ball: RigidBody2D) -> void:
	var points := int(red_ball.get("score_value")) if is_instance_valid(red_ball) else 2
	var orb_type := String(red_ball.get("orb_type")) if is_instance_valid(red_ball) else "normal"
	total_run_score += points
	if orb_type == "boost" and is_instance_valid(ball):
		ball.linear_velocity *= 1.35
	audio.play_coin()
	ui.set_message("Bonus orb popped! +%d points" % points)
	_save_progress()

func _on_level_mechanic_event(message: String, points: int) -> void:
	total_run_score += points
	ui.set_message(message)
	if points > 0:
		audio.play_coin()
		_save_progress()

func _on_boss_defeated() -> void:
	total_run_score += 20
	ui.set_message("Boss defeated! +20 bonus points")
	audio.play_win()
	_save_progress()

func _on_tutorial_finished() -> void:
	tutorial_completed = true
	_save_progress()
	ui.set_message("Practice room: collect the pearls and reach the golden exit")

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

func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"music":
			music_volume = float(value)
			audio.set_music_volume(music_volume)
		"sfx":
			sfx_volume = float(value)
			audio.set_sfx_volume(sfx_volume)
			audio.play_ui()
		"sensitivity":
			tilt.sensitivity = float(value)
			_saved_sensitivity = tilt.sensitivity
		"vibration":
			vibration_enabled = bool(value)
	_save_settings()
	ui.set_settings_defaults(music_volume, sfx_volume, tilt.sensitivity, vibration_enabled)

func _on_settings_pause_changed(paused: bool) -> void:
	get_tree().paused = paused
	if not paused:
		audio.play_ui()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_progress()
		_save_settings()
