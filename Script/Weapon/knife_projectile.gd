extends Area2D

# 原初飞刀投射物：命中敌人造成伤害；可选附加“目标最大生命百分比”、
# 命中分裂残影、以及在命中处触发炼狱之路。

var damage := 40.0
var max_hp_pct := 0.0        # 原初之力：0 / 3% / 6% / 9%
var echo_level := 0          # 原初回响等级
var is_echo := false         # 残影不再分裂
var fire_on_hit := false     # 淬火刀锋
var speed := 950.0
var max_distance := 14.0

var _travelled := 0.0

const ECHO_RATIO := [0.0, 0.4, 0.55, 0.7]
const ECHO_ANGLE := 0.45


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += Vector2.UP.rotated(rotation) * speed * delta
	_travelled += delta
	if _travelled > max_distance:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("_Damage"):
		return
	body._Damage(damage)
	if max_hp_pct > 0.0 and is_instance_valid(body):
		# 比例伤害统一走 _damage_percent_hp（BOSS 有比例抗性）
		if body.has_method("_damage_percent_hp"):
			body._damage_percent_hp(max_hp_pct)
		else:
			body._Damage(body.Max_HP * max_hp_pct)
	if fire_on_hit:
		_spawn_fire_at(global_position)
	if echo_level > 0 and not is_echo and is_instance_valid(get_tree().current_scene):
		_spawn_echoes()
	queue_free()


func _spawn_echoes() -> void:
	var ratio: float = ECHO_RATIO[clampi(echo_level, 0, ECHO_RATIO.size() - 1)]
	var scene := get_tree().current_scene
	if scene == null:
		return
	for sign_value in [-1.0, 1.0]:
		var echo = load("res://Scene/Weapon/knife_projectile.tscn").instantiate()
		scene.add_child(echo)
		echo.global_position = global_position
		echo.rotation = rotation + ECHO_ANGLE * sign_value
		echo.damage = damage * ratio
		echo.max_hp_pct = max_hp_pct
		echo.is_echo = true
		echo.echo_level = 0
		echo.fire_on_hit = false


func _spawn_fire_at(pos: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fire = load("uid://dbwn8i1e238o").instantiate()
	scene.add_child(fire)
	fire.global_position = pos
	# 统一伤害：火焰伤害由角色攻击力派生
	fire.damage = GameManager.dmg_fire()
	fire._set_life_time(4.0)
