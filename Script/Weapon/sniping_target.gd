extends Node2D

# ---------------------------------------------------------------------------
# 狙击特效：
#   1. 从很远处淡入、滑到目标身旁
#   2. 在目标周围摇摆 0.2s
#   3. 锁定并跟随目标
#   4. 触发狙击伤害（斩杀类不吃防御减免）
#   5. 淡出并销毁
# 必须在 add_child 之前调用 setup()，否则 _ready 里拿不到目标。
# ---------------------------------------------------------------------------

const SLIDE_TIME := 0.22
const WOBBLE_TIME := 0.20
const LOCK_TIME := 0.12
const FADE_TIME := 0.18
const WOBBLE_STEP := 0.04
const WOBBLE_RANGE := 18.0
const START_OFFSET := Vector2(0.0, -1400.0)
const APPROACH_OFFSET := Vector2(0.0, -46.0)

var _target: Node2D
var _damage := 0.0
var _execute := false


func setup(target: Node2D, damage: float, execute: bool) -> void:
	_target = target
	_damage = damage
	_execute = execute


func _ready() -> void:
	z_index = 6
	modulate.a = 0.0
	scale = Vector2(2.2, 2.2)
	_play()


func _play() -> void:
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	var aim_pos: Vector2 = (_target as Node2D).global_position
	global_position = aim_pos + START_OFFSET

	# 1) 从远处滑近并淡入
	var slide := create_tween()
	slide.set_parallel(true)
	slide.tween_property(self, "global_position", aim_pos + APPROACH_OFFSET, SLIDE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	slide.tween_property(self, "modulate:a", 1.0, SLIDE_TIME)
	slide.tween_property(self, "scale", Vector2(0.9, 0.9), SLIDE_TIME)
	await slide.finished

	# 2) 围绕目标摇摆
	var wobble_left := WOBBLE_TIME
	while wobble_left > 0.0:
		if not is_instance_valid(_target):
			break
		global_position = (_target as Node2D).global_position + Vector2(
			randf_range(-WOBBLE_RANGE, WOBBLE_RANGE),
			randf_range(-WOBBLE_RANGE, WOBBLE_RANGE)
		)
		await get_tree().create_timer(WOBBLE_STEP).timeout
		wobble_left -= WOBBLE_STEP

	# 3) 锁定并跟随
	var lock_left := LOCK_TIME
	while lock_left > 0.0:
		if not is_instance_valid(_target):
			break
		global_position = (_target as Node2D).global_position
		await get_tree().process_frame
		lock_left -= get_process_delta_time()

	# 4) 触发狙击
	if is_instance_valid(_target):
		global_position = (_target as Node2D).global_position
		if _execute and _target.has_method("_execute"):
			_target._execute()
		elif _target.has_method("_damage_percent_hp"):
			# 非斩杀段按最大生命百分比结算（BOSS 会吃比例抗性）
			_target._damage_percent_hp(_damage)
		elif _target.has_method("_Damage"):
			_target._Damage(_damage)

	# 5) 淡出
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	fade.tween_property(self, "scale", Vector2(1.35, 1.35), FADE_TIME)
	await fade.finished
	queue_free()
