extends Node2D

const ROW = preload("uid://bqkjktosk0whc")

var shoot_times := 1
var shoot_speed := 10.0
var damage := 20.0
var hp := 1
var _san_she_times := 0
var per := 0.0
var kill_line := 0.0


func _ready() -> void:
	GameManager.connect("change_target_pos", change_target_pos)
	GameManager.Bow = self


func change_target_pos(pos: Vector2) -> void:
	look_at(pos)


func get_interval() -> float:
	# 给「原初同调」用：当前弓箭的射击间隔
	return 8.0 / (shoot_speed + 0.55)


func _on_timer_timeout() -> void:
	_shoot()


func _shoot() -> void:
	for i in range(shoot_times):
		var bullet = ROW.instantiate()
		_inital_bullet(bullet)
		bullet.global_position = $Marker2D.global_position + _bullet_offset(i)
		add_child(bullet)
	$Timer.wait_time = 8.0 / (shoot_speed + 0.55)
	Audio.play("shoot")


func _bullet_offset(i: int) -> Vector2:
	# 0 号箭在正中间，之后左右交替排开
	if i == 0:
		return Vector2.ZERO
	var step := floori(i / 2.0)
	if i % 2 == 1:
		return Vector2(25.0, 0.0) * float(step + 1)
	return Vector2(-25.0, 0.0) * float(step)


func _inital_bullet(bullet) -> void:
	bullet.damage = damage
	bullet.hp = hp
	bullet.per = per
	bullet.rotation = rotation + PI / 2.0


func _san_she() -> void:
	if _san_she_times <= 0:
		return
	Audio.play("wind")
	for k in range(_san_she_times):
		for j in range(32):
			for i in range(shoot_times):
				var bullet = ROW.instantiate()
				_inital_bullet(bullet)
				bullet.rotation = j * PI / 16.0
				bullet.global_position = $Marker2D.global_position + _bullet_offset(i)
				add_child(bullet)
		# 「原初同调」：散射时错开时间也投出一把原初飞刀
		if GameManager.weapon_archer_sync and GameManager.weapon_node != null \
				and is_instance_valid(GameManager.weapon_node) \
				and GameManager.weapon_node.has_method("fire_now"):
			await get_tree().create_timer(0.05).timeout
			GameManager.weapon_node.fire_now()
		await get_tree().create_timer(0.1).timeout


func _on_sanshe_timer_timeout() -> void:
	_san_she()


func _detect_cloest() -> void:
	if kill_line <= 0.0:
		return
	var bodies: Array = $Detect_Enemies.get_overlapping_bodies()
	var cloest := INF
	var target = null
	for body in bodies:
		if body == null:
			continue
		var dist: float = global_position.distance_squared_to(body.global_position)
		if dist < cloest:
			cloest = dist
			target = body
	if target != null:
		if target.HP / target.Max_HP <= kill_line:
			if target.has_method("_Damage"):
				target._Damage(target.HP + 10.0)
		else:
			if target.has_method("_Damage"):
				target._Damage(target.Max_HP * (kill_line - 0.05))


func _on_kill_line_timeout() -> void:
	_detect_cloest()
