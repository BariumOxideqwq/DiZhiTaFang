extends Control

# 暂停界面：继续 / 重新开始 / 返回主菜单


func _ready() -> void:
	visible = false


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _on_resume_button_pressed() -> void:
	Audio.play("click")
	close()


func _on_restart_button_pressed() -> void:
	GameManager.start_run(GameManager.Character_option)


func _on_menu_button_pressed() -> void:
	GameManager.return_to_menu()
