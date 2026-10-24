@abstract extends CharacterBody2D

# ---------------------------------------------------------------------------
# 敌人基类：伤害 / 治疗 / 减速 / 流血等通用状态都放在这里，
# 子类只负责血量、速度、移动与死亡奖惩。
# 约定：_Damage() 只处理伤害，_Heal() 只处理治疗，两者互不复用。
# ---------------------------------------------------------------------------

const BLEED_MAX := 3
const BLEED_DURATION := 4.0

# 敌人攻击我方召唤单位的参数（想调平衡就改这三个）
const ALLY_ATTACK_RADIUS := 95.0
const ALLY_ATTACK_INTERVAL := 1.2
const ALLY_DAMAGE_MULTIPLIER := 8.0
const ALLY_SCAN_INTERVAL := 0.25

var Max_HP
var HP
var speed
var skill

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


# 子类共用的移动：被召唤单位缠住时原地攻击，否则按原速度前进
func _walk(delta: float) -> void:
	if _ally_target != null and is_instance_valid(_ally_target):
		velocity = Vector2.ZERO
	else:
		velocity = speed * Vector2(0.0, 10.0) * delta * slow_down_rate
	move_and_slide()
	_detect_self()


# --- 伤害 -------------------------------------------------------------------

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
	HP = minf(HP + amount, Max_HP)
	HP = snappedf(HP, 0.01)
	_set_Label()
	_heal_effect()


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
	HP -= (Max_HP - HP) * clampf(per, 0.0, 1.0)
	_finish_per_damage()


func _damage_current_hp(per: float) -> void:
	if HP <= 0.0:
		return
	HP -= HP * clampf(per, 0.0, 1.0)
	_finish_per_damage()


func _finish_per_damage() -> void:
	HP = snappedf(HP, 0.01)
	_set_Label()
	if HP <= 0.0:
		_die()


func _kill_by_per(per: float) -> void:
	if HP / Max_HP <= per:
		_Damage(Max_HP * 10.0)
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
		_Damage(GameManager.archer_bleed_dps * float(bleed_stacks))
		if not is_inside_tree():
			return
	if bleed_time_left <= 0.0:
		bleed_stacks -= 1
		bleed_time_left = BLEED_DURATION
