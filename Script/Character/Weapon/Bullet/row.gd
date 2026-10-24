extends "res://Script/Character/Weapon/Bullet/Bullet_model.gd"

var damage := 10.0
var per := 0.0
var distance := 0.0
var Max_dis := 10.0


func _set_damage(d: float) -> void:
	damage = d


func _ready() -> void:
	speed = 750.0


func _move(delta: float) -> void:
	var direction := Vector2.UP.rotated(rotation)
	global_position += speed * direction * delta
	distance += delta
	if distance > Max_dis:
		queue_free()


func _physics_process(delta: float) -> void:
	_move(delta)


func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("_Damage"):
		return
	body._Damage(damage)
	if GameManager.archer_bleed_level > 0 and body.has_method("_add_bleed"):
		body._add_bleed(1)
	if body.has_method("_damage_current_hp"):
		body._damage_current_hp(per)
	if body.has_method("_damage_already_hp"):
		body._damage_already_hp(per)
	hp -= 1
	if hp <= 0:
		queue_free()
