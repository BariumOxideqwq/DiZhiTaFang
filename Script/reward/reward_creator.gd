extends Node2D

const REWARD_PANEL = preload("uid://bxxkbjxtoc6av")


func _creat_reward() -> bool:
	var panel = REWARD_PANEL.instantiate()
	add_child(panel)
	panel.z_index = 10
	return panel.option_count > 0
