extends Control

# 奖励面板：从池子里抽最多 3 张「还没满级」的卡片。
# 抽不到任何卡片时自己销毁，让上层跳过这次奖励（不会把游戏卡在暂停状态）。

const REWARD_OPTION = preload("uid://dc16tue6wqx02")
const CARD_HEIGHT := 280.0

var option_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	GameManager.connect("reward_UP", _reward_up)
	GameManager.reward_finished = false

	var pool: Array = []
	for index in GameManager.Rewards_pool:
		if not pool.has(index) and GameManager.reward_is_available(index):
			pool.append(index)

	var shown := 0
	while shown < 3 and not pool.is_empty():
		var r := randi_range(0, pool.size() - 1)
		var index: int = pool[r]
		pool.remove_at(r)
		var info = GameManager.Reward_Asset_All.reward_list[index]
		var option = REWARD_OPTION.instantiate()
		option.global_position = Vector2(150.0, 81.0 + float(shown) * CARD_HEIGHT)
		$Panel.add_child(option)
		option._inital_Self(info.name, info.context, index)
		shown += 1

	option_count = shown
	if shown == 0:
		queue_free()


func _reward_up(_type: int) -> void:
	queue_free()
