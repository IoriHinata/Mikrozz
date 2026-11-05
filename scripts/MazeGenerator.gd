extends Node2D
class_name MazeGenerator

signal coin_body_created(coin: RigidBody2D)
signal hazard_created(area: Area2D)
signal exit_created(area: Area2D)

const CoinScript = preload("res://scripts/Coin.gd")

const PALETTES := [
	{"floor": Color("#e8f3e9"), "wall": Color("#91b8a4"), "accent": Color("#a8d2bd")},
	{"floor": Color("#fff0e7"), "wall": Color("#d7a48d"), "accent": Color("#f2c2a9")},
	{"floor": Color("#f0ebfa"), "wall": Color("#a99acb"), "accent": Color("#c7b8e8")},
	{"floor": Color("#fbf5d9"), "wall": Color("#c8b66f"), "accent": Color("#e8d98f")},
	{"floor": Color("#e7f2fa"), "wall": Color("#8eafc9"), "accent": Color("#b4d5e8")}
]

var cols := 7
var rows := 9
var cell_size := 42.0
var origin := Vector2.ZERO
var palette: Dictionary
var cells: Array = []
var solution: Array[Vector2i] = []
var gate_bodies: Array[StaticBody2D] = []
var gate_visuals: Array[Node2D] = []
var start_position := Vector2.ZERO
var finish_position := Vector2.ZERO
var board_rect := Rect2()

func generate(level_number: int, viewport_size: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	gate_bodies.clear()
	gate_visuals.clear()
	cols = 7
	rows = 9 + mini(2, int((level_number - 1) / 4))
	var usable := Vector2(viewport_size.x - 28.0, viewport_size.y - 190.0)
	cell_size = floorf(minf(usable.x / cols, usable.y / rows))
	cell_size = maxf(cell_size, 32.0)
	var board_size := Vector2(cols * cell_size, rows * cell_size)
	origin = Vector2((viewport_size.x - board_size.x) * 0.5, 76.0 + (usable.y - board_size.y) * 0.5)
	board_rect = Rect2(origin, board_size)
	palette = PALETTES[(level_number - 1) % PALETTES.size()]
	_build_cells()
	_build_solution()
	_build_geometry(level_number)
	_build_objects(level_number)
	queue_redraw()

func _build_cells() -> void:
	cells.clear()
	for y in range(rows):
		var row_data: Array = []
		for x in range(cols):
			row_data.append({"walls": [true, true, true, true], "visited": false})
		cells.append(row_data)
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	cells[0][0]["visited"] = true
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var opposites := [2, 3, 0, 1]
	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var choices: Array[int] = []
		for d in range(4):
			var next_cell: Vector2i = current + dirs[d]
			if next_cell.x >= 0 and next_cell.x < cols and next_cell.y >= 0 and next_cell.y < rows and not cells[next_cell.y][next_cell.x]["visited"]:
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

func _build_solution() -> void:
	solution.clear()
	var start := Vector2i.ZERO
	var target := Vector2i(cols - 1, rows - 1)
	var queue: Array[Vector2i] = [start]
	var previous: Dictionary = {start: Vector2i(-1, -1)}
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == target:
			break
		for d in range(4):
			if not cells[current.y][current.x]["walls"][d]:
				var next_cell: Vector2i = current + dirs[d]
				if not previous.has(next_cell):
					previous[next_cell] = current
					queue.append(next_cell)
	var cursor := target
	while cursor != Vector2i(-1, -1):
		solution.push_front(cursor)
		cursor = previous.get(cursor, Vector2i(-1, -1))
	start_position = _cell_center(start)
	finish_position = _cell_center(target)

func _build_geometry(level_number: int) -> void:
	var gate_edges: Dictionary = {}
	var candidates: Array[Dictionary] = []
	for i in range(2, solution.size() - 1):
		if i % maxi(3, 7 - int(level_number / 3)) == 0:
			var a: Vector2i = solution[i - 1]
			var b: Vector2i = solution[i]
			var d := _direction_index(b - a)
			candidates.append({"cell": a, "direction": d, "position": (_cell_center(a) + _cell_center(b)) * 0.5})
	var gate_limit := mini(3, 1 + int((level_number - 1) / 2))
	candidates.resize(mini(candidates.size(), gate_limit))
	for gate in candidates:
		gate_edges[_edge_key(gate.cell, gate.direction)] = gate
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			for d in range(4):
				if cells[y][x]["walls"][d]:
					_add_wall(_wall_center(cell, d), _wall_size(d))
				elif gate_edges.has(_edge_key(cell, d)):
					_add_gate(gate_edges[_edge_key(cell, d)].position, d)
	_add_wall(Vector2(board_rect.get_center().x, board_rect.position.y - 5), Vector2(board_rect.size.x + 10, 10))
	_add_wall(Vector2(board_rect.get_center().x, board_rect.end.y + 5), Vector2(board_rect.size.x + 10, 10))
	_add_wall(Vector2(board_rect.position.x - 5, board_rect.get_center().y), Vector2(10, board_rect.size.y))
	_add_wall(Vector2(board_rect.end.x + 5, board_rect.get_center().y), Vector2(10, board_rect.size.y))

func _build_objects(level_number: int) -> void:
	var coin_count := clampi(3 + int(level_number / 2), 3, 10)
	for i in range(coin_count):
		var path_index := clampi(int((float(i + 1) / float(coin_count + 1)) * (solution.size() - 1)), 1, solution.size() - 2)
		var coin := CoinScript.new()
		coin.position = _cell_center(solution[path_index]) + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		add_child(coin)
		coin_body_created.emit(coin)
	var hazard_count := mini(12, maxi(0, int((level_number - 1) * 1.15)))
	var placed := 0
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			if cell in solution or cell == Vector2i.ZERO or cell == Vector2i(cols - 1, rows - 1):
				continue
			if placed < hazard_count and randf() < 0.3:
				var hazard := _make_hazard(_cell_center(cell), cell_size * 0.22, placed % 2 == 0)
				add_child(hazard)
				if level_number >= 3:
					var travel := Vector2(cell_size * 0.20, 0)
					var motion := hazard.create_tween().set_loops()
					motion.tween_property(hazard, "position", _cell_center(cell) + travel, 0.9).from(_cell_center(cell) - travel)
					motion.tween_property(hazard, "position", _cell_center(cell) - travel, 0.9)
				hazard_created.emit(hazard)
				placed += 1
	var exit_area := Area2D.new()
	exit_area.name = "Exit"
	exit_area.add_to_group("exit")
	exit_area.position = finish_position
	var exit_shape := CircleShape2D.new()
	exit_shape.radius = 16.0
	var exit_collision := CollisionShape2D.new()
	exit_collision.shape = exit_shape
	exit_area.add_child(exit_collision)
	add_child(exit_area)
	exit_created.emit(exit_area)

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

func _add_gate(at: Vector2, direction: int) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.add_to_group("gates")
	var size := Vector2(9.0, cell_size * 0.82) if direction % 2 == 1 else Vector2(cell_size * 0.82, 9.0)
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
	gate_visuals.append(visual)

func set_gate_open(index: int, opened: bool) -> void:
	if index < 0 or index >= gate_bodies.size():
		return
	for child in gate_bodies[index].get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", opened)
	gate_visuals[index].visible = not opened

func _cell_center(cell: Vector2i) -> Vector2:
	return origin + Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

func _wall_center(cell: Vector2i, d: int) -> Vector2:
	var center := _cell_center(cell)
	match d:
		0: return center + Vector2(0, -cell_size * 0.5)
		1: return center + Vector2(cell_size * 0.5, 0)
		2: return center + Vector2(0, cell_size * 0.5)
		_: return center + Vector2(-cell_size * 0.5, 0)

func _wall_size(d: int) -> Vector2:
	return Vector2(cell_size + 4, 9) if d % 2 == 0 else Vector2(9, cell_size + 4)

func _direction_index(delta: Vector2i) -> int:
	if delta == Vector2i(0, -1): return 0
	if delta == Vector2i(1, 0): return 1
	if delta == Vector2i(0, 1): return 2
	return 3

func _edge_key(cell: Vector2i, d: int) -> String:
	return "%d,%d:%d" % [cell.x, cell.y, d]

func _draw() -> void:
	draw_rect(board_rect, palette.floor, true)
	draw_rect(board_rect, palette.wall.darkened(0.08), false, 3.0)
	for y in range(rows):
		for x in range(cols):
			var rect := Rect2(origin + Vector2(x * cell_size + 3, y * cell_size + 3), Vector2(cell_size - 6, cell_size - 6))
			draw_rect(rect, palette.floor.lightened(0.025), true)
	draw_circle(start_position, 11, Color("#b5d9c2"))
	draw_circle(finish_position, 13, Color("#f2d99a"))
	draw_circle(finish_position, 7, Color("#fff8df"))

class HazardVisual:
	extends Node2D
	var radius := 10.0
	var spikes := true
	func _draw() -> void:
		if spikes:
			for i in range(8):
				var a := TAU * float(i) / 8.0
				var tip := Vector2(cos(a), sin(a)) * radius
				var left := Vector2(cos(a - 0.32), sin(a - 0.32)) * radius * 0.48
				var right := Vector2(cos(a + 0.32), sin(a + 0.32)) * radius * 0.48
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
		draw_rect(Rect2(-size * 0.5, size), color, true)
		draw_rect(Rect2(-size * 0.5, size), color.darkened(0.2), false, 2.0)
