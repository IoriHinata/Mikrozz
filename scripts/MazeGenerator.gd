extends Node2D
class_name MazeGenerator

signal coin_body_created(coin: RigidBody2D)
signal hazard_created(hazard: Area2D)
signal exit_created(exit_area: Area2D)
signal pressure_button_created(button: Area2D)
signal pop_ball_created(ball: RigidBody2D)
signal pop_ball_popped(ball: RigidBody2D)
signal pressure_button_activated(index: int)

var pop_timer: Timer
var active_level := 1
var generation_seed := 0
var theme_id := -1
var theme_stage := 1
var endless_mode := false
var cell_size_x := 42.0
var cell_size_y := 42.0
var pop_spawn_cells: Array[Vector2i] = []
var pop_spawner_position := Vector2.ZERO

const CoinScript = preload("res://scripts/Coin.gd")
const PALETTES := [
	{"floor": Color("#f1f7ef"), "wall": Color("#719b87"), "accent": Color("#a9d8c0")},
	{"floor": Color("#fff4ed"), "wall": Color("#b98572"), "accent": Color("#e9b9a4")},
	{"floor": Color("#f4f0fb"), "wall": Color("#9182b8"), "accent": Color("#c5b8e5")},
	{"floor": Color("#fff9e5"), "wall": Color("#a99655"), "accent": Color("#e7d48c")},
	{"floor": Color("#edf6fc"), "wall": Color("#7296b4"), "accent": Color("#b2d4e9")}
]
var cols := 7
var rows := 9
var cell_size := 42.0
var origin := Vector2.ZERO
var palette: Dictionary
var cells: Array = []
var solution: Array[Vector2i] = []
var gate_bodies: Array[StaticBody2D] = []
var gate_button_states: Array[bool] = []
var start_position := Vector2.ZERO
var finish_position := Vector2.ZERO
var board_rect := Rect2()
var wall_count := 0
var shape_id := 0
var start_cell := Vector2i.ZERO
var target_cell := Vector2i.ZERO
var reveal_position := Vector2(-10000.0, -10000.0)
var sequence_next := 0
var special_mechanic_count := 0

signal level_mechanic_event(message: String, points: int)
signal boss_defeated

func generate(level_number: int, viewport_size: Vector2, seed_value: int = 0) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	gate_bodies.clear()
	wall_count = 0
	active_level = level_number
	generation_seed = seed_value if seed_value != 0 else randi()
	seed(generation_seed)
	endless_mode = level_number >= 11
	var growth := maxi(0, level_number - 10)
	cols = 9 if level_number < 5 else 11
	rows = 11 if level_number < 5 else 13
	if endless_mode:
		cols = mini(128, 9 + int(float(growth) * 0.46))
		rows = mini(128, 11 + int(float(growth) * 0.46))
	cell_size = 42.0
	var aspect_values: Array[float] = [1.0, 1.25, 0.8, 1.5, 0.667]
	var aspect := aspect_values[posmod(maxi(0, level_number), aspect_values.size())]
	cell_size_x = cell_size * aspect
	cell_size_y = cell_size / aspect
	var board_size := Vector2(cols * cell_size_x, rows * cell_size_y)
	origin = Vector2(cell_size_x * 2.0, cell_size_y * 2.0)
	board_rect = Rect2(origin, board_size)
	palette = PALETTES[posmod(maxi(0, level_number), PALETTES.size())]
	shape_id = 0 if level_number <= 0 else posmod(level_number - 1, 4)
	theme_id = posmod(int((level_number - 11) / 4), 13) if endless_mode else -1
	theme_stage = posmod(level_number - 11, 4) + 1 if endless_mode else 1
	_build_cells()
	_add_maze_loops()
	_build_solution()
	_build_geometry(level_number)
	gate_button_states.clear()
	for _i in range(gate_bodies.size()):
		gate_button_states.append(false)
	_build_objects(level_number)
	queue_redraw()

func _process(_delta: float) -> void:
	if active_level >= 9:
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			var player := players[0] as Node2D
			if is_instance_valid(player):
				reveal_position = player.global_position
				queue_redraw()

func _build_cells() -> void:
	cells.clear()
	var center := Vector2((cols - 1) * 0.5, (rows - 1) * 0.5)
	var rx := maxf(1.0, cols * 0.5)
	var ry := maxf(1.0, rows * 0.5)
	for y in range(rows):
		var row_data: Array = []
		for x in range(cols):
			var nx := (float(x) - center.x) / rx
			var ny := (float(y) - center.y) / ry
			var inside := true
			match shape_id:
				1: # rounded circular maze
					inside = nx * nx + ny * ny <= 0.91
				2: # diamond maze
					inside = absf(nx) + absf(ny) <= 1.02
				3: # hexagonal maze
					inside = absf(nx) <= 1.0 and absf(ny) <= 0.92 and absf(nx) * 0.5 + absf(ny) <= 1.05
			row_data.append({"walls": [true, true, true, true], "visited": false, "inside": inside})
		cells.append(row_data)
	# Choose a valid starting cell close to the upper edge.
	var best_start := 1.0e9
	for y in range(rows):
		for x in range(cols):
			if not cells[y][x]["inside"]:
				continue
			var cost := float(y * 100 + absf(float(x) - center.x))
			if cost < best_start:
				best_start = cost
				start_cell = Vector2i(x, y)
	cells[start_cell.y][start_cell.x]["visited"] = true
	var stack: Array[Vector2i] = [start_cell]
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var opposites := [2, 3, 0, 1]
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var choices: Array[int] = []
		for d in range(4):
			var next_cell: Vector2i = current + dirs[d]
			if next_cell.x >= 0 and next_cell.x < cols and next_cell.y >= 0 and next_cell.y < rows and cells[next_cell.y][next_cell.x]["inside"] and not cells[next_cell.y][next_cell.x]["visited"]:
				choices.append(d)
		if choices.is_empty():
			stack.pop_back()
		else:
			var direction: int = choices.pick_random()
			var next_cell: Vector2i = current + dirs[direction]
			cells[current.y][current.x]["walls"][direction] = false
			cells[next_cell.y][next_cell.x]["walls"][opposites[direction]] = false
			cells[next_cell.y][next_cell.x]["visited"] = true
			stack.append(next_cell)

func _add_maze_loops() -> void:
	var candidates: Array[Vector2i] = []
	for y in range(rows):
		for x in range(cols):
			if not cells[y][x]["inside"]:
				continue
			var cell := Vector2i(x, y)
			if x + 1 < cols and cells[y][x + 1]["inside"] and cells[y][x]["walls"][1]:
				candidates.append(cell)
			if y + 1 < rows and cells[y + 1][x]["inside"] and cells[y][x]["walls"][2]:
				candidates.append(cell)
	candidates.shuffle()
	var loop_budget := mini(candidates.size(), maxi(2, int(float(candidates.size()) * 0.08)))
	var opened := 0
	for cell in candidates:
		if opened >= loop_budget:
			break
		for direction in [1, 2]:
			var offset: Vector2i = Vector2i.RIGHT if direction == 1 else Vector2i.DOWN
			var neighbor: Vector2i = cell + offset
			if neighbor.x < cols and neighbor.y < rows and cells[neighbor.y][neighbor.x]["inside"] and cells[cell.y][cell.x]["walls"][direction]:
				cells[cell.y][cell.x]["walls"][direction] = false
				cells[neighbor.y][neighbor.x]["walls"][(direction + 2) % 4] = false
				opened += 1
				break

func _build_solution() -> void:
	solution.clear()
	var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var queue: Array[Vector2i] = [start_cell]
	var queue_index := 0
	var previous: Dictionary = {start_cell: Vector2i(-1, -1)}
	var distance: Dictionary = {start_cell: 0}
	var farthest := start_cell
	while queue_index < queue.size():
		var current: Vector2i = queue[queue_index]
		queue_index += 1
		if int(distance[current]) > int(distance[farthest]):
			farthest = current
		for d in range(4):
			if not cells[current.y][current.x]["walls"][d]:
				var next_cell: Vector2i = current + dirs[d]
				if not previous.has(next_cell):
					previous[next_cell] = current
					distance[next_cell] = int(distance[current]) + 1
					queue.append(next_cell)
	target_cell = farthest
	var stack: Array[Vector2i] = [start_cell]
	var visited: Dictionary = {start_cell: true}
	solution.append(start_cell)
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var choices: Array[Vector2i] = []
		for d in range(4):
			var next_cell: Vector2i = current + dirs[d]
			if next_cell.x >= 0 and next_cell.x < cols and next_cell.y >= 0 and next_cell.y < rows and cells[next_cell.y][next_cell.x]["inside"] and not visited.has(next_cell) and not cells[current.y][current.x]["walls"][d]:
				choices.append(next_cell)
		if choices.is_empty():
			stack.pop_back()
			if not stack.is_empty():
				solution.append(stack.back())
		else:
			var next_cell: Vector2i = choices.pick_random()
			visited[next_cell] = true
			stack.append(next_cell)
			solution.append(next_cell)
	var cursor := target_cell
	var return_path: Array[Vector2i] = []
	while cursor != start_cell:
		return_path.push_front(cursor)
		cursor = previous.get(cursor, start_cell)
	for path_cell in return_path:
		solution.append(path_cell)
	start_position = _cell_center(start_cell)
	finish_position = _cell_center(target_cell)

func _safe_neighbor_count(cell: Vector2i) -> int:
	var count := 0
	var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for d in range(4):
		var neighbor: Vector2i = cell + dirs[d]
		if neighbor.x >= 0 and neighbor.x < cols and neighbor.y >= 0 and neighbor.y < rows and cells[neighbor.y][neighbor.x]["inside"] and not cells[cell.y][cell.x]["walls"][d]:
			count += 1
	return count

func _ensure_three_open_sides(cell: Vector2i) -> void:
	var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for d in range(4):
		if _safe_neighbor_count(cell) >= 3:
			return
		var neighbor: Vector2i = cell + dirs[d]
		if neighbor.x < 0 or neighbor.x >= cols or neighbor.y < 0 or neighbor.y >= rows:
			continue
		if cells[neighbor.y][neighbor.x]["inside"] and cells[cell.y][cell.x]["walls"][d]:
			cells[cell.y][cell.x]["walls"][d] = false
			cells[neighbor.y][neighbor.x]["walls"][(d + 2) % 4] = false

func _build_geometry(level_number: int) -> void:
	var gate_edges: Dictionary = {}
	var gate_limit := 1 if level_number == 0 else mini(3, 1 + int(maxi(0, level_number - 1) / 2))
	var fractions: Array[float] = [0.24, 0.52, 0.78]
	var chosen_indices: Array[int] = []
	for i in range(gate_limit):
		var path_index := clampi(int(float(solution.size() - 1) * fractions[i]), 2, solution.size() - 2)
		if path_index in chosen_indices:
			continue
		chosen_indices.append(path_index)
		var a: Vector2i = solution[path_index - 1]
		var b: Vector2i = solution[path_index]
		var edge: Dictionary = {"a": a, "b": b, "position": (_cell_center(a) + _cell_center(b)) * 0.5}
		gate_edges[_edge_key(a, b)] = edge
	var dirs := [Vector2i(0, -1), Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for y in range(rows):
		for x in range(cols):
			if not cells[y][x]["inside"]:
				continue
			var cell := Vector2i(x, y)
			for d in range(4):
				var neighbor: Vector2i = cell + dirs[d]
				var outside: bool = neighbor.x < 0 or neighbor.x >= cols or neighbor.y < 0 or neighbor.y >= rows or not cells[neighbor.y][neighbor.x]["inside"]
				if outside:
					_add_wall(_cell_edge_center(cell, d), _cell_edge_size(d))
				elif d == 1 or d == 2:
					var key := _edge_key(cell, neighbor)
					if gate_edges.has(key):
						_add_gate(gate_edges[key].position, d == 1)
					elif cells[y][x]["walls"][d]:
						_add_wall(_wall_center(cell, d), _wall_size(d))

func _build_objects(level_number: int) -> void:
	var coin_count := clampi(3 + int(level_number / 2), 3, 10)
	for i in range(coin_count):
		var path_index := clampi(int((float(i + 1) / float(coin_count + 1)) * (solution.size() - 1)), 1, solution.size() - 2)
		var coin := CoinScript.new()
		coin.position = _cell_center(solution[path_index])
		add_child(coin)
		coin_body_created.emit(coin)
	var hazard_count := mini(12, maxi(0, int((level_number - 1) * 1.15))) if not endless_mode else 0
	var candidates: Array[Vector2i] = []
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			if cells[y][x]["inside"] and cell not in solution and cell != start_cell and cell != target_cell:
				candidates.append(cell)
	candidates.shuffle()
	for i in range(mini(hazard_count, candidates.size())):
		_ensure_three_open_sides(candidates[i])
		var hazard := _make_hazard(_cell_center(candidates[i]), cell_size * 0.20, true)
		add_child(hazard)
		hazard_created.emit(hazard)

	# Pressure plates are optional puzzle controls. The ball activates them by rolling over.
	if level_number >= 2 and not endless_mode:
		var plate_cells: Array[Vector2i] = []
		for y in range(rows):
			for x in range(cols):
				var candidate := Vector2i(x, y)
				if cells[y][x]["inside"] and candidate not in solution and candidate != start_cell and candidate != target_cell and not _cell_is_occupied(candidate):
					plate_cells.append(candidate)
		plate_cells.shuffle()
		var plate_count := mini(2, 1 + int(level_number / 6))
		for i in range(mini(plate_count, plate_cells.size())):
			var plate := PressurePlate.new()
			plate.position = _cell_center(plate_cells[i])
			plate.plate_index = i
			add_child(plate)
			plate.activated.connect(func(index: int): pressure_button_activated.emit(index))
			pressure_button_created.emit(plate)
	# A visible spawner periodically releases red bonus orbs. Tap them to pop them.
	if level_number >= 2 and not endless_mode:
		pop_spawn_cells.clear()
		for y in range(rows):
			for x in range(cols):
				var candidate := Vector2i(x, y)
				if cells[y][x]["inside"] and candidate not in solution and candidate != start_cell and candidate != target_cell and not _cell_is_occupied(candidate):
					pop_spawn_cells.append(candidate)
		pop_spawn_cells.shuffle()
		if not pop_spawn_cells.is_empty():
			var spawner := PopSpawnerVisual.new()
			spawner.add_to_group("special_occupied")
			pop_spawner_position = _cell_center(pop_spawn_cells[0])
			spawner.position = pop_spawner_position
			add_child(spawner)
			pop_timer = Timer.new()
			pop_timer.wait_time = maxf(2.8, 6.0 - float(level_number) * 0.12)
			pop_timer.autostart = true
			pop_timer.timeout.connect(_spawn_pop_ball)
			add_child(pop_timer)
	_build_special_mechanics(level_number)
	var exit_area := Area2D.new()
	exit_area.name = "Exit"
	exit_area.add_to_group("exit")
	exit_area.position = finish_position
	var exit_shape := CircleShape2D.new()
	exit_shape.radius = cell_size * 0.30
	var exit_collision := CollisionShape2D.new()
	exit_collision.shape = exit_shape
	exit_area.add_child(exit_collision)
	add_child(exit_area)
	exit_created.emit(exit_area)

func _spawn_pop_ball() -> void:
	if pop_spawn_cells.is_empty() or not is_inside_tree():
		return
	var red_ball := RedPopBall.new()
	red_ball.position = pop_spawner_position
	red_ball.linear_velocity = Vector2(randf_range(-45.0, 45.0), randf_range(-45.0, 45.0))
	add_child(red_ball)
	red_ball.popped.connect(func(): pop_ball_popped.emit(red_ball))
	pop_ball_created.emit(red_ball)

func _make_hazard(at: Vector2, radius: float, spikes: bool) -> Area2D:
	var area := Area2D.new()
	area.position = at
	area.add_to_group("hazard")
	var shape := CircleShape2D.new()
	shape.radius = radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child(collision)
	var visual := HazardVisual.new()
	visual.radius = radius
	visual.spikes = spikes
	area.add_child(visual)
	return area

func _add_wall(at: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = at
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	wall_count += 1

func _add_gate(at: Vector2, vertical: bool) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.add_to_group("gates")
	var size := Vector2(11.0, cell_size_y * 0.88) if vertical else Vector2(cell_size_x * 0.88, 11.0)
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	var visual := GateVisual.new()
	visual.size = size
	visual.color = palette.accent
	body.add_child(visual)
	add_child(body)
	gate_bodies.append(body)

func set_gate_button_state(index: int, pressed: bool) -> void:
	if index < 0 or index >= gate_button_states.size():
		return
	gate_button_states[index] = pressed
	for gate_index in range(gate_bodies.size()):
		var opened := gate_button_states[gate_index]
		if active_level >= 5 and gate_index == 2:
			opened = gate_button_states.size() >= 3 and gate_button_states[0] and gate_button_states[1] and gate_button_states[2]
		set_gate_open(gate_index, opened)

func set_gate_open(index: int, opened: bool) -> void:
	if index < 0 or index >= gate_bodies.size():
		return
	for child in gate_bodies[index].get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", opened)
	for child in gate_bodies[index].get_children():
		if child is GateVisual:
			child.visible = not opened

func _cell_center(cell: Vector2i) -> Vector2:
	return origin + Vector2((cell.x + 0.5) * cell_size_x, (cell.y + 0.5) * cell_size_y)

func _wall_center(cell: Vector2i, d: int) -> Vector2:
	return _cell_edge_center(cell, d)

func _wall_size(d: int) -> Vector2:
	return Vector2(12, cell_size_y + 5) if d == 1 else Vector2(cell_size_x + 5, 12)

func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var first := a if (a.y < b.y or (a.y == b.y and a.x < b.x)) else b
	var second := b if first == a else a
	return "%d,%d|%d,%d" % [first.x, first.y, second.x, second.y]

func _draw() -> void:
	# Seamless floor fill without visible tile borders or grid lines.
	for y in range(rows):
		for x in range(cols):
			if not cells[y][x]["inside"]:
				continue
			var cell := Vector2i(x, y)
			var cell_position := _cell_center(cell)
			if active_level >= 9 and cell_position.distance_to(reveal_position) > cell_size * 2.35:
				continue
			var floor_rect := Rect2(origin + Vector2(x * cell_size_x, y * cell_size_y), Vector2(cell_size_x, cell_size_y))
			draw_rect(floor_rect, palette.floor, true)
			for d in range(4):
				var neighbor: Vector2i = cell + [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][d]
				var outside: bool = neighbor.x < 0 or neighbor.x >= cols or neighbor.y < 0 or neighbor.y >= rows or not cells[neighbor.y][neighbor.x]["inside"]
				if outside or ((d == 1 or d == 2) and cells[y][x]["walls"][d]):
					var edge_center := _cell_edge_center(cell, d)
					var horizontal := d == 0 or d == 2
					var half := cell_size_x * 0.5 if horizontal else cell_size_y * 0.5
					var from := edge_center + (Vector2(-half, 0) if horizontal else Vector2(0, -half))
					var to := edge_center + (Vector2(half, 0) if horizontal else Vector2(0, half))
					draw_line(from, to, palette.wall.darkened(0.12), 9.0, true)
					draw_line(from, to, palette.wall.lightened(0.10), 5.0, true)
	draw_circle(start_position, cell_size * 0.19, Color("#b5ddc5"))
	draw_circle(start_position, cell_size * 0.11, Color("#f8fff8"))
	draw_circle(finish_position, cell_size * 0.28, Color("#f2d58a"))
	draw_circle(finish_position, cell_size * 0.16, Color("#fff9e7"))

func _cell_edge_center(cell: Vector2i, direction: int) -> Vector2:
	var center := _cell_center(cell)
	match direction:
		0: return center + Vector2(0, -cell_size_y * 0.5)
		1: return center + Vector2(cell_size_x * 0.5, 0)
		2: return center + Vector2(0, cell_size_y * 0.5)
		_: return center + Vector2(-cell_size_x * 0.5, 0)

func _cell_edge_size(direction: int) -> Vector2:
	return Vector2(cell_size_x + 5, 12) if direction == 0 or direction == 2 else Vector2(12, cell_size_y + 5)

func _find_free_path_index(fraction: float) -> int:
	if solution.size() < 5:
		return -1
	var desired := clampi(int(float(solution.size() - 1) * fraction), 2, solution.size() - 3)
	for radius in range(solution.size()):
		var candidates: Array[int] = [desired]
		if radius > 0:
			candidates.append(desired - radius)
			candidates.append(desired + radius)
		for index in candidates:
			if index < 2 or index > solution.size() - 3:
				continue
			if not _cell_is_occupied(solution[index]):
				return index
	return -1

func _cell_is_occupied(cell: Vector2i) -> bool:
	var center := _cell_center(cell)
	for child in get_children():
		if child is Node2D and (child.is_in_group("hazard") or child.is_in_group("puzzle_plates") or child.is_in_group("special_occupied") or child.is_in_group("coins")):
			if (child as Node2D).position.distance_to(center) < cell_size * 0.34:
				return true
	return false

func _build_special_mechanics(level_number: int) -> void:
	sequence_next = 0
	if endless_mode:
		_build_endless_theme_mechanics(level_number)
		return
	special_mechanic_count = 0
	if level_number >= 1 and solution.size() > 5:
		var surface_index := _find_free_path_index(0.42)
		if surface_index >= 0:
			var surface := SurfaceZone.new()
			surface.mode = ["ice", "sand", "sticky", "ice", "sand"][posmod(level_number - 1, 5)]
			surface.position = _cell_center(solution[surface_index])
			surface.size_radius = cell_size * 0.34
			add_child(surface)
			special_mechanic_count += 1
	if level_number >= 2:
		var branches: Array[Vector2i] = []
		for y in range(rows):
			for x in range(cols):
				var cell := Vector2i(x, y)
				if cells[y][x]["inside"] and cell not in solution and cell != start_cell and cell != target_cell and not _cell_is_occupied(cell):
					branches.append(cell)
		if branches.size() >= 2:
			branches.shuffle()
			var portal_a := PortalPad.new()
			var portal_b := PortalPad.new()
			portal_a.position = _cell_center(branches[0])
			portal_b.position = _cell_center(branches[1])
			portal_a.destination = portal_b.position
			portal_b.destination = portal_a.position
			add_child(portal_a)
			add_child(portal_b)
			special_mechanic_count += 1
	if level_number >= 3 and solution.size() > 6:
		var conveyor_index := _find_free_path_index(0.32)
		if conveyor_index >= 0:
			var conveyor := ConveyorZone.new()
			conveyor.position = _cell_center(solution[conveyor_index])
			conveyor.direction = Vector2.RIGHT if level_number % 2 == 1 else Vector2.LEFT
			add_child(conveyor)
			special_mechanic_count += 1
	if level_number >= 4 and solution.size() > 7:
		var spring_index := _find_free_path_index(0.58)
		if spring_index >= 0:
			var spring := SpringPad.new()
			spring.position = _cell_center(solution[spring_index])
			spring.kick_direction = Vector2.UP if level_number % 2 == 0 else Vector2.RIGHT
			add_child(spring)
			special_mechanic_count += 1
	if level_number >= 5 and solution.size() > 8:
		var barrier_index := _find_free_path_index(0.72)
		if barrier_index >= 0:
			var barrier := MovingBarrier.new()
			barrier.position = _cell_center(solution[barrier_index])
			barrier.travel = cell_size * 0.18
			barrier.speed = 1.25 + float(level_number) * 0.04
			barrier.barrier_size = Vector2(cell_size * 0.25, 8.0)
			add_child(barrier)
			special_mechanic_count += 1
	if level_number >= 6:
		var magnet_index := _find_free_path_index(0.50)
		if magnet_index >= 0:
			var magnet := MagnetField.new()
			magnet.position = _cell_center(solution[magnet_index])
			magnet.radius = cell_size * 1.45
			magnet.strength = 110.0
			add_child(magnet)
			special_mechanic_count += 1
	if level_number >= 6 and solution.size() > 10:
		var bridge_index := _find_free_path_index(0.84)
		if bridge_index >= 0:
			var bridge := RotatingBridge.new()
			bridge.position = _cell_center(solution[bridge_index])
			bridge.bridge_size = Vector2(cell_size * 0.66, 7.0)
			bridge.rotation_speed = 0.9
			add_child(bridge)
			special_mechanic_count += 1
	if level_number >= 7:
		var laser_cells: Array[Vector2i] = []
		for y in range(rows):
			for x in range(cols):
				var cell := Vector2i(x, y)
				if cells[y][x]["inside"] and cell not in solution and cell != start_cell and cell != target_cell and not _cell_is_occupied(cell):
					laser_cells.append(cell)
		if not laser_cells.is_empty():
			laser_cells.shuffle()
			var laser := LaserHazard.new()
			laser.position = _cell_center(laser_cells[0])
			add_child(laser)
			hazard_created.emit(laser)
			special_mechanic_count += 1
	if level_number >= 8 and solution.size() > 8:
		var sequence_created := 0
		for i in range(3):
			var plate_index := _find_free_path_index(float(i + 1) / 4.0)
			if plate_index < 0:
				continue
			var plate := SequencePlate.new()
			plate.plate_index = sequence_created
			plate.position = _cell_center(solution[plate_index])
			plate.sequence_owner = self
			add_child(plate)
			sequence_created += 1
		if sequence_created == 3:
			special_mechanic_count += 1
	if level_number >= 10:
		var boss_index := _find_free_path_index(0.68)
		if boss_index < 0:
			boss_index = clampi(int(solution.size() * 0.68), 2, solution.size() - 3)
		var boss := BossOrb.new()
		boss.add_to_group("special_occupied")
		boss.position = _cell_center(solution[boss_index])
		add_child(boss)
		boss.defeated.connect(func(): boss_defeated.emit())
		special_mechanic_count += 1

func _build_endless_theme_mechanics(level_number: int) -> void:
	var candidates: Array[Vector2i] = []
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			if cells[y][x]["inside"] and cell != start_cell and cell != target_cell and not _cell_is_occupied(cell):
				candidates.append(cell)
	candidates.shuffle()
	var route_indices: Array[int] = []
	for i in range(2, solution.size() - 2):
		var route_cell: Vector2i = solution[i]
		if route_cell != start_cell and route_cell != target_cell and not _cell_is_occupied(route_cell) and (route_indices.is_empty() or route_cell != solution[route_indices.back()]):
			route_indices.append(i)
	var count := 1 + theme_stage
	match theme_id:
		0:
			var placed := 0
			for cell in candidates:
				_ensure_three_open_sides(cell)
				if _safe_neighbor_count(cell) >= 3:
					var hazard := _make_hazard(_cell_center(cell), cell_size * 0.20, true)
					add_child(hazard)
					hazard_created.emit(hazard)
					placed += 1
					special_mechanic_count += 1
					if placed >= count:
						break
		1, 2, 3:
			var mode := "ice" if theme_id == 1 else ("sand" if theme_id == 2 else "sticky")
			for i in range(mini(count, route_indices.size())):
				var surface := SurfaceZone.new()
				surface.mode = mode
				surface.position = _cell_center(solution[route_indices[i]])
				surface.size_radius = cell_size * 0.34
				add_child(surface)
				special_mechanic_count += 1
		4:
			for pair_index in range(mini(theme_stage, int(candidates.size() / 2))):
				var portal_a := PortalPad.new()
				var portal_b := PortalPad.new()
				portal_a.position = _cell_center(candidates[pair_index * 2])
				portal_b.position = _cell_center(candidates[pair_index * 2 + 1])
				portal_a.destination = portal_b.position
				portal_b.destination = portal_a.position
				add_child(portal_a)
				add_child(portal_b)
				special_mechanic_count += 1
		5:
			for i in range(mini(count, route_indices.size())):
				var conveyor := ConveyorZone.new()
				conveyor.position = _cell_center(solution[route_indices[i]])
				conveyor.direction = Vector2.RIGHT if (i + theme_stage) % 2 == 0 else Vector2.LEFT
				add_child(conveyor)
				special_mechanic_count += 1
		6:
			for i in range(mini(count, route_indices.size())):
				var spring := SpringPad.new()
				spring.position = _cell_center(solution[route_indices[i]])
				spring.kick_direction = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][posmod(i + theme_stage, 4)]
				add_child(spring)
				special_mechanic_count += 1
		7:
			for i in range(mini(count, route_indices.size())):
				var barrier := MovingBarrier.new()
				barrier.position = _cell_center(solution[route_indices[i]])
				barrier.travel = cell_size * 0.18
				barrier.speed = 1.0 + float(theme_stage) * 0.22
				barrier.barrier_size = Vector2(cell_size * 0.25, 8.0)
				add_child(barrier)
				special_mechanic_count += 1
		8:
			for i in range(mini(count, route_indices.size())):
				var magnet := MagnetField.new()
				magnet.position = _cell_center(solution[route_indices[i]])
				magnet.radius = cell_size * (1.0 + float(theme_stage) * 0.12)
				magnet.strength = 75.0 + float(theme_stage) * 18.0
				add_child(magnet)
				special_mechanic_count += 1
		9:
			for i in range(mini(count, route_indices.size())):
				var bridge := RotatingBridge.new()
				bridge.position = _cell_center(solution[route_indices[i]])
				bridge.bridge_size = Vector2(cell_size * 0.66, 7.0)
				bridge.rotation_speed = 0.65 + float(theme_stage) * 0.12
				add_child(bridge)
				special_mechanic_count += 1
		10:
			var placed_lasers := 0
			for cell in candidates:
				_ensure_three_open_sides(cell)
				if _safe_neighbor_count(cell) >= 3:
					var laser := LaserHazard.new()
					laser.position = _cell_center(cell)
					add_child(laser)
					hazard_created.emit(laser)
					placed_lasers += 1
					special_mechanic_count += 1
					if placed_lasers >= count:
						break
		11:
			active_level = maxi(active_level, 9)
			special_mechanic_count = 1
		12:
			for i in range(mini(3, route_indices.size())):
				var plate := SequencePlate.new()
				plate.plate_index = i
				plate.position = _cell_center(solution[route_indices[i]])
				plate.sequence_owner = self
				add_child(plate)
				special_mechanic_count += 1

func get_level_snapshot() -> Array:
	var snapshot: Array = []
	for i in range(get_child_count()):
		var child := get_child(i)
		if not child is Node2D:
			continue
		var entry: Dictionary = {"index": i, "position": (child as Node2D).position, "rotation": (child as Node2D).rotation, "visible": (child as Node2D).visible}
		if child is RigidBody2D:
			entry["velocity"] = (child as RigidBody2D).linear_velocity
		if child is Area2D:
			entry["monitoring"] = (child as Area2D).monitoring
		for property_name in ["triggered", "defeated", "hits", "health", "sequence_next"]:
			for property_info in child.get_property_list():
				if String(property_info.name) == property_name:
					entry[property_name] = child.get(property_name)
					break
		snapshot.append(entry)
	return snapshot

func apply_level_snapshot(snapshot: Array) -> void:
	for entry in snapshot:
		var index := int(entry.get("index", -1))
		if index < 0 or index >= get_child_count():
			continue
		var child := get_child(index)
		if not child is Node2D:
			continue
		(child as Node2D).position = entry.get("position", (child as Node2D).position)
		(child as Node2D).rotation = float(entry.get("rotation", (child as Node2D).rotation))
		(child as Node2D).visible = bool(entry.get("visible", (child as Node2D).visible))
		if child is RigidBody2D and entry.has("velocity"):
			(child as RigidBody2D).linear_velocity = entry["velocity"]
		if child is Area2D and entry.has("monitoring"):
			(child as Area2D).set_deferred("monitoring", bool(entry["monitoring"]))
		for property_name in ["triggered", "defeated", "hits", "health", "sequence_next"]:
			if entry.has(property_name):
				for property_info in child.get_property_list():
					if String(property_info.name) == property_name:
						child.set(property_name, entry[property_name])
						break
		if child.has_method("queue_redraw"):
			child.queue_redraw()

func remove_collected_coins(positions: Array) -> void:
	for child in get_children():
		if child is RigidBody2D and child.is_in_group("coins"):
			for saved_position in positions:
				if (child as Node2D).position.distance_to(saved_position) < 1.0:
					child.queue_free()
					break

func activate_sequence_plate(index: int) -> void:
	if index == sequence_next:
		sequence_next += 1
		if sequence_next >= 3:
			level_mechanic_event.emit("Последовательность разгадана! +12", 12)
			sequence_next = 0
			for child in get_children():
				if child is SequencePlate:
					child.triggered = false
					child.queue_redraw()
		else:
			level_mechanic_event.emit("Верная плита: %d/3" % sequence_next, 0)
	else:
		sequence_next = 0
		for child in get_children():
			if child is SequencePlate:
				child.triggered = false
				child.queue_redraw()
		level_mechanic_event.emit("Неверный порядок — последовательность сброшена", 0)


class HazardVisual:
	extends Node2D
	var radius := 10.0
	var spikes := true
	func _draw() -> void:
		if spikes:
			for i in range(8):
				var angle := TAU * float(i) / 8.0
				var tip := Vector2(cos(angle), sin(angle)) * radius
				var left := Vector2(cos(angle - 0.32), sin(angle - 0.32)) * radius * 0.48
				var right := Vector2(cos(angle + 0.32), sin(angle + 0.32)) * radius * 0.48
				draw_colored_polygon(PackedVector2Array([tip, left, right]), Color("#d88e9a"))
		else:
			draw_circle(Vector2.ZERO, radius, Color("#7d8195"))
			draw_circle(Vector2.ZERO, radius * 0.62, Color("#44475b"))
			draw_circle(Vector2.ZERO, radius * 0.35, Color("#272b3d"))

class GateVisual:
	extends Node2D
	var size := Vector2.ONE
	var color := Color.WHITE
	func _draw() -> void:
		draw_rect(Rect2(-size * 0.5, size), color.darkened(0.18), true, true, 3.0)
		draw_rect(Rect2(-size * 0.5 + Vector2(2, 2), size - Vector2(4, 4)), color, true, true, 2.0)


class PressurePlate:
	extends Area2D
	signal activated(index: int)
	var plate_index := 0
	var triggered := false
	func _ready() -> void:
		add_to_group("puzzle_plates")
		var shape := CircleShape2D.new()
		shape.radius = 13.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		body_entered.connect(_on_body_entered)
		queue_redraw()
	func _on_body_entered(body: Node) -> void:
		if triggered or not body.is_in_group("player"):
			return
		triggered = true
		activated.emit(plate_index)
		queue_redraw()
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 13.0, Color("#d9b7e8") if not triggered else Color("#9bd6b0"))
		draw_circle(Vector2.ZERO, 7.0, Color("#fff8ff"))

class PopSpawnerVisual:
	extends Node2D
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 12.0, Color("#59616d"))
		draw_circle(Vector2.ZERO, 7.0, Color("#ef7880"))
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, Color("#8c98a5"), 3.0)

class SurfaceZone:
	extends Area2D
	var mode := "ice"
	var size_radius := 14.0
	func _ready() -> void:
		add_to_group("special_occupied")
		collision_layer = 0
		collision_mask = 1
		var shape := CircleShape2D.new()
		shape.radius = size_radius
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
		queue_redraw()
	func _on_enter(body: Node) -> void:
		if body.is_in_group("player"):
			body.set_meta("surface_mode", mode)
	func _on_exit(body: Node) -> void:
		if body.is_in_group("player") and body.has_meta("surface_mode"):
			body.remove_meta("surface_mode")
	func _draw() -> void:
		var tint := Color("#a9dff0") if mode == "ice" else Color("#d8c29a") if mode == "sand" else Color("#a9d9b5")
		draw_circle(Vector2.ZERO, size_radius, tint)
		draw_arc(Vector2.ZERO, size_radius - 3.0, 0.0, TAU, 32, Color.WHITE, 2.0)

class PortalPad:
	extends Area2D
	var destination := Vector2.ZERO
	var cooldown := false
	func _ready() -> void:
		add_to_group("special_occupied")
		collision_layer = 0
		collision_mask = 1
		var shape := CircleShape2D.new()
		shape.radius = 13.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		body_entered.connect(_on_enter)
		queue_redraw()
	func _on_enter(body: Node) -> void:
		if not body.is_in_group("player") or body.get_meta("portal_cooldown", false):
			return
		body.set_meta("portal_cooldown", true)
		body.global_position = destination
		if body is RigidBody2D:
			body.linear_velocity = body.linear_velocity.rotated(0.25)
		get_tree().create_timer(0.8).timeout.connect(_clear_cooldown.bind(body))
	func _clear_cooldown(body: Node) -> void:
		if is_instance_valid(body) and body.has_meta("portal_cooldown"):
			body.remove_meta("portal_cooldown")
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 13.0, Color("#8f8ee5"))
		draw_circle(Vector2.ZERO, 8.0, Color("#dcdcff"))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color("#aaa7ff"), 3.0)

class ConveyorZone:
	extends Area2D
	var direction := Vector2.RIGHT
	var active_body: RigidBody2D
	func _ready() -> void:
		add_to_group("special_occupied")
		collision_layer = 0
		collision_mask = 1
		var shape := RectangleShape2D.new()
		shape.size = Vector2(30.0, 22.0)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		body_entered.connect(_on_enter)
		body_exited.connect(_on_exit)
		queue_redraw()
	func _on_enter(body: Node) -> void:
		if body is RigidBody2D and body.is_in_group("player"):
			active_body = body
	func _on_exit(body: Node) -> void:
		if body == active_body:
			active_body = null
	func _physics_process(_delta: float) -> void:
		if is_instance_valid(active_body):
			active_body.apply_central_force(direction * 185.0)
	func _draw() -> void:
		draw_rect(Rect2(-15, -11, 30, 22), Color("#e7c77f"), true)
		for x in [-8.0, 0.0, 8.0]:
			draw_line(Vector2(x - 3.0, 0), Vector2(x + 3.0, 0), Color("#fff4d4"), 2.0)

class SpringPad:
	extends Area2D
	var kick_direction := Vector2.UP
	func _ready() -> void:
		add_to_group("special_occupied")
		collision_layer = 0
		collision_mask = 1
		var shape := CircleShape2D.new()
		shape.radius = 12.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		body_entered.connect(_on_enter)
		queue_redraw()
	func _on_enter(body: Node) -> void:
		if body is RigidBody2D and body.is_in_group("player"):
			(body as RigidBody2D).apply_central_impulse(kick_direction.normalized() * 220.0)
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 12.0, Color("#edb17c"))
		draw_line(Vector2(-7, 3), Vector2(0, -5), Color.WHITE, 3.0)
		draw_line(Vector2(0, -5), Vector2(7, 3), Color.WHITE, 3.0)

class MovingBarrier:
	extends AnimatableBody2D
	var travel := 8.0
	var speed := 1.0
	var barrier_size := Vector2(18.0, 8.0)
	var elapsed := 0.0
	var initial_position := Vector2.ZERO
	func _ready() -> void:
		add_to_group("special_occupied")
		initial_position = position
		sync_to_physics = true
		var shape := RectangleShape2D.new()
		shape.size = barrier_size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		queue_redraw()
	func _physics_process(delta: float) -> void:
		elapsed += delta
		position = initial_position + Vector2(0, sin(elapsed * speed) * travel)
	func _draw() -> void:
		draw_rect(Rect2(-barrier_size * 0.5, barrier_size), Color("#b87985"), true, true, 2.0)

class RotatingBridge:
	extends AnimatableBody2D
	var bridge_size := Vector2(28.0, 7.0)
	var rotation_speed := 0.9
	var elapsed := 0.0
	var initial_rotation := 0.0
	func _ready() -> void:
		add_to_group("special_occupied")
		initial_rotation = rotation
		sync_to_physics = true
		var shape := RectangleShape2D.new()
		shape.size = bridge_size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		queue_redraw()
	func _physics_process(delta: float) -> void:
		elapsed += delta
		rotation = initial_rotation + (sin(elapsed * rotation_speed) * 0.5 + 0.5) * PI * 0.5
	func _draw() -> void:
		draw_rect(Rect2(-bridge_size * 0.5, bridge_size), Color("#9b91d3"), true, true, 2.0)

class MagnetField:
	extends Node2D
	var radius := 70.0
	var strength := 130.0
	func _ready() -> void:
		add_to_group("special_occupied")
	func _physics_process(_delta: float) -> void:
		for player in get_tree().get_nodes_in_group("player"):
			if not is_instance_valid(player) or not (player is RigidBody2D):
				continue
			var offset: Vector2 = global_position - player.global_position
			var distance := offset.length()
			if distance > 1.0 and distance < radius:
				(player as RigidBody2D).apply_central_force(offset.normalized() * strength * (1.0 - distance / radius))
	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(0.42, 0.58, 0.88, 0.10))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color("#8da9df"), 1.5)

class LaserHazard:
	extends Area2D
	var active := false
	var safe_disabled := false
	var pulse_timer: Timer
	func _ready() -> void:
		add_to_group("hazard")
		var shape := RectangleShape2D.new()
		shape.size = Vector2(28.0, 12.0)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		monitoring = false
		pulse_timer = Timer.new()
		pulse_timer.wait_time = 1.35
		pulse_timer.autostart = true
		pulse_timer.timeout.connect(_toggle)
		add_child(pulse_timer)
		queue_redraw()
	func _toggle() -> void:
		active = not active
		monitoring = active and not safe_disabled
		queue_redraw()
	func set_safe_disabled(value: bool) -> void:
		safe_disabled = value
		monitoring = active and not safe_disabled
	func _draw() -> void:
		draw_rect(Rect2(-14, -6, 28, 12), Color("#e9d6dc"), true)
		if active:
			draw_line(Vector2(-14, 0), Vector2(14, 0), Color("#ef5365"), 4.0)
		else:
			draw_circle(Vector2.ZERO, 3.0, Color("#9aa7a0"))

class SequencePlate:
	extends Area2D
	var plate_index := 0
	var sequence_owner: Node
	var triggered := false
	func _ready() -> void:
		add_to_group("puzzle_plates")
		collision_layer = 0
		collision_mask = 1
		var shape := CircleShape2D.new()
		shape.radius = 11.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		body_entered.connect(_on_enter)
		queue_redraw()
	func _on_enter(body: Node) -> void:
		if not body.is_in_group("player") or triggered:
			return
		triggered = true
		if is_instance_valid(sequence_owner):
			sequence_owner.activate_sequence_plate(plate_index)
		queue_redraw()
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 11.0, Color("#d3b5eb") if not triggered else Color("#9bd6b0"))
		draw_circle(Vector2.ZERO, 4.0, Color("#59466d"))

class BossOrb:
	extends Area2D
	signal defeated
	var health := 3
	var target: Node2D
	func _ready() -> void:
		add_to_group("special_occupied")
		input_pickable = true
		var shape := CircleShape2D.new()
		shape.radius = 17.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		body_entered.connect(_on_body)
		input_event.connect(_on_input)
		queue_redraw()
	func _physics_process(delta: float) -> void:
		if not is_instance_valid(target):
			var players := get_tree().get_nodes_in_group("player")
			if not players.is_empty():
				target = players[0] as Node2D
		if is_instance_valid(target):
			global_position = global_position.move_toward(target.global_position, 24.0 * delta)
	func _on_body(body: Node) -> void:
		if body.is_in_group("player") and body is RigidBody2D:
			(body as RigidBody2D).apply_central_impulse((body.global_position - global_position).normalized() * 100.0)
	func _on_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
		var tapped: bool = event is InputEventScreenTouch and event.pressed
		tapped = tapped or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		if not tapped:
			return
		health -= 1
		if health <= 0:
			defeated.emit()
			queue_free()
		else:
			queue_redraw()
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 17.0, Color("#8d3f65"))
		draw_circle(Vector2.ZERO, 13.0, Color("#e65d83"))
		for i in range(health):
			draw_circle(Vector2(-5.0 + float(i) * 5.0, 21.0), 2.0, Color("#ffe5ed"))

class RedPopBall:
	extends RigidBody2D
	signal popped
	var orb_type := "normal"
	var score_value := 2
	func _ready() -> void:
		add_to_group("pop_balls")
		gravity_scale = 0.0
		mass = 0.25
		linear_damp = 1.2
		continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
		input_pickable = true
		var shape := CircleShape2D.new()
		shape.radius = 10.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
		input_event.connect(_on_input_event)
		queue_redraw()
	func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
		var tapped: bool = event is InputEventScreenTouch and event.pressed
		tapped = tapped or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		if tapped:
			popped.emit()
			queue_free()
	func _draw() -> void:
		var orb_color := Color("#efbd5b") if orb_type == "gold" else Color("#74bfe5") if orb_type == "boost" else Color("#f05e68")
		draw_circle(Vector2(0, 2), 11.0, Color("#8e3d48"))
		draw_circle(Vector2.ZERO, 9.5, orb_color)
		draw_circle(Vector2(-3.0, -3.0), 2.5, Color("#fff1d8"))
