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
var boss_required := false
var boss_is_defeated := false
var safe_passage_timer: Timer
var music_volume := 0.32
var sfx_volume := 0.75
var vibration_enabled := true
var level_seed := 0
var restore_level_state := false
var collected_coin_positions: Array[Vector2] = []
var saved_maze_snapshot: Array = []
var saved_ball_positions: Array[Vector2] = []
var saved_ball_velocities: Array[Vector2] = []
var saved_boss_defeated := false
var saved_sequence_next := 0
var camera: Camera2D
var camera_zoom := 1.0
var camera_pan_offset := Vector2.ZERO
var autosave_elapsed := 0.0
var touch_points: Dictionary = {}
var pinch_distance := 0.0
var mouse_pan_active := false

func _ready() -> void:
	randomize()
	viewport_size = get_viewport_rect().size
	camera = Camera2D.new()
	camera.name = "MazeCamera"
	camera.enabled = true
	camera.position = viewport_size * 0.5
	add_child(camera)
	safe_passage_timer = Timer.new()
	safe_passage_timer.one_shot = true
	safe_passage_timer.timeout.connect(_restore_current_safe_hazards)
	add_child(safe_passage_timer)
	_load_settings()
	_load_progress()
	camera.zoom = Vector2.ONE * camera_zoom
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
	ui.regenerate_requested.connect(_regenerate_level)
	ui.camera_zoom_requested.connect(_on_camera_zoom)
	ui.camera_center_requested.connect(_center_camera)
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
		push_warning("Не удалось сохранить настройки: %s" % error)

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) != OK:
		return
	level = maxi(0, int(cfg.get_value("progress", "level", 0)))
	total_run_score = maxi(0, int(cfg.get_value("progress", "total_score", 0)))
	tutorial_completed = bool(cfg.get_value("progress", "tutorial_completed", false))
	lives = clampi(int(cfg.get_value("state", "lives", 3)), 1, 3)
	level_seed = int(cfg.get_value("state", "seed", 0))
	restore_level_state = bool(cfg.get_value("state", "available", false)) and level_seed != 0
	if restore_level_state:
		score = maxi(0, int(cfg.get_value("state", "score", 0)))
		collected_coin_positions = cfg.get_value("state", "collected_coins", [])
		saved_maze_snapshot = cfg.get_value("state", "maze_snapshot", [])
		saved_ball_positions = cfg.get_value("state", "ball_positions", [])
		saved_ball_velocities = cfg.get_value("state", "ball_velocities", [])
		saved_boss_defeated = bool(cfg.get_value("state", "boss_defeated", false))
		saved_sequence_next = int(cfg.get_value("state", "sequence_next", 0))
		camera_zoom = clampf(float(cfg.get_value("state", "camera_zoom", 1.0)), 0.18, 2.8)
		camera_pan_offset = cfg.get_value("state", "camera_pan", Vector2.ZERO)
	if not tutorial_completed:
		level = 0

func _save_progress(saved_level: int = -1) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "level", maxi(0, saved_level if saved_level >= 0 else level))
	cfg.set_value("progress", "total_score", total_run_score)
	cfg.set_value("progress", "best_score", best_score)
	cfg.set_value("progress", "last_level_score", score)
	cfg.set_value("progress", "tutorial_completed", tutorial_completed)
	cfg.set_value("state", "lives", lives)
	var keep_level_state := saved_level < 0 and is_instance_valid(maze) and not level_locked
	cfg.set_value("state", "available", keep_level_state)
	if keep_level_state:
		cfg.set_value("state", "seed", level_seed)
		cfg.set_value("state", "score", score)
		cfg.set_value("state", "collected_coins", collected_coin_positions)
		cfg.set_value("state", "maze_snapshot", maze.get_level_snapshot())
		var positions: Array[Vector2] = []
		var velocities: Array[Vector2] = []
		for player_body in _get_player_bodies():
			if is_instance_valid(player_body):
				positions.append(player_body.global_position)
				velocities.append(player_body.linear_velocity)
		cfg.set_value("state", "ball_positions", positions)
		cfg.set_value("state", "ball_velocities", velocities)
		cfg.set_value("state", "boss_defeated", boss_is_defeated)
		cfg.set_value("state", "sequence_next", maze.sequence_next)
		cfg.set_value("state", "camera_zoom", camera_zoom)
		cfg.set_value("state", "camera_pan", camera_pan_offset)
	else:
		cfg.set_value("state", "available", false)
	var error := cfg.save(PROGRESS_PATH)
	if error != OK:
		push_warning("Не удалось сохранить прогресс: %s" % error)

func _start_run() -> void:
	level = 1 if tutorial_completed else 0
	lives = 3
	total_run_score = 0
	level_seed = randi()
	restore_level_state = false
	collected_coin_positions.clear()
	saved_maze_snapshot.clear()
	_start_level()

func _start_level() -> void:
	level_locked = false
	if not restore_level_state:
		score = 0
		level_seed = randi()
		collected_coin_positions.clear()
		saved_maze_snapshot.clear()
		camera_pan_offset = Vector2.ZERO
	_build_level()
	_save_progress()

func _build_level() -> void:
	var restoring_level := restore_level_state
	if is_instance_valid(maze):
		maze.queue_free()
	maze = MazeScript.new()
	add_child(maze)
	maze.hazard_created.connect(_connect_hazard)
	maze.exit_created.connect(_connect_exit)
	maze.coin_body_created.connect(_connect_coin)
	maze.generate(level, viewport_size, level_seed)
	maze.pressure_button_activated.connect(_on_pressure_button_activated)
	maze.pop_ball_popped.connect(_on_pop_ball_popped)
	maze.level_mechanic_event.connect(_on_level_mechanic_event)
	maze.boss_defeated.connect(_on_boss_defeated)
	start_point = maze.start_position
	coins_total = _count_coins()
	if restoring_level:
		maze.apply_level_snapshot(saved_maze_snapshot)
		maze.remove_collected_coins(collected_coin_positions)
		maze.sequence_next = saved_sequence_next
	exit_required = 2 if level >= 8 else 1
	exit_balls_entered.clear()
	boss_required = level >= 10
	boss_is_defeated = saved_boss_defeated if restoring_level else false
	if not restoring_level:
		var fit_x := viewport_size.x / maxf(1.0, maze.board_rect.size.x)
		var fit_y := (viewport_size.y - 220.0) / maxf(1.0, maze.board_rect.size.y)
		camera_zoom = clampf(minf(fit_x, fit_y), 0.18, 1.0)
		camera.zoom = Vector2.ONE * camera_zoom
	ui.make_gate_buttons(maze.gate_bodies.size())
	_spawn_ball()
	if restoring_level:
		_restore_player_bodies()
		restore_level_state = false
	if is_instance_valid(camera) and is_instance_valid(ball):
		camera.global_position = ball.global_position + camera_pan_offset
	ui.hide_result()
	ui.set_message(_level_intro_message())
	_update_hud()

func _level_intro_message() -> String:
	match level:
		0: return "ТРЕНИРОВКА • Наклоняйте телефон, собирайте жемчужины и найдите выход"
		1: return "ЛЁД • Шарик скользит дальше по инерции"
		2: return "ПОРТАЛЫ • Исследуйте боковые проходы"
		3: return "КОНВЕЙЕРЫ • Следите за движущимся полом"
		4: return "ПРУЖИНЫ • Рассчитывайте место приземления"
		5: return "ДВИЖУЩИЕСЯ СТЕНЫ • Выбирайте момент для прохода"
		6: return "МАГНИТЫ И ВРАЩАЮЩИЙСЯ МОСТ • Контролируйте инерцию"
		7: return "ЛАЗЕРЫ • Пересекайте их только в выключенном состоянии"
		8: return "ДВЕ ЖЕМЧУЖИНЫ • Доставьте обе к выходу и решите головоломку"
		9: return "СКРЫТЫЙ ЛАБИРИНТ • Стены видны рядом с шариком"
		10: return "БОСС • Трижды нажмите на движущееся ядро"
		_: return "Соберите все жемчужины и доберитесь до золотого выхода"

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
		collected_coin_positions.append(coin.position)
		score += 1
		total_run_score += 1
		coin.queue_free()
		_save_progress()
		if vibration_enabled and (OS.has_feature("android") or OS.has_feature("ios")):
			Input.vibrate_handheld(25)
		audio.play_coin()
		_update_hud()
		if score >= coins_total:
			ui.set_message("Все жемчужины собраны! Доберитесь до золотого выхода")

func _on_hazard_body(body: Node) -> void:
	if body.is_in_group("player"):
		_lose_life()

func _on_exit_body(body: Node) -> void:
	if not body.is_in_group("player") or level_locked:
		return
	if score < coins_total:
		ui.set_message("Сначала соберите все жемчужины: %d/%d" % [coins_total, score, coins_total])
		return
	if boss_required and not boss_is_defeated:
		ui.set_message("Перед выходом победите босса")
		return
	exit_balls_entered[body.get_instance_id()] = true
	if exit_balls_entered.size() < exit_required:
		ui.set_message("Доставьте оба шарика к золотому выходу: %d/%d" % [exit_balls_entered.size(), exit_required])
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
	ui.show_result("ЛАБИРИНТ ПРОЙДЕН!", "Уровень %d • Очки за игру: %d • Рекорд: %d" % [level, total_run_score, best_score], true)

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
		ui.show_result("ЖИЗНИ ЗАКОНЧИЛИСЬ", "Очки за игру: %d" % total_run_score, false)
	else:
		_respawn_all.call_deferred()

func _respawn_all() -> void:
	if is_instance_valid(safe_passage_timer):
		safe_passage_timer.stop()
	if is_instance_valid(ball):
		ball.queue_free()
	if is_instance_valid(maze):
		maze.queue_free()
	maze = MazeScript.new()
	add_child(maze)
	maze.hazard_created.connect(_connect_hazard)
	maze.exit_created.connect(_connect_exit)
	maze.coin_body_created.connect(_connect_coin)
	maze.generate(level, viewport_size, level_seed)
	maze.pressure_button_activated.connect(_on_pressure_button_activated)
	maze.pop_ball_popped.connect(_on_pop_ball_popped)
	maze.level_mechanic_event.connect(_on_level_mechanic_event)
	maze.boss_defeated.connect(_on_boss_defeated)
	start_point = maze.start_position
	exit_required = 2 if level >= 8 else 1
	exit_balls_entered.clear()
	boss_required = level >= 10
	boss_is_defeated = false
	coins_total = _count_coins()
	score = 0
	collected_coin_positions.clear()
	saved_maze_snapshot.clear()
	_save_progress()
	ui.make_gate_buttons(maze.gate_bodies.size())
	_spawn_ball()
	level_locked = false
	ui.set_message("Комната перезапущена — попробуйте другой путь")
	_update_hud()

func _on_pressure_button_activated(index: int) -> void:
	if not is_instance_valid(maze):
		return
	total_run_score += 3
	for hazard in maze.get_children():
		if hazard is Area2D and hazard.is_in_group("hazard"):
			if hazard.has_method("set_safe_disabled"):
				hazard.set_safe_disabled(true)
			else:
				hazard.set_deferred("monitoring", false)
	safe_passage_timer.start(4.0)
	ui.set_message("Бонусная плита %d: безопасный проход на 4 секунды! +3" % (index + 1))
	audio.play_win()
	if vibration_enabled and (OS.has_feature("android") or OS.has_feature("ios")):
		Input.vibrate_handheld(45)
	_save_progress()

func _restore_current_safe_hazards() -> void:
	_restore_hazards(maze)

func _restore_hazards(target_maze: Node) -> void:
	if not is_instance_valid(target_maze) or target_maze != maze:
		return
	for hazard in target_maze.get_children():
		if hazard is Area2D and hazard.is_in_group("hazard"):
			if hazard.has_method("set_safe_disabled"):
				hazard.set_safe_disabled(false)
			else:
				hazard.set_deferred("monitoring", true)

func _on_pop_ball_popped(red_ball: RigidBody2D) -> void:
	var points := int(red_ball.get("score_value")) if is_instance_valid(red_ball) else 2
	var orb_type := String(red_ball.get("orb_type")) if is_instance_valid(red_ball) else "normal"
	total_run_score += points
	if orb_type == "boost" and is_instance_valid(ball):
		ball.linear_velocity *= 1.35
	audio.play_coin()
	ui.set_message("Бонусный шарик лопнул! +%d очков" % points)
	_save_progress()

func _on_level_mechanic_event(message: String, points: int) -> void:
	total_run_score += points
	ui.set_message(message)
	if points > 0:
		audio.play_coin()
		_save_progress()

func _on_boss_defeated() -> void:
	boss_is_defeated = true
	total_run_score += 20
	ui.set_message("Босс побеждён! Бонус: +20 очков")
	audio.play_win()
	_save_progress()

func _on_tutorial_finished() -> void:
	tutorial_completed = true
	_save_progress()
	ui.set_message("Тренировочная комната: соберите жемчужины и доберитесь до золотого выхода")

func _on_gate_pressed(index: int, pressed: bool) -> void:
	if is_instance_valid(maze):
		maze.set_gate_button_state(index, pressed)

func _update_hud() -> void:
	ui.set_hud(level, lives, score, coins_total)

func _next_level() -> void:
	level += 1
	restore_level_state = false
	level_seed = randi()
	collected_coin_positions.clear()
	saved_maze_snapshot.clear()
	_start_level()

func _regenerate_level() -> void:
	if level_locked:
		return
	level_seed = randi()
	score = 0
	collected_coin_positions.clear()
	saved_maze_snapshot.clear()
	restore_level_state = false
	camera_pan_offset = Vector2.ZERO
	_start_level()
	ui.set_message("Создан новый вариант уровня")

func _restart_run() -> void:
	_start_run()

func _calibrate_tilt() -> void:
	tilt.calibrate()
	ui.set_message("Наклон откалиброван — ненадолго оставьте телефон неподвижным")

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

func _get_player_bodies() -> Array:
	var bodies: Array = []
	if is_instance_valid(ball):
		bodies.append(ball)
	for extra in extra_balls:
		if is_instance_valid(extra):
			bodies.append(extra)
	return bodies

func _restore_player_bodies() -> void:
	var bodies := _get_player_bodies()
	for i in range(mini(bodies.size(), saved_ball_positions.size())):
		bodies[i].global_position = saved_ball_positions[i]
		if i < saved_ball_velocities.size():
			bodies[i].linear_velocity = saved_ball_velocities[i]
	saved_ball_positions.clear()
	saved_ball_velocities.clear()

func _on_camera_zoom(factor: float) -> void:
	camera_zoom = clampf(camera_zoom * factor, 0.18, 2.8)
	if is_instance_valid(camera):
		camera.zoom = Vector2.ONE * camera_zoom
	_save_progress()

func _center_camera() -> void:
	camera_pan_offset = Vector2.ZERO
	if is_instance_valid(ball) and is_instance_valid(camera):
		camera.global_position = ball.global_position
	_save_progress()

func _process(delta: float) -> void:
	if is_instance_valid(camera) and is_instance_valid(ball):
		var target := ball.global_position + camera_pan_offset
		camera.global_position = camera.global_position.lerp(target, minf(1.0, delta * 8.0))
	autosave_elapsed += delta
	if autosave_elapsed >= 2.0:
		autosave_elapsed = 0.0
		_save_progress()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			touch_points[touch.index] = touch.position
			if touch_points.size() == 2:
				var values: Array = touch_points.values()
				pinch_distance = values[0].distance_to(values[1])
		else:
			touch_points.erase(touch.index)
			if touch_points.size() < 2:
				pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if touch_points.has(drag.index):
			touch_points[drag.index] = drag.position
		if touch_points.size() >= 2:
			var values: Array = touch_points.values()
			var next_distance: float = values[0].distance_to(values[1])
			if pinch_distance > 1.0:
				camera_zoom = clampf(camera_zoom * next_distance / pinch_distance, 0.18, 2.8)
				camera.zoom = Vector2.ONE * camera_zoom
			pinch_distance = next_distance
		elif touch_points.size() == 1:
			camera_pan_offset -= drag.relative / camera_zoom
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			mouse_pan_active = mouse_button.pressed
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_on_camera_zoom(1.15)
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_on_camera_zoom(0.87)
	elif event is InputEventMouseMotion and mouse_pan_active:
		camera_pan_offset -= (event as InputEventMouseMotion).relative / camera_zoom

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_progress()
		_save_settings()
