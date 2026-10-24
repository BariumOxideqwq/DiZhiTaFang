extends Node2D



func _ready() -> void:
	if GameManager.Character_option == 0:
		var character = GameManager.ARCHER.instantiate()
		character.global_position = Vector2(-300,1220)
		add_child(character)
	elif GameManager.Character_option == 1:
		var character = GameManager.MAGICIAN.instantiate()
		character.global_position = Vector2(-300,1220)
		add_child(character)
	elif GameManager.Character_option == 2:
		var character = GameManager.SUMMONER.instantiate()
		character.global_position = Vector2(-300,1220)
		add_child(character)
