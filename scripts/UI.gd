extends CanvasLayer
class_name MikrozzUI

signal gate_pressed(index: int, pressed: bool)
signal restart_requested
signal next_level_requested
signal calibrate_requested
signal touch_direction_changed(direction: Vector2)
signal settings_changed(key: String, value: Variant)
signal settings_pause_changed(paused: bool)

var root: Control
var hud_label: Label
var message_label: Label
var sensor_label: Label
var gate_buttons: Array[Button] = []
var direction_buttons: Array[Button] = []
var result_panel: PanelContainer
var settings_panel: PanelContainer
var settings_overlay: ColorRect
var viewport_size := Vector2.ZERO
var settings_open := false
var current_music := 0.32
var current_sfx := 0.75
var current_sensitivity := 1.65
var current_vibration := true

func setup(size: Vector2) -> void:
	viewport_size = size
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(root)
	hud_label = Label.new()
	hud_label.position = Vector2(18, 14)
	hud_label.size = Vector2(size.x - 92, 30)
	hud_label.add_theme_font_size_override("font_size", 19)
	hud_label.add_theme_color_override("font_color", Color("#50695d"))
	root.add_child(hud_label)
	message_label = Label.new()
	message_label.position = Vector2(10, 52)
	message_label.size = Vector2(size.x - 20, 30)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 13)
	message_label.add_theme_color_override("font_color", Color("#6c8075"))
	root.add_child(message_label)
	sensor_label = Label.new()
	sensor_label.position = Vector2(18, 84)
	sensor_label.size = Vector2(190, 24)
	sensor_label.add_theme_font_size_override("font_size", 11)
	sensor_label.add_theme_color_override("font_color", Color("#6c8075"))
	sensor_label.text = "TILT SENSOR: CHECKING..."
	root.add_child(sensor_label)
	var calibrate := Button.new()
	calibrate.text = "CALIBRATE"
	calibrate.position = Vector2(size.x - 112, 80)
	calibrate.size = Vector2(94, 32)
	calibrate.focus_mode = Control.FOCUS_NONE
	calibrate.add_theme_font_size_override("font_size", 11)
	calibrate.pressed.connect(func(): calibrate_requested.emit())
	root.add_child(calibrate)
	var settings_button := Button.new()
	settings_button.text = "⚙"
	settings_button.position = Vector2(size.x - 58, 10)
	settings_button.size = Vector2(42, 36)
	settings_button.focus_mode = Control.FOCUS_NONE
	settings_button.add_theme_font_size_override("font_size", 22)
	settings_button.pressed.connect(func(): open_settings(current_music, current_sfx, current_sensitivity, current_vibration))
	root.add_child(settings_button)
	_build_direction_pad()

func _build_direction_pad() -> void:
	var base := Vector2(18, viewport_size.y - 154)
	var specs := [
		{"text": "↑", "offset": Vector2(42, 0), "direction": Vector2.UP},
		{"text": "←", "offset": Vector2(0, 42), "direction": Vector2.LEFT},
		{"text": "↓", "offset": Vector2(42, 42), "direction": Vector2.DOWN},
		{"text": "→", "offset": Vector2(84, 42), "direction": Vector2.RIGHT}
	]
	for spec in specs:
		var button := Button.new()
		button.text = spec.text
		button.position = base + spec.offset
		button.size = Vector2(40, 40)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_color", Color("#50695d"))
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("#d7eadf")
		normal.border_color = Color("#9abda8")
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(12)
		button.add_theme_stylebox_override("normal", normal)
		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color("#8fbea2")
		pressed.set_corner_radius_all(12)
		button.add_theme_stylebox_override("pressed", pressed)
		var direction: Vector2 = spec.direction
		button.button_down.connect(func(): touch_direction_changed.emit(direction))
		button.button_up.connect(func(): touch_direction_changed.emit(Vector2.ZERO))
		root.add_child(button)
		direction_buttons.append(button)

func set_settings_defaults(music: float, sfx: float, sensitivity: float, vibration: bool) -> void:
	current_music = music
	current_sfx = sfx
	current_sensitivity = sensitivity
	current_vibration = vibration

func open_settings(music: float, sfx: float, sensitivity: float, vibration: bool) -> void:
	if settings_open:
		return
	settings_open = true
	settings_pause_changed.emit(true)
	settings_overlay = ColorRect.new()
	settings_overlay.color = Color(0.12, 0.18, 0.15, 0.62)
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(settings_overlay)
	settings_panel = PanelContainer.new()
	settings_panel.position = Vector2((viewport_size.x - 340) * 0.5, (viewport_size.y - 410) * 0.5)
	settings_panel.size = Vector2(340, 410)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#fffaf0")
	panel_style.border_color = Color("#bfd8c8")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(22)
	settings_panel.add_theme_stylebox_override("panel", panel_style)
	settings_overlay.add_child(settings_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_theme_constant_override("margin_left", 18)
	box.add_theme_constant_override("margin_right", 18)
	box.add_theme_constant_override("margin_top", 16)
	box.add_theme_constant_override("margin_bottom", 16)
	settings_panel.add_child(box)
	var heading := Label.new()
	heading.text = "GAME SETTINGS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", Color("#587565"))
	box.add_child(heading)
	_add_slider(box, "MUSIC VOLUME", music, "music")
	_add_slider(box, "SOUND EFFECTS", sfx, "sfx")
	_add_slider(box, "TILT SENSITIVITY", sensitivity, "sensitivity", 0.5, 3.0)
	var vibration_toggle := CheckButton.new()
	vibration_toggle.text = "Vibration on events"
	vibration_toggle.button_pressed = vibration
	vibration_toggle.toggled.connect(func(value: bool): settings_changed.emit("vibration", value))
	box.add_child(vibration_toggle)
	var hint := Label.new()
	hint.text = "Progress and settings save automatically."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color("#87968c"))
	box.add_child(hint)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(140, 42)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_settings)
	box.add_child(close)

func _add_slider(parent: VBoxContainer, caption: String, initial: float, key: String, minimum: float = 0.0, maximum: float = 1.0) -> void:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("#61796b"))
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = clampf(initial, minimum, maximum)
	slider.custom_minimum_size = Vector2(270, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float): settings_changed.emit(key, value))
	parent.add_child(slider)

func close_settings() -> void:
	if not settings_open:
		return
	settings_open = false
	if is_instance_valid(settings_overlay):
		settings_overlay.queue_free()
	settings_overlay = null
	settings_panel = null
	settings_pause_changed.emit(false)

func set_sensor_status(available: bool, magnitude: float) -> void:
	if available:
		sensor_label.text = "TILT SENSOR: ACTIVE  %.1f" % magnitude
		sensor_label.add_theme_color_override("font_color", Color("#477d5c"))
	else:
		sensor_label.text = "TILT SENSOR: UNAVAILABLE"
		sensor_label.add_theme_color_override("font_color", Color("#b06d65"))

func set_hud(level: int, lives: int, score: int, total: int) -> void:
	hud_label.text = "LEVEL %02d     ♥ %d     COINS %d/%d" % [level, lives, score, total]

func set_message(value: String) -> void:
	message_label.text = value

func make_gate_buttons(count: int) -> void:
	for button in gate_buttons:
		button.queue_free()
	gate_buttons.clear()
	for i in range(count):
		var button := Button.new()
		button.text = "HOLD %d" % (i + 1)
		button.position = Vector2(viewport_size.x - 112, viewport_size.y - 112 - float(i) * 84.0)
		button.size = Vector2(94, 72)
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
	close_settings()
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
