extends Node2D

# ---------------------------------------------------------------------------
# 图腾：原地不动、没有血量、一段时间后自动消失，对半径内单位持续生效。
#   kind = "hurt" → 范围内敌人持续受伤，并持续被降低防御
#   kind = "heal" → 范围内己方（召唤物）持续恢复生命
# 用法：instantiate() → setup(...) → add_child() → 设置 global_position
# ---------------------------------------------------------------------------

const TICK := 0.5
const HURT_TEXTURE = preload("uid://43ggeg1ejw7a")
const HEAL_TEXTURE = preload("uid://ds67onrjpdqjn")

var kind := "hurt"
var radius := 240.0
var duration := 8.0
var power := 10.0          # hurt：每次 tick 伤害；heal：每次 tick 的治疗比例
var defense_down := 0.0
var defense_down_time := 1.25

var _age := 0.0
var _tick_timer := 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func setup(kind_name: String, radius_value: float, duration_value: float,
		power_value: float, defense_down_value: float = 0.0) -> void:
	kind = kind_name
	radius = radius_value
	duration = duration_value
	power = power_value
	defense_down = defense_down_value
	defense_down_time = TICK * 2.5


func _ready() -> void:
	z_index = 1
	if kind == "hurt":
		_sprite.texture = HURT_TEXTURE
		_sprite.modulate = Color(1.0, 0.82, 0.85, 0.0)
	else:
		_sprite.texture = HEAL_TEXTURE
		_sprite.modulate = Color(0.92, 1.0, 0.95, 0.0)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate:a", 0.95, 0.25)
	tween.parallel().tween_property(self, "scale", Vector2(1.0, 1.0), 0.25).from(Vector2(0.6, 0.6))
	_tick_timer = TICK
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	# 最后 1 秒淡出
	if duration - _age < 1.0:
		_sprite.modulate.a = clampf(duration - _age, 0.0, 1.0) * 0.95
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK
		_apply_tick()


func _apply_tick() -> void:
	if kind == "hurt":
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy):
				continue
			if (enemy as Node2D).global_position.distance_to(global_position) > radius:
				continue
			if enemy.has_method("_Damage"):
				enemy._Damage(power)
			if defense_down > 0.0 and is_instance_valid(enemy) and enemy.has_method("_lower_defense"):
				enemy._lower_defense(defense_down, defense_down_time)
	else:
		for ally in get_tree().get_nodes_in_group("summons"):
			if not is_instance_valid(ally) or not ally.has_method("_heal"):
				continue
			if (ally as Node2D).global_position.distance_to(global_position) > radius:
				continue
			var max_value := float(ally.get("max_hp"))
			if max_value > 0.0:
				ally._heal(max_value * power)


func _draw() -> void:
	var fill := Color(0.9, 0.3, 0.35, 0.10) if kind == "hurt" else Color(0.4, 1.0, 0.6, 0.10)
	var line := Color(0.95, 0.45, 0.5, 0.55) if kind == "hurt" else Color(0.55, 1.0, 0.75, 0.55)
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, line, 3.0)
