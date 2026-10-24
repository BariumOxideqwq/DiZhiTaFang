extends Area2D


var damage = 100.0


func _ready() -> void:
	#var bodies = get_overlapping_bodies()
	##print(bodies)
	#for body in bodies:
		#if body.has_method("_Damage"):
			#body._Damage(damage)
	#await  get_tree().create_timer(0.01).timeout
	$LightningStrikeSheet/AnimationPlayer.play("normal")
	#bodies = get_overlapping_bodies()
	#print(bodies)
	


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "normal":
		var bodies = get_overlapping_bodies()
		for body in bodies:
			if body.has_method("_Damage"):
				body._Damage(damage)
		queue_free()
	


#func _on_body_entered(body: Node2D) -> void:
	#if body.has_method("_Damage"):
		#body._Damage(damage)
