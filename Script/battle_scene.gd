extends Node2D

func _ready() -> void:
	GameManager.Reward_Creator = $Reward_Creator
	GameManager.Enemies_creator_creator = $Enemies_creator_creator
