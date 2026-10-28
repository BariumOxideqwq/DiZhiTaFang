extends Control

# 奖励面板：从池子里抽最多 3 张「还没满级」的卡片。
# 每张卡片右侧有一个「刷新」按钮，每张卡可以单独刷新一次（不消耗奖励次数）。
# 抽不到任何卡片时自己销毁，让上层跳过这次奖励（不会把游戏卡在暂停状态）。

const REWARD_OPTION = preload("uid://dc16tue6wqx02")
const CARD_HEIGHT := 280.0
const CARD_X := 150.0
const CARD_WIDTH := 460.0
const REFRESH_OFFSET_X := 12.0
const REFRESH_WIDTH := 96.0

var option_count := 0

var _pool: Array = []
var _shown_ids: Array[int] = []
var _cards: Array = []
var _refresh_buttons: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	GameManager.connect("reward_UP", _reward_up)
	GameManager.reward_finished = false

	for index in GameManager.Rewards_pool:
		if not _pool.has(index) and GameManager.reward_is_available(index):
			_pool.append(index)

	var shown := 0
	while shown < 3:
		var index := _draw_and_remove()
		if index < 0:
			break
		_add_card(shown, index)
		shown += 1

	option_count = shown
	if shown == 0:
		queue_free()


func _draw_and_remove() -> int:
	if _pool.is_empty():
		return -1
	var r := randi_range(0, _pool.size() - 1)
	var index: int = _pool[r]
	_pool.remove_at(r)
	return index


func _add_card(slot: int, index: int) -> void:
	var y := 81.0 + float(slot) * CARD_HEIGHT
	var info = GameManager.Reward_Asset_All.reward_list[index]
	var option = REWARD_OPTION.instantiate()
	option.position = Vector2(CARD_X, y)
	$Panel.add_child(option)
	option._inital_Self(info.name, info.context, index)

	var button := Button.new()
	button.text = "刷新"
	button.add_theme_font_size_override("font_size", 20)
	button.position = Vector2(CARD_X + CARD_WIDTH + REFRESH_OFFSET_X, y + 18.0)
	button.custom_minimum_size = Vector2(REFRESH_WIDTH, 48.0)
	button.size = Vector2(REFRESH_WIDTH, 48.0)
	button.pressed.connect(_on_refresh_pressed.bind(slot))
	$Panel.add_child(button)

	_shown_ids.append(index)
	_cards.append(option)
	_refresh_buttons.append(button)


func _on_refresh_pressed(slot: int) -> void:
	if slot < 0 or slot >= _refresh_buttons.size():
		return
	var button: Button = _refresh_buttons[slot]
	if button.disabled:
		return
	var card = _cards[slot]
	var old_id: int = card.reward_context
	var candidates: Array = []
	for index in _pool:
		if not _shown_ids.has(index) and GameManager.reward_is_available(index):
			candidates.append(index)
	if candidates.is_empty():
		return
	Audio.play("click")
	var new_id: int = candidates[randi_range(0, candidates.size() - 1)]
	_pool.erase(new_id)
	_pool.append(old_id)
	_shown_ids.erase(old_id)
	_shown_ids.append(new_id)
	var info = GameManager.Reward_Asset_All.reward_list[new_id]
	card._inital_Self(info.name, info.context, new_id)
	button.disabled = true
	button.text = "已刷新"


func _reward_up(_type: int) -> void:
	queue_free()
