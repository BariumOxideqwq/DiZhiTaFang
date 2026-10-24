extends Area2D



func _process(_delta: float) -> void:
	self.modulate.a = randf_range(0.1,0.5)
	
func _ready() -> void:
	var enemies = get_overlapping_bodies()
	enemies.sort_custom(func(a, b):
		return a.global_position.y > b.global_position.y)
	
