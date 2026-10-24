extends Control

# ---------------------------------------------------------------------------
# 新手引导：开局分步提示「基本操作 → 系统介绍」。
#   * 引导期间整局暂停（get_tree().paused = true）：不会刷怪、不会掉城墙
#   * 第 1 步：在屏幕上点一下 → 武器转向 + 进入下一步
#   * 第 2 步：按住底部小人左右拖动（引导面板用暂停态下的输入直接驱动角色）
#   * 第 3–5 步：系统介绍，点「下一步」继续
#   * 任何一步都能「跳过引导」；停留超过 12 秒也会自动放行
# 结束（或跳过）后解除暂停。
# ---------------------------------------------------------------------------

const STEPS := [
	{"title": "1 / 5　基本操作 · 瞄准", "body": "点击或触摸屏幕上方，武器会朝那个方向攻击。", "action": "aim"},
	{"title": "2 / 5　基本操作 · 移动", "body": "按住底部的小人左右拖动，可以调整站位。", "action": "drag"},
	{"title": "3 / 5　系统 · 城墙", "body": "怪物走到城墙会扣耐久，耐久归零本局结束。", "action": "read"},
	{"title": "4 / 5　系统 · 经验与奖励", "body": "击杀怪物获得经验；升级后三选一，奖励能让本局越打越强。", "action": "read"},
	{"title": "5 / 5　系统 · 武器", "body": "抽到武器后，它会挂在角色身边，并解锁武器专属奖励。", "action": "read"},
]

var step_index := 0

var _pulse := 0.0
var _drag_start_x := 0.0
var _drag_offset_x := 0.0
var _dragging := false
var _drag_moved := false
var _touch_index := -1
var _started := false
var _pause_button: CanvasItem


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if not GameManager.tutorial_enabled:
		return
	_begin.call_deferred()


func _begin() -> void:
	if not GameManager.tutorial_enabled or GameManager.is_game_over:
		return
	_started = true
	GameManager.tutorial_active = true
	get_tree().paused = true
	visible = true
	# 引导期间本来就暂停，暂停按钮没有意义，先藏起来避免和引导按钮重叠
	_pause_button = get_tree().current_scene.get_node_or_null("UI/PauseButton") as CanvasItem
	if _pause_button != null:
		_pause_button.visible = false
	var character = get_tree().get_first_node_in_group("character")
	if character is Node2D:
		_drag_start_x = (character as Node2D).global_position.x
	_show_step(0)


func _show_step(index: int) -> void:
	step_index = index
	_dragging = false
	_drag_moved = false
	_touch_index = -1
	$Banner/Title.text = String(STEPS[index]["title"])
	$Banner/Body.text = String(STEPS[index]["body"])
	$Banner/NextButton.visible = String(STEPS[index]["action"]) == "read"
	queue_redraw()


func _process(delta: float) -> void:
	if not _started:
		return
	_pulse += delta
	queue_redraw()

	if String(STEPS[step_index]["action"]) == "drag":
		var character = get_tree().get_first_node_in_group("character")
		if character is Node2D and absf((character as Node2D).global_position.x - _drag_start_x) > 20.0:
			_drag_moved = true
		# 等玩家松手再进入下一步，拖动过程不会被中途打断
		if _drag_moved and not _dragging:
			_next_step()


func _next_step() -> void:
	if not _started:
		return
	if step_index + 1 >= STEPS.size():
		_finish()
	else:
		_show_step(step_index + 1)


func _finish() -> void:
	if not _started:
		return
	_started = false
	_dragging = false
	visible = false
	if _pause_button != null and is_instance_valid(_pause_button):
		_pause_button.visible = true
	GameManager.tutorial_active = false
	get_tree().paused = false
	Audio.play("levelup", -8.0)


func _on_next_button_pressed() -> void:
	Audio.play("click")
	_next_step()


func _on_skip_button_pressed() -> void:
	Audio.play("click")
	_finish()


# --- 暂停态下的教学输入 -----------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _started:
		return
	var action := String(STEPS[step_index]["action"])
	if action == "aim":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			GameManager.change_target_pos.emit(_screen_to_world(event.position))
			_next_step()
		elif event is InputEventScreenTouch and event.pressed:
			GameManager.change_target_pos.emit(_screen_to_world(event.position))
			_next_step()
		return
	if action != "drag":
		return

	var character = get_tree().get_first_node_in_group("character")
	if not (character is Node2D):
		return
	var node := character as Node2D

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var world := _screen_to_world(event.position)
			if node._point_on_me(world):
				_dragging = true
				_drag_offset_x = world.x - node.global_position.x
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_move_character(_screen_to_world(event.position).x)
	elif event is InputEventScreenTouch:
		if event.pressed:
			var world := _screen_to_world(event.position)
			if _touch_index == -1 and node._point_on_me(world):
				_touch_index = event.index
				_dragging = true
				_drag_offset_x = world.x - node.global_position.x
		elif event.index == _touch_index:
			_touch_index = -1
			_dragging = false
	elif event is InputEventScreenDrag and _dragging and event.index == _touch_index:
		_move_character(_screen_to_world(event.position).x)


func _move_character(target_x: float) -> void:
	var character = get_tree().get_first_node_in_group("character")
	if not (character is Node2D):
		return
	var node := character as Node2D
	var new_x := clampf(target_x - _drag_offset_x, float(node.get("min_x")), float(node.get("max_x")))
	node.global_position = Vector2(new_x, float(node.get("_original_y")))


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


# --- 屏幕上的指示圈 / 箭头 ---------------------------------------------------

func _draw() -> void:
	if not _started:
		return
	var alpha := 0.45 + 0.45 * (0.5 + 0.5 * sin(_pulse * 4.0))
	var action := String(STEPS[step_index]["action"])
	if action == "aim":
		var color := Color(1.0, 0.92, 0.45, alpha)
		var center := Vector2(360.0, 470.0)
		draw_arc(center, 78.0, 0.0, TAU, 64, color, 6.0)
		draw_arc(center, 42.0, 0.0, TAU, 48, color, 4.0)
		draw_line(center + Vector2(0.0, -140.0), center + Vector2(0.0, -86.0), color, 6.0)
	elif action == "drag":
		var character = get_tree().get_first_node_in_group("character")
		if character is Node2D:
			var color := Color(0.45, 1.0, 0.6, alpha)
			var pos: Vector2 = (character as Node2D).get_global_transform_with_canvas().origin
			draw_arc(pos, 105.0, 0.0, TAU, 64, color, 6.0)
			draw_line(pos + Vector2(-165.0, 0.0), pos + Vector2(-100.0, 0.0), color, 6.0)
			draw_line(pos + Vector2(100.0, 0.0), pos + Vector2(165.0, 0.0), color, 6.0)
			draw_line(pos + Vector2(-165.0, 0.0), pos + Vector2(-140.0, -14.0), color, 6.0)
			draw_line(pos + Vector2(-165.0, 0.0), pos + Vector2(-140.0, 14.0), color, 6.0)
			draw_line(pos + Vector2(165.0, 0.0), pos + Vector2(140.0, -14.0), color, 6.0)
			draw_line(pos + Vector2(165.0, 0.0), pos + Vector2(140.0, 14.0), color, 6.0)
