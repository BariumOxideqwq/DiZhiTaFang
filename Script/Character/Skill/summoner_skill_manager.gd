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
const TOTEM = preload("res://Scene/Totem/totem.tscn")

const HEAL_INTERVAL := 8.0
const HALLUCINATION_INTERVAL := 7.0

# 32 解离恶咒 / 33 解脱恩赐
const TOTEM_CURSE_INTERVAL := 10.0
const TOTEM_CURSE_RETRY := 2.0     # 场上没有敌人时 2 秒后重试（不白等一整个冷却）
const TOTEM_BLESSING_INTERVAL := 12.0
const CURSE_RANGE := 620.0

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
var _curse_timer := 0.0
var _blessing_timer := 0.0


func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	_tick_crack()
	_tick_heal(delta)
	_tick_hallucination(delta)
	_tick_burial(delta)
	_tick_totems(delta)


# --- 15 此岸渡蚀 ------------------------------------------------------------

func _tick_crack() -> void:
	if GameManager.summon_crack_level <= 0:
		return
	if _crack != null and not is_instance_valid(_crack):
		_crack = null
	if _crack == null:
		_spawn_crack()
	else:
		if GameManager.summon_crack_level != _applied_crack_level:
			_apply_crack_level()
		# 统一伤害：裂隙伤害由角色攻击力派生（等级/奖励变化时保持同步）
		_crack.damage = GameManager.dmg_crack()


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
	_crack.damage = GameManager.dmg_crack()
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
	var allies: Array = []
	for ally in get_tree().get_nodes_in_group("summons"):
		if is_instance_valid(ally) and ally.has_method("_heal"):
			allies.append(ally)
	# 粒子名额有限：先治疗离玩家最近的单位，保证看得见的单位优先有特效
	var character := get_tree().get_first_node_in_group("character") as Node2D
	var origin := Vector2(360.0, 1300.0)
	if character != null:
		origin = character.global_position
	allies.sort_custom(func(a, b) -> bool:
		var da: float = (a as Node2D).global_position.distance_squared_to(origin)
		var db: float = (b as Node2D).global_position.distance_squared_to(origin)
		return da < db
	)
	for ally in allies:
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
			# 用 _execute 而不是 10 倍血量的固定伤害：BOSS 会把斩杀降级成大额伤害
			if enemy.has_method("_execute"):
				enemy._execute()
			else:
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


# --- 32 解离恶咒 / 33 解脱恩赐：图腾 -----------------------------------------

func _tick_totems(delta: float) -> void:
	if GameManager.totem_curse_level > 0:
		_curse_timer -= delta
		if _curse_timer <= 0.0:
			# 只有真的放下图腾才进冷却；放不下就 2 秒后重试，不白等 10 秒
			_curse_timer = TOTEM_CURSE_INTERVAL if _place_curse_totem() else TOTEM_CURSE_RETRY
	if GameManager.totem_blessing_level > 0:
		_blessing_timer -= delta
		if _blessing_timer <= 0.0:
			_blessing_timer = TOTEM_BLESSING_INTERVAL
			_place_blessing_totem()


func _place_curse_totem() -> bool:
	# 优先级：自身 620px 内的敌人 → 全场离自己最近的敌人 → 随机场上位置（同解脱恩赐）
	var origin := _own_position()
	var in_range: Array = []
	var nearest: Node2D = null
	var nearest_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist: float = (enemy as Node2D).global_position.distance_to(origin)
		if dist <= CURSE_RANGE:
			in_range.append(enemy)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	var spot: Vector2
	if not in_range.is_empty():
		var target: Node2D = in_range.pick_random()
		spot = target.global_position + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
	elif nearest != null:
		# 范围内没有敌人：退而求其次，丢在场上最近那只敌人身边
		spot = nearest.global_position + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
	else:
		# 场上一个敌人都没有：和解脱恩赐一样落在随机场上位置
		spot = _random_blessing_spot()

	var level: int = GameManager.totem_curse_level
	# 统一伤害：图腾每跳伤害由角色攻击力派生
	return _spawn_totem("hurt", _clamp_field(spot),
		200.0 + 30.0 * float(level), 8.0 + float(level),
		GameManager.dmg_totem(), 0.20 + 0.10 * float(level))


func _place_blessing_totem() -> void:
	var level: int = GameManager.totem_blessing_level
	_spawn_totem("heal", _random_blessing_spot(),
		220.0 + 30.0 * float(level), 8.0 + float(level),
		0.02 + 0.01 * float(level), 0.0)


func _spawn_totem(kind: String, spot: Vector2, radius_value: float, duration_value: float,
		power_value: float, defense_down_value: float) -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var totem = TOTEM.instantiate()
	totem.setup(kind, radius_value, duration_value, power_value, defense_down_value)
	scene.add_child(totem)
	totem.global_position = spot
	Audio.play("heal" if kind == "heal" else "hurt", -14.0)
	return true


func _own_position() -> Vector2:
	var owner_node := get_parent()
	if owner_node is Node2D:
		return (owner_node as Node2D).global_position
	return Vector2(360.0, 1300.0)


func _clamp_field(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 70.0, 650.0), clampf(pos.y, -60.0, 1000.0))


func _random_blessing_spot() -> Vector2:
	# 三角分布：中间的落点概率最高，越靠边缘越低
	var x := 360.0 + (randf_range(-1.0, 1.0) + randf_range(-1.0, 1.0)) * 0.5 * 300.0
	var y := 560.0 + (randf_range(-1.0, 1.0) + randf_range(-1.0, 1.0)) * 0.5 * 420.0
	return _clamp_field(Vector2(x, y))


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
