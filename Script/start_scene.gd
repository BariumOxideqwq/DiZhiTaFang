extends Node2D


func _ready() -> void:
	$Record.text = GameManager.best_record_text()
	$GuideSwitch.button_pressed = GameManager.tutorial_enabled
	$GuideSwitch.toggled.connect(_on_guide_toggled)


func _on_guide_toggled(pressed: bool) -> void:
	GameManager.set_tutorial_enabled(pressed)


func _on_start_button_button_down() -> void:
	Audio.play("click")
	GameManager._change_scene(GameManager.CHOSING_CHARACTER_PATH)
