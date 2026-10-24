extends "res://Script/Enemy/Enemy_model.gd"


func _ready() -> void:
	Max_HP = 100.0
	HP = 100.0 + (GameManager.GameProgress * (10 + (GameManager.GameProgress - 1)))
	speed = 150.0 + (GameManager.GameProgress * (10 + (GameManager.GameProgress - 1)))
	damage = 1
	_set_Label()


func _physics_process(delta: float) -> void:
	_move(delta)
	if not $AnimationPlayer.is_playing():
		$AnimationPlayer.play("walk")


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
