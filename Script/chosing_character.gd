extends Node2D

# 选择角色：统一走 GameManager.start_run()，开局会重置上一局的状态。


func _on_archer_button_button_down() -> void:
	GameManager.start_run(0)


func _on_magcian_button_button_down() -> void:
	GameManager.start_run(1)


func _on_summoner_button_button_down() -> void:
	GameManager.start_run(2)
