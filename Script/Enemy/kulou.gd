extends "res://Script/Enemy/Enemy_model.gd"


const HEALING_AREA_ENEMY = preload("uid://ctxd4cmlcp4ih")


func _ready() -> void:
	Max_HP = 1000.0 + (GameManager.GameProgress * (100 + (GameManager.GameProgress - 1)))
	HP = 1000.0 + (GameManager.GameProgress * (100 + (GameManager.GameProgress - 1)))
	speed = 200.0 + (GameManager.GameProgress * (10 + (GameManager.GameProgress - 1)))
	damage = 2
	_set_Label()


func _physics_process(delta: float) -> void:
	_move(delta)


func _move(delta: float) -> void:
	_walk(delta)


func _Damage(amount: float) -> void:
	HP -= amount
	HP = snappedf(HP, 0.01)
	_damage_effect()
	if HP <= 0.0:
		_die()
		return
	_set_Label()


func _Add_Exp() -> void:
	GameManager._Change_Exp(Max_HP / 20.0)


func _healing() -> void:
	var healing_area = HEALING_AREA_ENEMY.instantiate()
	get_tree().current_scene.add_child(healing_area)
	healing_area.global_position = global_position


func _on_healing_timer_timeout() -> void:
	_healing()
