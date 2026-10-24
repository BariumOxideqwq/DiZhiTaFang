@abstract extends CharacterBody2D

# ---------------------------------------------------------------------------
# 角色基类：三个角色共用的拖拽逻辑都在这里。
# 拖拽修复点：
#   1. 触摸也必须先按在角色身上才开始拖动（不再整屏乱滑都能带走角色）；
#   2. 命中判定用物理点查询（会算上 CollisionShape2D 自身的偏移），
#      和人物实际位置对得上；
#   3. 触摸坐标统一换算成世界坐标，摄像机有偏移也不会飘。
# ---------------------------------------------------------------------------

var charactername

var level

var attack_power_physics
var attack_power_magic
var attack_speed

var skill_arr

var weapon

@export var min_x := 50.0
@export var max_x := 670.0

var is_dragging := false
var _drag_offset_x := 0.0
var _original_y := 0.0
var _touch_index := -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		_original_y = global_position.y
		add_to_group("character")


func _input(event: InputEvent) -> void:
	if get_tree().paused or GameManager.is_game_over:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var world_pos := _screen_to_world(event.position)
			if _point_on_me(world_pos):
				_begin_drag(world_pos)
		else:
			is_dragging = false
	elif event is InputEventMouseMotion and is_dragging:
		_move_to_x(_screen_to_world(event.position).x)
	elif event is InputEventScreenTouch:
		var world_pos := _screen_to_world(event.position)
		if event.pressed:
			if _touch_index == -1 and _point_on_me(world_pos):
				_touch_index = event.index
				_begin_drag(world_pos)
		elif event.index == _touch_index:
			_touch_index = -1
			is_dragging = false
	elif event is InputEventScreenDrag and is_dragging and event.index == _touch_index:
		_move_to_x(_screen_to_world(event.position).x)


func _begin_drag(world_pos: Vector2) -> void:
	is_dragging = true
	_drag_offset_x = world_pos.x - global_position.x


func _move_to_x(target_x: float) -> void:
	global_position = Vector2(clampf(target_x - _drag_offset_x, min_x, max_x), _original_y)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _point_on_me(world_pos: Vector2) -> bool:
	# 优先用「看到的人物范围」判定：碰撞盒的偏移在不同角色上并不一致，
	# 直接按碰撞盒判定会点不到人物上半身。
	if _visual_rect().has_point(world_pos):
		return true
	# 兜底：用物理点查询（会把 CollisionShape2D 自身的偏移算进去）
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = collision_layer
	for hit in space.intersect_point(query, 8):
		if hit.get("collider") == self:
			return true
	return false


func _visual_rect() -> Rect2:
	var bounds := Rect2()
	var found := false
	for child in get_children():
		if not (child is Sprite2D) or not child.visible:
			continue
		var local_rect: Rect2 = child.get_rect()
		if local_rect.size == Vector2.ZERO:
			continue
		var corners := [
			local_rect.position,
			Vector2(local_rect.end.x, local_rect.position.y),
			local_rect.end,
			Vector2(local_rect.position.x, local_rect.end.y),
		]
		var top_left := Vector2(INF, INF)
		var bottom_right := Vector2(-INF, -INF)
		for corner in corners:
			var global_corner: Vector2 = child.to_global(corner)
			top_left = top_left.min(global_corner)
			bottom_right = bottom_right.max(global_corner)
		var rect := Rect2(top_left, bottom_right - top_left)
		bounds = rect if not found else bounds.merge(rect)
		found = true
	if not found:
		return Rect2()
	return bounds.grow(12.0)
