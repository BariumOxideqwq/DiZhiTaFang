extends Area2D

# 炼狱之路的火场：落地后持续一段时间，只造成伤害

var target_size := Vector2(1.5, 1.5)
var damage := 50.0

@onready var _life_timer: Timer = $LifeTimer


func _ready() -> void:
	_life_timer.one_shot = true
	_life_timer.timeout.connect(_on_life_timer_timeout)
	_play_spawn()
	_set_life_time(5.0)


func _play_spawn() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", target_size, 0.6).from(Vector2(0.05, 0.05))
	tween.parallel().tween_property($EffectRound, "modulate", Color(0.82, 0.0, 0.0, 0.42), 0.1)


func _set_life_time(t: float) -> void:
	_life_timer.wait_time = t
	_life_timer.start()
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.01, t)


func _on_life_timer_timeout() -> void:
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("_Damage"):
		body._Damage(damage)
		body._Damage(0.15 * body.Max_HP)
