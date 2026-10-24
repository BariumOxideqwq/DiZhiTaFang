extends Node

# ---------------------------------------------------------------------------
# 召唤师技能管理器（挂在召唤师场景下）
# 逐个轮询 GameManager 里的技能等级，负责：
#   15 此岸渡蚀  —— 维持一个在场上乱撞的裂隙
#   17 行炁淬锋  —— 周期治疗城墙 + 暂时强化召唤物
#   18 负向幻觉  —— 周期随机传送 / 抹除敌人
# （16 溶原增殖由 GameManager 在敌人死亡时生成临时单位）
# ---------------------------------------------------------------------------

const HALLUCINATION_FX = preload("res://Scene/Character/weapon/bullet/unnameable_hole.tscn")

const HEAL_INTERVAL := 8.0
const HALLUCINATION_INTERVAL := 7.0

# 28 永葬秘法
const BURIAL_INTERVAL := 12.0
const BURIAL_DURATION := 3.0
const BURIAL_SHOT_INTERVAL := 0.1

var _crack: Area2D
var _applied_crack_level := -1
var _heal_timer := 0.0
var _hallucination_timer := 0.0
var _burial_timer := 0.0
var _burial_left := 0.0
var _burial_shot := 0.0


func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	_tick_crack()
	_tick_heal(delta)
	_tick_hallucination(delta)
	_tick_burial(delta)


# --- 15 此岸渡蚀 ------------------------------------------------------------

func _tick_crack() -> void:
	if GameManager.summon_crack_level <= 0:
		return
	if _crack != null and not is_instance_valid(_crack):
		_crack = null
	if _crack == null:
		_spawn_crack()
	elif GameManager.summon_crack_level != _applied_crack_level:
		_apply_crack_level()


func _spawn_crack() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_crack = GameManager.SUMMONING_CRACK.instantiate()
	scene.add_child(_crack)
	_crack.global_position = Vector2(360.0, 900.0)
	var life_timer := _crack.get_node_or_null("lifetimer")
	if life_timer != null:
		life_timer.stop()
	_applied_crack_level = -1
	_apply_crack_level()


func _apply_crack_level() -> void:
	if _crack == null:
		return
	_applied_crack_level = GameManager.summon_crack_level
	var extra := float(_applied_crack_level - 1)
	_crack.per = 0.10 + 0.05 * extra
	_crack.damage = 25.0 + 15.0 * extra
	_crack.move_speed = 580.0 + 90.0 * extra
	_crack.scale = Vector2(0.75, 0.75) * (1.0 + 0.12 * extra)


# --- 17 行炁淬锋 ------------------------------------------------------------

func _tick_heal(delta: float) -> void:
	if GameManager.summon_heal_level <= 0:
		return
	_heal_timer -= delta
	if _heal_timer > 0.0:
		return
	_heal_timer = HEAL_INTERVAL
	GameManager._heal_wall(GameManager.summon_heal_level)
	_heal_allies()
	GameManager.Heal_and_enhance_by_summoner.emit()
	Audio.play("heal")


func _heal_allies() -> void:
	var ratio := 0.30 + 0.05 * float(GameManager.summon_heal_level)
	for ally in get_tree().get_nodes_in_group("summons"):
		if not is_instance_valid(ally) or not ally.has_method("_heal"):
			continue
		var max_value := float(ally.get("max_hp"))
		if max_value > 0.0:
			ally._heal(max_value * ratio)


# --- 18 负向幻觉 ------------------------------------------------------------

func _tick_hallucination(delta: float) -> void:
	if GameManager.summon_hallucination_level <= 0:
		return
	_hallucination_timer -= delta
	if _hallucination_timer > 0.0:
		return
	_hallucination_timer = HALLUCINATION_INTERVAL
	_trigger_hallucination()


func _trigger_hallucination() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return
	var erase_chance := 0.05 * float(GameManager.summon_hallucination_level)
	var max_targets := mini(enemies.size(), 5)
	for i in max_targets:
		var enemy: Node2D = enemies.pick_random()
		if not is_instance_valid(enemy):
			continue
		if randf() < erase_chance and enemy.has_method("_Damage"):
			enemy._Damage(enemy.Max_HP * 10.0)
		else:
			enemy.global_position = Vector2(randf_range(80.0, 640.0), randf_range(-200.0, 300.0))
	_play_hallucination_fx()


func _play_hallucination_fx() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fx = HALLUCINATION_FX.instantiate()
	scene.add_child(fx)
	Audio.play("wind", -14.0)
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(fx):
		fx.queue_free()


# --- 28 永葬秘法：从此岸渡蚀的位置向四周连射飞刀 -----------------------------

func _tick_burial(delta: float) -> void:
	if not GameManager.weapon_summoner_burial:
		return
	if _crack == null or not is_instance_valid(_crack):
		return
	if _burial_left > 0.0:
		_burial_left -= delta
		_burial_shot -= delta
		while _burial_shot <= 0.0 and _burial_left > 0.0:
			_burial_shot += BURIAL_SHOT_INTERVAL
			_fire_burial_knife()
		return
	_burial_timer -= delta
	if _burial_timer <= 0.0:
		_burial_timer = BURIAL_INTERVAL
		_burial_left = BURIAL_DURATION
		_burial_shot = 0.0


func _fire_burial_knife() -> void:
	if _crack == null or not is_instance_valid(_crack):
		return
	var weapon = GameManager.weapon_node
	if weapon == null or not is_instance_valid(weapon) or not weapon.has_method("fire_from"):
		return
	weapon.fire_from((_crack as Node2D).global_position, randf() * TAU)
