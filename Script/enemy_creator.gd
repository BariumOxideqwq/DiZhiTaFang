extends Node2D


var par = null
var hp = -1
#var Enemy_Arr = [GameManager.SLIME]
var fixed_time = 7.5
var monster_type = 0

func _set_data(p,h,f_t,type):
	par = p
	hp =h
	fixed_time = f_t
	monster_type = type

func _creat_monster(type):
	if GameManager.tutorial_active:
		return
	var enemy = GameManager.Enemy_Arr[type].instantiate()
	enemy.global_position = Vector2(randf_range(80,500),-210+randf_range(-5,5))
	par.add_child(enemy)


func _on_timer_timeout() -> void:
	_creat_monster(monster_type)
	$Timer.wait_time = fixed_time +randf_range(-0.1,0.1)
	hp -= 1
	if hp == 0:
		queue_free()
	elif hp < 0:
		hp = -1
