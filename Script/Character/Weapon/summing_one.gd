extends Area2D

# ---------------------------------------------------------------------------
# 召唤物一号：追击最近的敌人，每 0.5s 对重叠的敌人造成伤害。
# 它现在有血量：会被敌人攻击，也能被「行炁淬锋」治疗；
# 被击倒后 4 秒在召唤师身边重新召唤（满血）。
# ---------------------------------------------------------------------------

const RESPAWN_DELAY := 4.0

@export var base_damage := 5.0
@export var weight := 0.1
@export var max_hp := 150.0

var damage := 5.0
var hp := 150.0
var targetpos := Vector2(360.0, 1500.0)
var buff_mult := 1.0

var _dead := false
var _respawn_timer := 0.0
var _buff_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	add_to_group("summons")
	add_to_group("summoner_units")
	GameManager.Heal_and_enhance_by_summoner.connect(_on_enhance)
	hp = max_hp
	recalc_damage()
	apply_attack_interval()


func apply_attack_interval() -> void:
	# 「提升攻速」奖励改的是全局攻击间隔，这里同步到自己的攻击计时器
	var timer: Timer = $Timer
	timer.wait_time = GameManager.summon_attack_interval


func recalc_damage() -> void:
	damage = (base_damage + GameManager.summon_damage_bonus) * buff_mult


func is_alive() -> bool:
	return not _dead


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
	visible = false
	_respawn_timer = RESPAWN_DELAY
	Audio.play("hurt", -14.0)


func _respawn() -> void:
	_dead = false
	hp = max_hp
	visible = true
	var host := get_parent()
	if host is Node2D:
		global_position = (host as Node2D).global_position + Vector2(0.0, -160.0)


func _flash(color: Color) -> void:
	modulate = color
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.15)


# --- 增益 -------------------------------------------------------------------

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


# --- 跟随与攻击 -------------------------------------------------------------

func _setTarget(pos: Vector2) -> void:
	targetpos = pos


func _physics_process(delta: float) -> void:
	if _dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	global_position = global_position.slerp(targetpos, weight)


func _on_timer_timeout() -> void:
	if _dead:
		return
	var bodies := get_overlapping_bodies()
	if bodies.is_empty():
		return
	for body in bodies:
		if body.has_method("_Damage"):
			body._Damage(damage)
