extends CanvasLayer
class_name MikrozzUI

signal gate_pressed(index: int, pressed: bool)
signal restart_requested
signal next_level_requested

var root: Control
var hud_label: Label
var message_label: Label
var gate_buttons: Array[Button] = []
var result_panel: PanelContainer
var viewport_size := Vector2.ZERO

func setup(size: Vector2) -> void:
	viewport_size = size
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)
	hud_label = Label.new()
	hud_label.position = Vector2(18, 14)
	hud_label.add_theme_font_size_override("font_size", 19)
	hud_label.add_theme_color_override("font_color", Color("#50695d"))
	root.add_child(hud_label)
	message_label = Label.new()
	message_label.position = Vector2(0, 54)
	message_label.size = Vector2(size.x, 30)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 14)
	message_label.add_theme_color_override("font_color", Color("#6c8075"))
	root.add_child(message_label)

func set_hud(level: int, lives: int, score: int, total: int) -> void:
	hud_label.text = "LEVEL %02d     ♥ %d     COINS %d/%d" % [level, lives, score, total]

func set_message(value: String) -> void:
	message_label.text = value

func make_gate_buttons(count: int) -> void:
	for button in gate_buttons:
		button.queue_free()
	gate_buttons.clear()
	var positions := [Vector2(18, viewport_size.y - 112), Vector2(viewport_size.x - 112, viewport_size.y - 112), Vector2(viewport_size.x * 0.5 - 47, viewport_size.y - 112)]
	for i in range(count):
		var button := Button.new()
		button.text = "HOLD %d" % (i + 1)
		button.position = positions[i]
		button.size = Vector2(94, 76)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_color_override("font_color", Color("#526d60"))
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("#c7e1d1")
		normal.set_corner_radius_all(18)
		normal.border_color = Color("#a8cdb8")
		normal.set_border_width_all(2)
		button.add_theme_stylebox_override("normal", normal)
		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color("#8fbea2")
		pressed.set_corner_radius_all(18)
		pressed.border_color = Color("#719e84")
		pressed.set_border_width_all(2)
		button.add_theme_stylebox_override("pressed", pressed)
		button.button_down.connect(_on_gate_down.bind(i))
		button.button_up.connect(_on_gate_up.bind(i))
		root.add_child(button)
		gate_buttons.append(button)

func _on_gate_down(index: int) -> void:
	gate_pressed.emit(index, true)

func _on_gate_up(index: int) -> void:
	gate_pressed.emit(index, false)

func show_result(title: String, detail: String, allow_next: bool) -> void:
	if result_panel != null:
		result_panel.queue_free()
	result_panel = PanelContainer.new()
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_panel.position = Vector2(-150, -115)
	result_panel.size = Vector2(300, 230)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fffaf0")
	style.border_color = Color("#bfd8c8")
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	result_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	result_panel.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", Color("#587565"))
	box.add_child(heading)
	var body := Label.new()
	body.text = detail
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", Color("#718579"))
	box.add_child(body)
	var action := Button.new()
	action.text = "NEXT LEVEL" if allow_next else "TRY AGAIN"
	action.custom_minimum_size = Vector2(180, 48)
	action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action.pressed.connect(_on_result_action.bind(allow_next))
	box.add_child(action)
	root.add_child(result_panel)

func _on_result_action(allow_next: bool) -> void:
	if result_panel != null:
		result_panel.queue_free()
		result_panel = null
	if allow_next:
		next_level_requested.emit()
	else:
		restart_requested.emit()

func hide_result() -> void:
	if result_panel != null:
		result_panel.queue_free()
		result_panel = null
