extends Area2D

# 法师的魔法阵：普攻魔法弹 + 雷电/炼狱/暴雪/风卷四套技能
# 所有伤害都不再自己维护数值，统一从 GameManager 的角色攻击力派生。

var attack_speed := 8.0

var fire_magic_unlock := false
var frozen_magic_unlock := false
var thunder_magic_unlock := false
var wind_magic_ulock := false
var wind_nums := 1

const MAGIC_BULLET = preload("uid://cnehu81xh83e6")
const THUNDER = preload("uid://d0m2sq4jtrs14")
const FIRE_AREA = preload("uid://dbwn8i1e238o")
const SNOW_CURTAIN = preload("uid://b7u6vvt065k76")
const ARCANE_BOLT = preload("res://Scene/Character/weapon/bullet/arcane_bolt.tscn")

const ARCANE_INTERVAL := 6.0

var a_dir := 1.0
var _arcane_timer := 0.0


func _ready() -> void:
	GameManager.connect("change_target_pos", change_target_pos)
	GameManager.Magic_Cricle = self


func _physics_process(delta: float) -> void:
	$MagicCircle.rotate(delta * PI / 12.0)
	$MagicCircle.modulate.a += delta * a_dir
	if $MagicCircle.modulate.a >= 1.0:
		a_dir = -1.0
	elif $MagicCircle.modulate.a <= 0.0:
		a_dir = 1.0
	_tick_arcane(delta)


# --- 31 魔力解构：周期性朝前方丢出巨大的奥术魔弹 -----------------------------

func _tick_arcane(delta: float) -> void:
	if GameManager.arcane_level <= 0:
		return
	_arcane_timer -= delta
	if _arcane_timer > 0.0:
		return
	_arcane_timer = maxf(ARCANE_INTERVAL - 1.0 * float(GameManager.arcane_level), 2.5)
	_fire_arcane()


func _fire_arcane() -> void:
	var bolt = ARCANE_BOLT.instantiate()
	bolt.setup(GameManager.arcane_level)
	add_child(bolt)
	bolt.global_position = global_position + Vector2.UP.rotated(rotation) * 40.0
	bolt.rotation = rotation
	Audio.play("magic", -6.0)


func change_target_pos(pos: Vector2) -> void:
	look_at(pos)


func _shoot() -> void:
	var magic_ball = MAGIC_BULLET.instantiate()
	add_child(magic_ball)
	magic_ball._set_data(GameManager.dmg_magic_bolt(), 0)
	magic_ball.global_position = global_position
	magic_ball.rotation = rotation + PI / 2.0
	Audio.play("magic")
	await get_tree().create_timer(0.1).timeout
	var r := randi_range(1, 4)
	var bullet = MAGIC_BULLET.instantiate()
	bullet.global_position = global_position
	bullet.rotation = rotation + PI / 2.0
	add_child(bullet)
	bullet._set_data(GameManager.dmg_magic_bolt(), r)


func _on_attack_fixed_timer_timeout() -> void:
	_shoot()
	$attack_fixed_timer.wait_time = 12.0 / attack_speed


func _on_thunder_timer_timeout() -> void:
	if not thunder_magic_unlock:
		return

	var thunder = THUNDER.instantiate()
	thunder.damage = GameManager.dmg_thunder()
	var target_pos: Vector2
	var bodies := get_overlapping_bodies()
	if bodies.size() != 0:
		var cloest = null
		var min_dist := INF
		for body in bodies:
			var dist: float = global_position.distance_squared_to(body.global_position)
			if dist < min_dist:
				cloest = body
				min_dist = dist
		target_pos = cloest.global_position
	else:
		target_pos = Vector2(300.0, 500.0)
	thunder.global_position = target_pos
	add_child(thunder)
	Audio.play("thunder")
	$thunder_timer.wait_time = 8.0 + randf_range(-0.5, 0.5)


func _on_fire_timer_timeout() -> void:
	if not fire_magic_unlock:
		return
	Audio.play("thunder", -14.0)
	for i in range(3):
		var r_x := randf_range(15.0, 650.0)
		var r_y := randf_range(80.0, 1000.0)
		var fire_area = FIRE_AREA.instantiate()
		fire_area.damage = GameManager.dmg_fire()
		fire_area.global_position = Vector2(r_x, r_y)
		add_child(fire_area)
	$fire_timer.wait_time = 10.0 + randf_range(-0.5, 0.5)


func _on_ice_timer_timeout() -> void:
	if not frozen_magic_unlock:
		return

	var snow_curtain = SNOW_CURTAIN.instantiate()
	snow_curtain.damage = GameManager.dmg_snow()
	snow_curtain.global_position = Vector2(-1.0, -180.0)
	add_child(snow_curtain)
	snow_curtain._set_life_time(8.0)
	Audio.play("ice")
	$ice_timer.wait_time = 12.0 + randf_range(-0.5, 0.5)


func _on_wind_magic_timer_timeout() -> void:
	if not wind_magic_ulock:
		return
	Audio.play("wind")
	for j in range(wind_nums):
		for i in range(30):
			var wind = MAGIC_BULLET.instantiate()
			wind._set_data(GameManager.dmg_wind(), 4)
			wind.penetrable = true
			wind.rotation = rotation + float(i) * PI / 36.0
			wind.scale = Vector2(3.0, 3.0)
			wind.global_position = global_position
			add_child(wind)
		await get_tree().create_timer(0.25).timeout
	$wind_magic_timer.wait_time = 8.0 + randf_range(-0.25, 0.25)
