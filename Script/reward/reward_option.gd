extends Button

# 奖励卡片：名称 + 说明始终显示在卡片里，手机上没有 hover 也能看清效果

var reward_context: int


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _inital_Self(nm: String, contxt: String, r_c: int) -> void:
	$Content/Name.text = nm
	$Content/Desc.text = contxt
	reward_context = r_c


func _on_button_down() -> void:
	Audio.play("click")
	GameManager.emit_signal("reward_UP", reward_context)


func _on_mouse_entered() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.03, 1.03), 0.08)


func _on_mouse_exited() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
