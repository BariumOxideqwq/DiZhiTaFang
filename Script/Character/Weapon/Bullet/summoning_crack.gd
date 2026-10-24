extends Area2D

# 此岸渡蚀：场上随机移动的裂隙，碰到敌人造成伤害，
# 生命低于 per 的敌人直接斩杀；升级会变大、变快、斩杀线更高。

var damage := 25.0
var per := 0.1

@export var move_speed: float = 580.0
@export var bounce_random_range: float = 0.45

var move_dir := Vector2.UP
var rng := RandomNumberGenerator.new()

@onready var col_shape: CollisionPolygon2D = $collision_shape


func _ready() -> void:
	rng.randomize()
	move_dir = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()


func _physics_process(delta: float) -> void:
	position += move_dir * move_speed * delta

	var screen_rect: Rect2 = get_viewport_rect()
	var half_extent := Vector2(16, 16)

	var screen_left := screen_rect.position.x
	var screen_right := screen_rect.end.x
	var screen_top := screen_rect.position.y - 120.0
	var screen_bottom := screen_rect.end.y - 300.0

	var hit_left := position.x - half_extent.x <= screen_left
	var hit_right := position.x + half_extent.x >= screen_right
	if hit_left or hit_right:
		move_dir.x *= -1.0
		move_dir.y += rng.randf_range(-bounce_random_range, bounce_random_range)
		move_dir = move_dir.normalized()
		position.x = clampf(position.x, screen_left + half_extent.x, screen_right - half_extent.x)

	var hit_top := position.y - half_extent.y <= screen_top
	var hit_bottom := position.y + half_extent.y >= screen_bottom
	if hit_top or hit_bottom:
		move_dir.y *= -1.0
		move_dir.x += rng.randf_range(-bounce_random_range, bounce_random_range)
		move_dir = move_dir.normalized()
		position.y = clampf(position.y, screen_top + half_extent.y, screen_bottom - half_extent.y)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("_Damage"):
		body._Damage(damage)
		if body.has_method("_kill_by_per"):
			body._kill_by_per(per)


func _on_timer_timeout() -> void:
	# 视觉呼吸，避免看起来像静态贴图
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.55, 0.15)
	tween.tween_property(self, "modulate:a", 0.75, 0.35)


func _on_lifetimer_timeout() -> void:
	var tween := create_tween()
	tween.tween_property(self, "self_modulate", Color(0.0, 0.0, 0.0, 0.03), 1.0)
	await tween.finished
	queue_free()
