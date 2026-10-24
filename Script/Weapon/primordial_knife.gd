extends Node2D

# ---------------------------------------------------------------------------
# 原初飞刀（第一把通用武器）
#   * 挂在角色身上，会在角色附近显示一把小刀，提示“已获得该武器”
#   * 每隔一段较长时间，朝当前朝向投出一把飞刀
#   * 数值全部从 GameManager 的武器状态派生：攻击加成、攻速倍率、
#     原初之力（最大生命百分比）、原初回响（分裂）、职业专属效果
# ---------------------------------------------------------------------------

const KNIFE_PROJECTILE = preload("res://Scene/Weapon/knife_projectile.tscn")

@export var base_damage := 40.0
@export var base_interval := 3.5
@export var min_interval := 0.25
@export var fire_interval := 6.0

var damage := 40.0
var attack_interval := 3.5

var _fire_armed := false
var _bob_time := 0.0
var _icon_base := Vector2(-95.0, -52.0)

@onready var _timer: Timer = $Timer
@onready var _fire_timer: Timer = $FireTimer
@onready var _marker: Marker2D = $Marker2D
@onready var _icon: Sprite2D = $Icon


func _ready() -> void:
	GameManager.weapon_node = self
	GameManager.connect("change_target_pos", _on_aim)
	_timer.timeout.connect(_on_timer_timeout)
	_fire_timer.timeout.connect(_on_fire_timer_timeout)
	refresh_stats()


func _process(delta: float) -> void:
	# 小刀固定在角色身边浮动（抵消武器节点的瞄准旋转），提示已经拿到这把武器
	_bob_time += delta
	_icon.position = _icon_base.rotated(-rotation) + Vector2(0.0, sin(_bob_time * 2.4) * 3.0)
	_icon.rotation = -rotation + 0.55
	_icon.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * sin(_bob_time * 3.1))


func _on_aim(pos: Vector2) -> void:
	if pos.distance_to(global_position) > 1.0:
		look_at(pos)


func refresh_stats() -> void:
	damage = base_damage + GameManager.weapon_damage_bonus
	attack_interval = maxf(base_interval * GameManager.weapon_interval_mult, min_interval)

	# 弓箭手「原初同调」：攻速 = 50% 投掷速度 + 50% 弓箭射速
	if GameManager.weapon_archer_sync:
		var bow = GameManager.Bow
		if bow != null and is_instance_valid(bow) and bow.has_method("get_interval"):
			var knife_rate := 1.0 / attack_interval
			var bow_rate := 1.0 / maxf(bow.get_interval(), 0.05)
			attack_interval = maxf(1.0 / (0.5 * knife_rate + 0.5 * bow_rate), min_interval)

	_timer.wait_time = attack_interval

	# 法师「淬火刀锋」：周期性给下一把飞刀上“命中触发炼狱之路”
	_fire_timer.wait_time = fire_interval
	if GameManager.weapon_magician_fire:
		if _fire_timer.is_stopped():
			_fire_timer.start()
	else:
		_fire_timer.stop()
		_fire_armed = false


func _on_timer_timeout() -> void:
	fire_now()


func _on_fire_timer_timeout() -> void:
	_fire_armed = true
	Audio.play("magic", -16.0)


func fire_now() -> void:
	_spawn_knife(global_position, rotation + PI / 2.0, damage, true)
	Audio.play("shoot", -12.0)


func fire_from(pos: Vector2, angle: float, custom_damage: float = -1.0) -> void:
	# 给召唤师「永葬秘法」用：从裂隙位置随意方向发射（不分裂、不触发淬火）
	var use_damage := damage if custom_damage < 0.0 else custom_damage
	_spawn_knife(pos, angle, use_damage, false)


func _spawn_knife(pos: Vector2, angle: float, knife_damage: float, allow_echo: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var knife = KNIFE_PROJECTILE.instantiate()
	scene.add_child(knife)
	knife.global_position = pos
	knife.rotation = angle
	knife.damage = knife_damage
	knife.max_hp_pct = GameManager.weapon_max_hp_pct()
	knife.echo_level = GameManager.weapon_echo_level if allow_echo else 0
	knife.is_echo = false
	knife.fire_on_hit = _fire_armed and allow_echo
	if knife.fire_on_hit:
		_fire_armed = false
