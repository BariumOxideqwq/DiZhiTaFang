@abstract extends CharacterBody2D

# ---------------------------------------------------------------------------
# 敌人基类：伤害 / 治疗 / 减速 / 流血等通用状态都放在这里，
# 子类只负责血量、速度、移动与死亡奖惩。
# 约定：_Damage() 只处理伤害，_Heal() 只处理治疗，两者互不复用。
# ---------------------------------------------------------------------------

const BLEED_MAX := 3
const BLEED_DURATION := 4.0

# 防御值：所有伤害都过这里算一次减免，最多减免 2/3
const DEFENSE_K := 100.0
const MAX_DEFENSE_REDUCTION := 2.0 / 3.0

# 敌人攻击我方召唤单位的参数（想调平衡就改这几个）
const ALLY_ATTACK_RADIUS := 95.0
const ALLY_ATTACK_INTERVAL := 1.2
const ALLY_DAMAGE_MULTIPLIER := 8.0
const ALLY_SCAN_INTERVAL := 0.25
# 被召唤单位缠住时：独立乘区，只按 50% 速度前进（不再被“堵住”原地不动）
const ALLY_ENGAGE_SLOW := 0.5

var Max_HP
var HP
var speed
var skill
var defense := 0.0
var defense_debuff := 0.0        # 防御被降低的比例（0~0.9）
var _defense_debuff_timer := 0.0

# BOSS 专用（普通怪保持 0）
var percent_resist := 0.0        # 比例伤害抗性：最大生命% / 当前生命% / 已损失生命% 都乘 (1-抗性)
var execute_damage_pct := 0.0    # >0 时：斩杀降级为“造成最大生命该比例的伤害”，不再秒杀

var damage

var slow
var slow_down_rate := 1.0
var blood_num := 0

var bleed_stacks := 0
var bleed_time_left := 0.0
var bleed_tick_timer := 0.0

var _flash_tween: Tween
var _slow_tween: Tween
var _ally_target: Node2D
var _ally_scan_timer := 0.0
var _ally_attack_timer := 0.0

@abstract func _move(delta)
@abstract func _Damage(amount)


func _enter_tree() -> void:
	add_to_group("enemies")


func _process(delta: float) -> void:
	_tick_bleed(delta)
	_tick_ally_combat(delta)
	_tick_defense_debuff(delta)


# --- 攻击我方召唤单位 -------------------------------------------------------

func _tick_ally_combat(delta: float) -> void:
	_ally_scan_timer -= delta
	if _ally_scan_timer <= 0.0:
		_ally_scan_timer = ALLY_SCAN_INTERVAL
		_ally_target = _find_ally_target()
	if _ally_target == null:
		return
	_ally_attack_timer -= delta
	if _ally_attack_timer > 0.0:
		return
	_ally_attack_timer = ALLY_ATTACK_INTERVAL
	if _ally_target.has_method("_take_damage"):
		_ally_target._take_damage(damage * ALLY_DAMAGE_MULTIPLIER)


func _find_ally_target() -> Node2D:
	var closest: Node2D = null
	var min_dist := ALLY_ATTACK_RADIUS * ALLY_ATTACK_RADIUS
	for ally in get_tree().get_nodes_in_group("summons"):
		if not is_instance_valid(ally):
			continue
		if ally.has_method("is_alive") and not ally.is_alive():
			continue
		var dist: float = global_position.distance_squared_to(ally.global_position)
		if dist < min_dist:
			min_dist = dist
			closest = ally
	return closest


# 子类共用的移动：被召唤单位缠住时会边打边前进，但只按 50% 速度（独立乘区，
# 与冰冻/减速等 slow_down_rate 相乘，互不覆盖）
func _walk(delta: float) -> void:
	var factor := slow_down_rate
	if _ally_target != null and is_instance_valid(_ally_target):
		factor *= ALLY_ENGAGE_SLOW
	velocity = speed * Vector2(0.0, 10.0) * delta * factor
	move_and_slide()
	_detect_self()


# --- 伤害 -------------------------------------------------------------------

func _mitigate(amount: float) -> float:
	# 防御减免：有效防御 = (防御 × 破甲debuff) - 固定穿透，再乘 (1 - 百分比穿透)，
	# 减免 = eff/(eff+K)，上限 2/3。
	if amount <= 0.0:
		return amount
	var effective := maxf(effective_defense() - GameManager.penetration, 0.0)
	effective *= (1.0 - clampf(GameManager.penetration_pct, 0.0, 1.0))
	var reduction := minf(effective / (effective + DEFENSE_K), MAX_DEFENSE_REDUCTION)
	return amount * (1.0 - reduction)


func effective_defense() -> float:
	return maxf(defense * (1.0 - clampf(defense_debuff, 0.0, 0.9)), 0.0)


# 降低防御（魔力解构 / 解离恶咒图腾）：ratio 为降低比例，duration 秒后恢复
func _lower_defense(ratio: float, duration: float) -> void:
	if ratio <= 0.0 or duration <= 0.0:
		return
	defense_debuff = maxf(defense_debuff, clampf(ratio, 0.0, 0.9))
	_defense_debuff_timer = maxf(_defense_debuff_timer, duration)


func _tick_defense_debuff(delta: float) -> void:
	if defense_debuff <= 0.0:
		return
	_defense_debuff_timer -= delta
	if _defense_debuff_timer <= 0.0:
		defense_debuff = 0.0
		_defense_debuff_timer = 0.0


func _execute() -> void:
	# 斩杀/处决：不吃防御减免
	if HP <= 0.0:
		return
	# BOSS：斩杀降级成一记按最大生命的巨额伤害（仍照常走防御减免）
	if execute_damage_pct > 0.0:
		HP -= _mitigate(Max_HP * execute_damage_pct)
		_finish_per_damage()
		return
	HP = 0.0
	_set_Label()
	_damage_effect()
	_die()


# 比例伤害的统一系数（BOSS 有抗性时会明显变小）
func _percent_factor() -> float:
	return 1.0 - clampf(percent_resist, 0.0, 0.95)


# 按最大生命百分比造成伤害（原初之力 / 火焰弹 / 狙击非斩杀段都走这里）
func _damage_percent_hp(pct: float) -> void:
	if HP <= 0.0 or pct <= 0.0:
		return
	HP -= _mitigate(Max_HP * clampf(pct, 0.0, 1.0) * _percent_factor())
	_finish_per_damage()


func _damage_effect() -> void:
	modulate = Color(1.0, 0.45, 0.45)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.12)


# --- 治疗 -------------------------------------------------------------------

func _Heal(amount: float, raise_max: bool = false) -> void:
	if amount <= 0.0:
		return
	if raise_max:
		Max_HP += amount
	var before: float = HP
	HP = minf(HP + amount, Max_HP)
	HP = snappedf(HP, 0.01)
	_set_Label()
	_heal_effect()
	if HP > before:
		ParticleDirector.spawn_heal(get_tree().current_scene, global_position, self)


func _heal_effect() -> void:
	modulate = Color(0.6, 1.0, 0.65)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.18)


# --- 生命显示 ---------------------------------------------------------------

func _set_Label() -> void:
	var label := get_node_or_null("Show_HP") as Label
	if label == null:
		return
	label.text = str(int(ceil(maxf(HP, 0.0))))


# --- 死亡 -------------------------------------------------------------------

func _die() -> void:
	GameManager.notify_enemy_killed(global_position)
	_Add_Exp()
	queue_free()


func _Add_Exp() -> void:
	pass


# --- 通用状态 ---------------------------------------------------------------

func _detect_self() -> void:
	if global_position.y > 1270:
		GameManager._BeDamaged(damage)
		queue_free()


func _damage_already_hp(per: float) -> void:
	if HP <= 0.0:
		return
	HP -= _mitigate((Max_HP - HP) * clampf(per, 0.0, 1.0) * _percent_factor())
	_finish_per_damage()


func _damage_current_hp(per: float) -> void:
	if HP <= 0.0:
		return
	HP -= _mitigate(HP * clampf(per, 0.0, 1.0) * _percent_factor())
	_finish_per_damage()


func _finish_per_damage() -> void:
	HP = snappedf(HP, 0.01)
	_set_Label()
	if HP <= 0.0:
		_die()


func _kill_by_per(per: float) -> void:
	if HP / Max_HP <= per:
		_execute()
	else:
		_Damage(1.0)


func _slow_down(per: float, t: float) -> void:
	slow_down_rate *= per
	modulate = Color(0.55, 0.8, 1.0)
	if _slow_tween != null and _slow_tween.is_valid():
		_slow_tween.kill()
	_slow_tween = create_tween()
	_slow_tween.tween_interval(t)
	_slow_tween.tween_callback(_restore_slow.bind(per))


func _restore_slow(per: float) -> void:
	slow_down_rate /= per
	modulate = Color.WHITE


func _blood() -> void:
	for i in range(blood_num):
		HP -= HP * 0.01 * blood_num
		_Damage(5.0 * blood_num)


# --- 流血（淬锋之矢）--------------------------------------------------------

func _add_bleed(stacks: int = 1) -> void:
	bleed_stacks = mini(bleed_stacks + stacks, BLEED_MAX)
	bleed_time_left = BLEED_DURATION


func _tick_bleed(delta: float) -> void:
	if bleed_stacks <= 0:
		return
	bleed_time_left -= delta
	bleed_tick_timer += delta
	if bleed_tick_timer >= 0.5:
		bleed_tick_timer = 0.0
		_Damage(GameManager.dmg_bleed() * float(bleed_stacks))
		if not is_inside_tree():
			return
	if bleed_time_left <= 0.0:
		bleed_stacks -= 1
		bleed_time_left = BLEED_DURATION
