extends Button

signal hold_changed(held: bool)

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	button_down.connect(func(): hold_changed.emit(true))
	button_up.connect(func(): hold_changed.emit(false))
