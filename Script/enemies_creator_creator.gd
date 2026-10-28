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


func _add_creator(hp: int, interval: float, monster_type: int) -> void:
	var creator = ENEMY_CREATOR.instantiate()
	add_child(creator)
	creator._set_data(self, hp, interval, monster_type)


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
			enemy_creator0._set_data(self,-1,10.0,2)
			enemy_creator1._set_data(self,3,7.5,2)
		_:
			# 12 级（progress = 4）之后：出怪量递增，间隔随进度缩短到下限为止
			var extra := float(progress - 4)
			_add_creator(-1, maxf(8.0 - 0.5 * extra, 4.0), 0)   # 史莱姆：常驻
			_add_creator(-1, maxf(7.0 - 0.5 * extra, 3.2), 2)   # 骷髅：常驻
			if progress >= 6:
				_add_creator(8, maxf(4.0 - 0.3 * extra, 2.2), 1)  # 再追一条地鼠线
