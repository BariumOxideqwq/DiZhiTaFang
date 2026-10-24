extends Area2D

# ---------------------------------------------------------------------------
# 溶原增殖生成的临时召唤单位：
#   * 有血量，会被敌人攻击，也能被「行炁淬锋」治疗
#   * 平时每隔一段时间随机挪动一小段（缓慢游荡）
#   * 索敌范围内有敌人时，缓慢朝最近的敌人移动
#   * 攻击范围略大于自己本体，按固定间隔对范围内敌人造成伤害
# 攻击/索敌半径都按贴图实际大小自动换算，换美术不用改数值。
# ---------------------------------------------------------------------------

const ATTACK_RADIUS_FACTOR := 1.15   # 本体半径 × 1.15（略大于本体）
const DETECT_RADIUS_FACTOR := 2.4     # 远大于本体
const SEPARATION_FACTOR := 0.95       # 互相推开的间距 ≈ 本体宽度的 95%
const SEPARATION_SPEED := 130.0
const MOVE_SPEED_IDLE := 55.0
const MOVE_SPEED_CHASE := 105.0
const WANDER_INTERVAL := Vector2(1.6, 3.0)
const WANDER_STEP := Vector2(70.0, 170.0)
const FIELD_RECT := Rect2(40.0, -140.0, 640.0, 1220.0)

@export var base_damage := 4.0
@export var max_hp := 40.0

var damage := 4.0
var hp := 40.0
var buff_mult := 1.0
var life := 12.0
var attack_interval := 0.5

var body_size := 0.0
var attack_radius := 60.0
var detect_radius := 240.0
var separation_radius := 100.0

var _attack_timer := 0.0
var _wander_timer := 0.0
var _has_wander_target := false
var _wander_target := Vector2.ZERO
var _buff_tween: Tween
var _flash_tween: Tween
var _dead := false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _hit_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("summons")
	add_to_group("summon_minions")
	GameManager.Heal_and_enhance_by_summoner.connect(_on_enhance)
	_fit_radii()
	hp = max_hp
	recalc_damage()
	apply_attack_interval()
	_wander_timer = randf_range(WANDER_INTERVAL.x, WANDER_INTERVAL.y)


func apply_attack_interval() -> void:
	# 攻速继承本体，但只有本体的一半 → 攻击间隔是本体的两倍
	attack_interval = GameManager.summon_attack_interval * 2.0


func setup(minion_damage: float, life_time: float, hp_max: float = 40.0) -> void:
	base_damage = minion_damage
	life = life_time
	max_hp = hp_max
	hp = max_hp
	recalc_damage()


func _fit_radii() -> void:
	var rect := _sprite.get_rect().size * _sprite.scale
	body_size = maxf(rect.x, rect.y)
	attack_radius = body_size * 0.5 * ATTACK_RADIUS_FACTOR
	detect_radius = body_size * DETECT_RADIUS_FACTOR
	separation_radius = body_size * SEPARATION_FACTOR
	var shape := CircleShape2D.new()
	shape.radius = attack_radius
	_hit_shape.shape = shape


func is_alive() -> bool:
	return not _dead


func recalc_damage() -> void:
	damage = (base_damage + GameManager.summon_damage_bonus) * buff_mult


# --- 生命 -------------------------------------------------------------------

func _take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	hp -= amount
	_flash(Color(1.0, 0.5, 0.5, 1.0))
	if hp <= 0.0:
		_die()


func _heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	hp = minf(hp + amount, max_hp)
	_flash(Color(0.6, 1.0, 0.7, 1.0))


func _die() -> void:
	_dead = true
	hp = 0.0
	queue_free()


func _flash(color: Color) -> void:
	modulate = color
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.15)


func _on_enhance() -> void:
	buff_mult = 1.5
	recalc_damage()
	if _buff_tween != null and _buff_tween.is_valid():
		_buff_tween.kill()
	_buff_tween = create_tween()
	_buff_tween.tween_interval(GameManager.summon_buff_duration)
	_buff_tween.tween_callback(_end_enhance)


func _end_enhance() -> void:
	buff_mult = 1.0
	recalc_damage()


# --- 每帧：存活时间 / 移动 / 攻击 -------------------------------------------

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or _dead:
		return
	life -= delta
	if _sprite != null:
		_sprite.modulate.a = clampf(life / 2.0, 0.2, 0.9)
	if life <= 0.0:
		queue_free()
		return
	_update_move(delta)
	_apply_separation(delta)
	_update_attack(delta)


func _apply_separation(delta: float) -> void:
	# 和同类保持间距，避免一堆临时单位叠在同一个点上
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("summon_minions"):
		if other == self or not is_instance_valid(other):
			continue
		var offset: Vector2 = global_position - (other as Node2D).global_position
		var dist := offset.length()
		if dist >= separation_radius:
			continue
		if dist < 0.01:
			var angle := randf() * TAU
			push += Vector2(cos(angle), sin(angle))
		else:
			var strength := 1.0 - dist / separation_radius
			push += offset / dist * strength
	if push == Vector2.ZERO:
		return
	global_position = _clamp_to_field(global_position + push.normalized() * SEPARATION_SPEED * delta)


func _update_move(delta: float) -> void:
	var enemy := _nearest_enemy()
	if enemy != null:
		_has_wander_target = false
		_move_toward(enemy.global_position, MOVE_SPEED_CHASE, delta)
		return

	if _has_wander_target:
		if global_position.distance_to(_wander_target) < 10.0:
			_has_wander_target = false
			_wander_timer = randf_range(WANDER_INTERVAL.x, WANDER_INTERVAL.y)
		else:
			_move_toward(_wander_target, MOVE_SPEED_IDLE, delta)
		return

	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_target = _pick_wander_target()
		_has_wander_target = true


func _pick_wander_target() -> Vector2:
	var angle := randf() * TAU
	var distance := randf_range(WANDER_STEP.x, WANDER_STEP.y)
	var target := global_position + Vector2(cos(angle), sin(angle)) * distance
	return _clamp_to_field(target)


func _clamp_to_field(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, FIELD_RECT.position.x, FIELD_RECT.end.x),
		clampf(pos.y, FIELD_RECT.position.y, FIELD_RECT.end.y)
	)


func _move_toward(target: Vector2, speed: float, delta: float) -> void:
	global_position = _clamp_to_field(global_position.move_toward(target, speed * delta))


func _nearest_enemy() -> Node2D:
	var closest: Node2D = null
	var min_dist := detect_radius * detect_radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist: float = global_position.distance_squared_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			closest = enemy
	return closest


# --- 攻击 -------------------------------------------------------------------

func _update_attack(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_interval
	var hit := false
	for body in get_overlapping_bodies():
		if body.has_method("_Damage"):
			body._Damage(damage)
			hit = true
	if hit:
		Audio.play("hit", -18.0)
