extends Node2D

# 治疗粒子爆发：在目标位置炸开一小簇绿色十字。
#   * 传了 target 就每帧贴着目标走（粒子跟随单位，不会留在原地）
#   * 目标中途死亡/销毁时停在最后位置，正常播完
#   * 用固定计时回收（不依赖 GPUParticles2D.finished，headless 下也能回收）

const LIFETIME := 0.55

var _released := false
var _target: Node2D

@onready var _particles: GPUParticles2D = $Particles


func setup(object_strength: float, target: Node2D = null) -> void:
	_target = target
	if _particles == null:
		return
	_particles.amount = ParticleDirector.particle_count(object_strength)
	_particles.modulate = Color(1.0, 1.0, 1.0, 0.5 + 0.5 * object_strength)
	_particles.emitting = true
	var timer := get_tree().create_timer(LIFETIME + 0.35)
	timer.timeout.connect(_finish)


func _process(_delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		global_position = _target.global_position


func _finish() -> void:
	if _released:
		return
	_released = true
	ParticleDirector.release()
	queue_free()


func _exit_tree() -> void:
	# 场景被提前切走/销毁时也要归还计数，避免全局计数泄漏
	if _released:
		return
	_released = true
	ParticleDirector.release()
