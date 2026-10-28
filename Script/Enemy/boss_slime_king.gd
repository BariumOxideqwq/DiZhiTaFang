extends "res://Script/Enemy/Enemy_model.gd"

# ---------------------------------------------------------------------------
# BOSS：史莱姆王（第一只 boss，暂无额外机制）
#   * 表现：大号史莱姆 + 皇冠
#   * 血条用 ProgressBar 显示，不显示数字
#   * 对城墙伤害 5 点（普通怪 1~2 点）
#   * 死亡：大量经验 + 提升城墙血量上限 + 在身边炸出 3~5 只史莱姆
#   * 血量 / 防御 / 移速随波次（GameProgress）成长
# ---------------------------------------------------------------------------

const BOSS_WALL_DAMAGE := 5
const CHILD_MIN := 3
const CHILD_MAX := 5
const WALL_MAX_UP := 1

# BOSS 专用减伤（普通怪没有这两条）
const BOSS_PERCENT_RESIST := 0.75      # 比例伤害只吃 25%
const BOSS_EXECUTE_DAMAGE_PCT := 0.10  # 斩杀对 BOSS 只有 10% 效果：一记 10% 最大生命的伤害

@onready var _hp_bar: ProgressBar = $HP_Bar


func _enter_tree() -> void:
	super()
	# 场上同时只能有一只 BOSS：GameManager._boss_alive() 靠这个分组判断
	add_to_group("bosses")


func _ready() -> void:
	var g := maxi(GameManager.GameProgress, 1)
	Max_HP = 1000.0 + 450.0 * float(g)
	HP = Max_HP
	speed = 90.0 + 6.0 * float(g)
	defense = 35.0 + 12.0 * float(g)
	damage = BOSS_WALL_DAMAGE
	percent_resist = BOSS_PERCENT_RESIST
	execute_damage_pct = BOSS_EXECUTE_DAMAGE_PCT
	_update_hp_bar()


func _physics_process(delta: float) -> void:
	_move(delta)
	if not $AnimationPlayer.is_playing():
		$AnimationPlayer.play("walk")


func _move(delta: float) -> void:
	_walk(delta)


func _Damage(amount: float) -> void:
	HP -= _mitigate(amount)
	HP = snappedf(HP, 0.01)
	_damage_effect()
	if HP <= 0.0:
		_die()
		return
	_update_hp_bar()


func _set_Label() -> void:
	# BOSS 不显示血量数字，只更新进度条
	_update_hp_bar()


func _update_hp_bar() -> void:
	if _hp_bar == null:
		return
	_hp_bar.max_value = maxf(Max_HP, 1.0)
	_hp_bar.value = maxf(HP, 0.0)


func _die() -> void:
	GameManager.notify_enemy_killed(global_position)
	_Add_Exp()
	GameManager._raise_wall_max(WALL_MAX_UP)
	# _die 常常在物理回调里被调用，生成 CharacterBody2D 必须延后到帧末
	GameManager._spawn_slime_children.call_deferred(global_position, randi_range(CHILD_MIN, CHILD_MAX))
	queue_free()


func _Add_Exp() -> void:
	# 大量经验奖励
	GameManager._Change_Exp(Max_HP / 3.0)
