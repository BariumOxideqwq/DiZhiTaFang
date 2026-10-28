extends Node

# ---------------------------------------------------------------------------
# 全局粒子调度器（Autoload: ParticleDirector）
#
# 目的：粒子对象越多越容易卡，所以统一在这里统计“当前有多少个粒子对象在播”，
# 并发越多，单个对象拿到的强度越低（粒子数/透明度一起降）。
#
# 名额上限会跟着帧率动态调整：
#   * 帧率健康（> 55）→ 上限逐步放宽到 96
#   * 帧率吃紧（< 40）→ 上限逐步收紧到 18
#   * 中间区间保持不变，避免数值来回抖
#
# 用法：
#   var strength := ParticleDirector.acquire()   # 0 表示被拒绝（已达上限）
#   if strength > 0.0: ...播放... ; ParticleDirector.release()
# 治疗粒子直接调 spawn_heal()，它会自己处理计数。
# ---------------------------------------------------------------------------

const BASE_PARTICLES := 16      # 满强度时的粒子数
const MIN_PARTICLES := 2        # 最弱时也保留的粒子数
const SOFT_CAP := 6.0           # 超过这个并发数后明显衰减
const MIN_STRENGTH := 0.12      # 强度下限

const MAX_ACTIVE := 60          # 基准上限
const MAX_ACTIVE_RELAXED := 96  # 帧率很好时放宽到这里
const MAX_ACTIVE_MIN := 18      # 帧率很差时收紧到这里
const FPS_GOOD := 55.0
const FPS_BAD := 40.0
const FPS_SAMPLE_INTERVAL := 0.5

const HEAL_SCENE_PATH := "res://Scene/Particle/heal_burst.tscn"

var _active := 0
var _cap := MAX_ACTIVE
var _fps_timer := 0.0
var _heal_scene: PackedScene


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_fps_timer += delta
	if _fps_timer < FPS_SAMPLE_INTERVAL:
		return
	_fps_timer = 0.0
	_apply_fps_sample(float(Engine.get_frames_per_second()))


# 按当前帧率调名额上限（抽成独立函数，方便测试直接喂样本）
func _apply_fps_sample(fps: float) -> void:
	if fps <= 0.0:
		return
	if fps < FPS_BAD:
		_cap = maxi(int(float(_cap) * 0.75), MAX_ACTIVE_MIN)
	elif fps > FPS_GOOD:
		_cap = mini(_cap + 8, MAX_ACTIVE_RELAXED)


func max_active() -> int:
	return _cap


func active_count() -> int:
	return _active


# 强度：1 个对象满强度，并发越多越低
func strength() -> float:
	if _active <= 1:
		return 1.0
	return clampf(1.0 / (1.0 + float(_active - 1) / SOFT_CAP), MIN_STRENGTH, 1.0)


# 申请一个粒子对象名额；返回该对象应使用的强度（0 = 被拒绝）
func acquire() -> float:
	if _active >= _cap:
		return 0.0
	_active += 1
	return strength()


func release() -> void:
	_active = maxi(_active - 1, 0)


func particle_count(object_strength: float) -> int:
	if object_strength <= 0.0:
		return 0
	return maxi(MIN_PARTICLES, int(round(float(BASE_PARTICLES) * object_strength)))


func reset() -> void:
	_active = 0
	_cap = MAX_ACTIVE
	_fps_timer = 0.0


func _get_heal_scene() -> PackedScene:
	# 延迟加载：heal_burst.gd 里要用 ParticleDirector，直接 preload 会形成循环依赖
	if _heal_scene == null:
		_heal_scene = load(HEAL_SCENE_PATH)
	return _heal_scene


# --- 具体特效 ---------------------------------------------------------------

func spawn_heal(parent: Node, pos: Vector2, target: Node2D = null) -> Node:
	return spawn_effect(_get_heal_scene(), parent, pos, target)


func spawn_effect(scene: PackedScene, parent: Node, pos: Vector2, target: Node2D = null) -> Node:
	if scene == null or parent == null:
		return null
	var object_strength := acquire()
	if object_strength <= 0.0:
		return null
	var effect = scene.instantiate()
	parent.add_child(effect)
	effect.global_position = pos
	if effect.has_method("setup"):
		effect.setup(object_strength, target)
	return effect
