extends Node2D
class_name MazeGenerator

signal coin_body_created(coin: RigidBody2D)
signal hazard_created(hazard: Area2D)
signal exit_created(exit_area: Area2D)

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
var start_position := Vector2.ZERO
var finish_position := Vector2.ZERO
var board_rect := Rect2()
var wall_count := 0
var shape_id := 0
var start_cell := Vector2i.ZERO
var target_cell := Vector2i.ZERO

func generate(level_number: int, viewport_size: Vector2) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	gate_bodies.clear()
	wall_count = 0
	cols = 9 if level_number >= 5 else 7
	rows = 11 if level_number >= 5 else 9
	var usable := Vector2(viewport_size.x - 34.0, viewport_size.y - 238.0)
	cell_size = floorf(minf(usable.x / cols, usable.y / rows))
	cell_size = maxf(cell_size, 26.0)
	var board_size := Vector2(cols * cell_size, rows * cell_size)
	origin = Vector2((viewport_size.x - board_size.x) * 0.5, 92.0 + (usable.y - board_size.y) * 0.5)
	board_rect = Rect2(origin, board_size)
	palette = PALETTES[posmod(maxi(0, level_number), PALETTES.size())]
	shape_id = 0 if level_number <= 0 else posmod(level_number - 1, 4)
	_build_cells()
	_build_solution()
	_build_geometry(level_number)
	_build_objects(level_number)
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

func _build_solution() -> void:
	solution.clear()
	var queue: Array[Vector2i] = [start_cell]
	var previous: Dictionary = {start_cell: Vector2i(-1, -1)}
	var distance: Dictionary = {start_cell: 0}
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var farthest := start_cell
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
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
	var cursor := target_cell
	while cursor != Vector2i(-1, -1):
		solution.push_front(cursor)
		cursor = previous.get(cursor, Vector2i(-1, -1))
	start_position = _cell_center(start_cell)
	finish_position = _cell_center(target_cell)

func _build_geometry(level_number: int) -> void:
	var gate_edges: Dictionary = {}
	var candidates: Array[Dictionary] = []
	var spacing := maxi(4, 8 - int(level_number / 3))
	for i in range(3, solution.size() - 2):
		if i % spacing == 0:
			var a: Vector2i = solution[i - 1]
			var b: Vector2i = solution[i]
			candidates.append({"a": a, "b": b, "position": (_cell_center(a) + _cell_center(b)) * 0.5})
	var gate_limit := mini(3, 1 + int(maxi(0, level_number - 1) / 3))
	for i in range(mini(candidates.size(), gate_limit)):
		var edge: Dictionary = candidates[i]
		gate_edges[_edge_key(edge.a, edge.b)] = edge
	var dirs := [Vector2i(0, -1), Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for y in range(rows):
		for x in range(cols):
			if not cells[y][x]["inside"]:
				continue
			var cell := Vector2i(x, y)
			for d in range(4):
				var neighbor := cell + dirs[d]
				var outside := neighbor.x < 0 or neighbor.x >= cols or neighbor.y < 0 or neighbor.y >= rows or not cells[neighbor.y][neighbor.x]["inside"]
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
	var hazard_count := mini(12, maxi(0, int((level_number - 1) * 1.15)))
	var candidates: Array[Vector2i] = []
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			if cell not in solution and cell != Vector2i.ZERO and cell != Vector2i(cols - 1, rows - 1):
				candidates.append(cell)
	candidates.shuffle()
	for i in range(mini(hazard_count, candidates.size())):
		var hazard := _make_hazard(_cell_center(candidates[i]), cell_size * 0.20, i % 2 == 0)
		add_child(hazard)
		hazard_created.emit(hazard)
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
	var size := Vector2(11.0, cell_size * 0.88) if vertical else Vector2(cell_size * 0.88, 11.0)
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
	return origin + Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

func _wall_center(cell: Vector2i, d: int) -> Vector2:
	return _cell_edge_center(cell, d)

func _wall_size(d: int) -> Vector2:
	return Vector2(12, cell_size + 5) if d == 1 else Vector2(cell_size + 5, 12)

func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var first := a if (a.y < b.y or (a.y == b.y and a.x < b.x)) else b
	var second := b if first == a else a
	return "%d,%d|%d,%d" % [first.x, first.y, second.x, second.y]

func _draw() -> void:
	for y in range(rows):
		for x in range(cols):
			if not cells[y][x]["inside"]:
				continue
			var rect := Rect2(origin + Vector2(x * cell_size + 1, y * cell_size + 1), Vector2(cell_size - 2, cell_size - 2))
			draw_rect(rect, palette.floor.lightened(0.02), true)
			draw_rect(rect, palette.wall.lightened(0.58), false, 1.0)
			var cell := Vector2i(x, y)
			for d in range(4):
				var neighbor := cell + [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][d]
				var outside := neighbor.x < 0 or neighbor.x >= cols or neighbor.y < 0 or neighbor.y >= rows or not cells[neighbor.y][neighbor.x]["inside"]
				if outside or ((d == 1 or d == 2) and cells[y][x]["walls"][d]):
					var edge_center := _cell_edge_center(cell, d)
					var horizontal := d == 0 or d == 2
					var half := cell_size * 0.5
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
		0: return center + Vector2(0, -cell_size * 0.5)
		1: return center + Vector2(cell_size * 0.5, 0)
		2: return center + Vector2(0, cell_size * 0.5)
		_: return center + Vector2(-cell_size * 0.5, 0)

func _cell_edge_size(direction: int) -> Vector2:
	return Vector2(cell_size + 5, 12) if direction == 0 or direction == 2 else Vector2(12, cell_size + 5)

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
