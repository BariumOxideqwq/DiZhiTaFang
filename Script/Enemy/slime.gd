extends "res://Script/Enemy/Enemy_model.gd"


func _ready() -> void:
	Max_HP = 100.0
	HP = 100.0 + (GameManager.GameProgress * (10 + (GameManager.GameProgress - 1)))
	# 血量成长后最大血量也要跟上，否则治疗会被"上限"反倒扣血
	Max_HP = maxf(Max_HP, HP)
	speed = 150.0 + (GameManager.GameProgress * (10 + (GameManager.GameProgress - 1)))
	defense = 8.0 + float(GameManager.GameProgress) * 4.0
	damage = 1
	_set_Label()


func _physics_process(delta: float) -> void:
	_move(delta)
	if not $AnimationPlayer.is_playing():
		$AnimationPlayer.play("walk")


func _move(delta: float) -> void:
	_walk(delta)


func _Damage(amount: float) -> void:
	HP -= _mitigate(amount)
	HP = snappedf(HP, 0.01)
	_damage_effect()
	if HP <= 0.0:
		_die()
		return
	_set_Label()


func _Add_Exp() -> void:
	GameManager._Change_Exp(Max_HP / 20.0)
