extends Node2D


const ENEMY_CREATOR = preload("uid://dgl6l2ayjk6nx")



func _ready() -> void:
	GameManager.connect("GameProgress_forward",_creat_new_creator)
	var enemy_creator = ENEMY_CREATOR.instantiate()
	add_child(enemy_creator)
	enemy_creator._set_data(self,-1,6,0)
	for i in range(3):
		await get_tree().create_timer(3).timeout
		var enemy_creator0 = ENEMY_CREATOR.instantiate()
		add_child(enemy_creator0)
		enemy_creator0._set_data(self,3,3,0)
		
		await get_tree().create_timer(9).timeout
		#var enemy_creator0 = ENEMY_CREATOR.instantiate()
		#var enemy_creator1 = ENEMY_CREATOR.instantiate()
		#add_child(enemy_creator0)
		#add_child(enemy_creator1)
		#enemy_creator0._set_data(self,-1,10.0,1)
		#enemy_creator1._set_data(self,5,5,2)
func _creat_new_creator(progress):
	match progress:
		1:
			var enemy_creator0 = ENEMY_CREATOR.instantiate()
			var enemy_creator1 = ENEMY_CREATOR.instantiate()
			add_child(enemy_creator0)
			add_child(enemy_creator1)
			enemy_creator0._set_data(self,15,5,1)
			enemy_creator1._set_data(self,3,1,0)
		2:
			var enemy_creator0 = ENEMY_CREATOR.instantiate()
			var enemy_creator1 = ENEMY_CREATOR.instantiate()
			add_child(enemy_creator0)
			add_child(enemy_creator1)
			enemy_creator0._set_data(self,-1,10.0,1)
			enemy_creator1._set_data(self,5,5,1)
		3:
			var enemy_creator0 = ENEMY_CREATOR.instantiate()
			var enemy_creator1 = ENEMY_CREATOR.instantiate()
			add_child(enemy_creator0)
			add_child(enemy_creator1)
			enemy_creator0._set_data(self,-1,5.0,2)
			enemy_creator1._set_data(self,8,5,2)
		
