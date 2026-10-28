extends Control

# 战斗 HUD：城墙耐久 + 经验条/等级（打印已移除，避免每杀一只就刷日志）

var _exp_tween: Tween


func _ready() -> void:
	GameManager.connect("change_Exp", _change_exp_ui)
	GameManager.connect("Damage_Wall", _change_wall_hp)
	GameManager.emit_signal("change_Exp")
	GameManager.emit_signal("Damage_Wall")


func _change_wall_hp() -> void:
	# 城墙上限被 BOSS 奖励抬高后，同时显示「当前/上限」
	if GameManager.Wall_Max > GameManager.WALL_MAX_HEALTH:
		$Show_Box_01/show_Wall_HP.text = "城墙耐久度:%d/%d" % [GameManager.Wall_Health, GameManager.Wall_Max]
	else:
		$Show_Box_01/show_Wall_HP.text = "城墙耐久度:" + str(GameManager.Wall_Health)


func _change_exp_ui() -> void:
	var ratio := clampf(100.0 * GameManager.Exp_cur / GameManager.Exp_max, 0.0, 100.0)
	if _exp_tween != null and _exp_tween.is_valid():
		_exp_tween.kill()
	_exp_tween = create_tween()
	_exp_tween.tween_property($Exp_Bar, "value", ratio, 0.2)
	$Lv.text = "Lv " + str(GameManager.level)


func _on_pause_button_pressed() -> void:
	if GameManager.is_game_over:
		return
	Audio.play("click")
	var panel := get_tree().current_scene.get_node_or_null("Overlay/PausePanel")
	if panel != null and panel.has_method("open"):
		panel.open()
