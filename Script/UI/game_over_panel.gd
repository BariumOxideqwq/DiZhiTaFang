extends Control

# 结算界面：显示本局成绩、最高记录，提供重开与返回主菜单。


func _ready() -> void:
	visible = false
	GameManager.game_over.connect(_on_game_over)


func _on_game_over(stats: Dictionary) -> void:
	$Panel/Margin/VBox/Title.text = "城墙被攻破了"
	$Panel/Margin/VBox/StatTime.text = "存活时间    " + GameManager.format_time(stats["time"])
	$Panel/Margin/VBox/StatInfo.text = "等级 Lv %d     波次 %d     击杀 %d" % [
		stats["level"], stats["wave"], stats["kills"],
	]
	if stats["new_record"]:
		$Panel/Margin/VBox/Record.text = "★ 新纪录！"
	else:
		$Panel/Margin/VBox/Record.text = "最高记录：Lv %d · %s" % [
			GameManager.best_level, GameManager.format_time(GameManager.best_time),
		]
	visible = true


func _on_restart_button_pressed() -> void:
	GameManager.start_run(GameManager.Character_option)


func _on_menu_button_pressed() -> void:
	GameManager.return_to_menu()
