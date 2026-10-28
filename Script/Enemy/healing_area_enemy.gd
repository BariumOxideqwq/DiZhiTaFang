extends Area2D

# 骷髅的治疗圈：只负责治疗，不再用「负伤害」冒充治疗

@onready var _life_timer: Timer = $LifeTimer


func _ready() -> void:
	_life_timer.one_shot = true
	_life_timer.timeout.connect(_on_life_timer_timeout)
	_grow_in()
	_set_life_time(2.0)


func _grow_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(0.85, 0.85), 0.2).from(Vector2(0.01, 0.01))


func _set_life_time(t: float) -> void:
	_life_timer.wait_time = t
	_life_timer.start()


func _physics_process(delta: float) -> void:
	rotate(PI / 12.0 * delta)


func _on_life_timer_timeout() -> void:
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("_Heal"):
		body._Heal(15.0 + float(GameManager.GameProgress) * 3.0, true)
