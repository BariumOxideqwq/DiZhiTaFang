extends "res://Script/Enemy/Enemy_model.gd"


func _ready() -> void:
	Max_HP = 500.0
	HP = 500.0 + ((GameManager.GameProgress - 1) * 100)
	Max_HP = maxf(Max_HP, HP)
	speed = 100.0
	defense = 20.0 + float(GameManager.GameProgress) * 6.0
	damage = 1
	_set_Label()


func _physics_process(delta: float) -> void:
	_move(delta)
	if not $AnimationPlayer.is_playing():
		$AnimationPlayer.play("walk")


func _move(delta: float) -> void:
	_walk(delta)


func _Damage(amount: float) -> void:
	# 地鼠额外有 5% 的物理减伤（旧特性，保留）
	HP -= _mitigate(amount) * 0.95
	HP = snappedf(HP, 0.01)
	_damage_effect()
	if HP <= 0.0:
		_die()
		return
	_set_Label()


func _Add_Exp() -> void:
	GameManager._Change_Exp(Max_HP / 20.0)
