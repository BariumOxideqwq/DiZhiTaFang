extends Area2D

# 雪虐风饕：全屏持续伤害 + 减速

var damage := 5.0

@onready var _life_timer: Timer = $LifeTimer


func _ready() -> void:
	_life_timer.one_shot = true
	_life_timer.timeout.connect(_on_life_timer_timeout)


func _set_life_time(t: float) -> void:
	_life_timer.wait_time = t
	_life_timer.start()
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.01, t)


func _on_life_timer_timeout() -> void:
	queue_free()


func _on_timer_timeout() -> void:
	var bodies := get_overlapping_bodies()
	for body in bodies:
		if body.has_method("_Damage"):
			body._Damage(damage)
			if body.has_method("_slow_down"):
				body._slow_down(0.8, 2.5)
