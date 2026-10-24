extends "res://Script/Character/Weapon/Bullet/Bullet_model.gd"


var type = 0
var damage = 15.0
#var per= 0.0
var distance = 0.0
var Max_dis = 10.0
var penetrable = false
var slow_down = false
var fire_attack = false
var repel_attack = false


#var sprites = [$MagicBall,$ThunderBall,$IceBall,$Fireball,$WindSprite]

func _set_data(d,t):
	damage = d
	type = t
	match type :
		0:
			$MagicBall.show()
			#print("Magic_Ball")
			#print($MagicBall.visible)
		1:
			$ThunderBall.show()
			penetrable = true
		2:
			$IceBall.show()
			slow_down = true
			
		3:
			$Fireball.show()
			fire_attack = true
		4:
			$WindSprite.show()
			repel_attack = true
			if $WindSprite.has_node("AnimationPlayer"):
				$WindSprite/AnimationPlayer.play("normal")
	


func _ready() -> void:
	speed = 750.0
	#hp = 1
	#sprites[type].show()
	#print("my hp =" +str(hp))
	
func _move(delta):
	var direction = Vector2.UP.rotated(rotation)
	global_position += speed*direction*delta
	distance += delta
	if distance > Max_dis :
		queue_free()
func _physics_process(delta: float) -> void:
	_move(delta)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("_Damage"):
		body._Damage(damage)
		if slow_down:
			if body.has_method("_slow_down"):
				body._slow_down(0.8,5)
		if fire_attack:
			body._Damage(0.15*body.Max_HP)
		if repel_attack:
			body.global_position += Vector2(0,-15)
		if !penetrable:
			queue_free()
