extends "res://Script/Character/Character_model.gd"

# 召唤师：召唤物自动攻击最近的敌人；技能由子节点 SummonerSkillManager 维护

@onready var _detect_area: Area2D = $Summoner_detect_Area
@onready var _summon: Area2D = $summing_one


func _ready() -> void:
	add_to_group("summoner")
	GameManager.Summoner = self
	_summon._setTarget(Vector2(360.0, 1500.0))


func _physics_process(_delta: float) -> void:
	_update_target()


func _update_target() -> void:
	var bodies := _detect_area.get_overlapping_bodies()
	if bodies.is_empty():
		_summon._setTarget(Vector2(360.0, 1500.0))
		return
	var closest: Node2D = null
	var min_dist := INF
	for body in bodies:
		var dist: float = global_position.distance_squared_to(body.global_position)
		if dist < min_dist:
			min_dist = dist
			closest = body
	if closest == null:
		_summon._setTarget(Vector2(360.0, 1500.0))
	else:
		_summon._setTarget(closest.global_position)
