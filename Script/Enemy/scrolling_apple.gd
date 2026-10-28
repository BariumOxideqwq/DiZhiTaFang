extends "res://Script/Enemy/Enemy_model.gd"

# ---------------------------------------------------------------------------
# 滚动苹果（scrolling_apple）
#   * 基础速度略快于普通敌人
#   * 登场瞬间 +100% 速度，持续 1 秒，随后 1 秒内衰减回正常
#   * 斜着滚动：与竖直方向夹角 30°~60°，撞到场地左右边界就反弹并换一个新角度
#   * 贴图本身一直旋转（滚动感）
# ---------------------------------------------------------------------------

const FIELD_MIN_X := 70.0
const FIELD_MAX_X := 650.0
const ANGLE_MIN_DEG := 30.0
const ANGLE_MAX_DEG := 60.0
const SPIN_SPEED := 240.0      # 贴图自转速度（度/秒）
const BOOST_FACTOR := 2.5     # 登场加速：+100%
const BOOST_HOLD := 1.0        # 满加速持续 1 秒
const BOOST_DECAY := 1.0       # 之后 1 秒内衰减回 0

var dir_sign := 1.0            # 横向滚动方向（+1 向右 / -1 向左）
var angle_deg := 45.0          # 与竖直方向的夹角
var spawn_boost := 1.0         # 当前速度倍率（1 = 不加速）

var _spawn_time := 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	var g := maxi(GameManager.GameProgress, 1)
	Max_HP = 120.0 + float(g) * (10.0 + float(g - 1))
	HP = Max_HP
	speed = 600 + float(g) * (10.0 + float(g - 1))
	defense = 6.0 + 4.0 * float(g)
	damage = 1
	angle_deg = randf_range(ANGLE_MIN_DEG, ANGLE_MAX_DEG)
	dir_sign = 1.0 if randf() < 0.5 else -1.0
	_set_Label()


func _physics_process(delta: float) -> void:
	_spawn_time += delta
	spawn_boost = current_boost()
	# 贴图一直转（方向跟着滚动方向）
	if _sprite != null:
		_sprite.rotation += deg_to_rad(SPIN_SPEED) * delta * dir_sign
	_move(delta)


# 登场加速：0~1 秒满加速，1~2 秒衰减，之后恢复正常
func current_boost() -> float:
	if _spawn_time <= BOOST_HOLD:
		return BOOST_FACTOR
	var t := (_spawn_time - BOOST_HOLD) / BOOST_DECAY
	if t >= 1.0:
		return 1.0
	return lerpf(BOOST_FACTOR, 1.0, t)


func _move(delta: float) -> void:
	var factor := slow_down_rate * spawn_boost
	if _ally_target != null and is_instance_valid(_ally_target):
		factor *= ALLY_ENGAGE_SLOW
	var rad := deg_to_rad(angle_deg)
	var dir := Vector2(sin(rad) * dir_sign, cos(rad))
	velocity = dir * speed * 10.0 * delta * factor
	move_and_slide()
	_bounce_if_needed()
	_detect_self()


# 撞到左右边界：反弹并换一个新角度（30°~60°）
func _bounce_if_needed() -> void:
	var x := global_position.x
	if x > FIELD_MIN_X and x < FIELD_MAX_X:
		return
	dir_sign = -dir_sign
	angle_deg = randf_range(ANGLE_MIN_DEG, ANGLE_MAX_DEG)
	global_position.x = clampf(x, FIELD_MIN_X + 1.0, FIELD_MAX_X - 1.0)
	Audio.play("hit", -22.0)


func _Damage(amount: float) -> void:
	HP -= _mitigate(amount)
	HP = snappedf(HP, 0.01)
	_damage_effect()
	if HP <= 0.0:
		_die()
		return
	_set_Label()


func _Add_Exp() -> void:
	GameManager._Change_Exp(Max_HP / 20.0)
