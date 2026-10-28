extends Node

# ---------------------------------------------------------------------------
# 全局游戏管理器（Autoload: GameManager）
# 负责：单局状态与重置、奖励池与奖励结算、经验/波次、结算与最高记录存档
# ---------------------------------------------------------------------------

signal change_target_pos(pos: Vector2)
signal change_Exp
signal Exp_reward
signal Damage_Wall
signal GameProgress_forward(progress)
signal Heal_and_enhance_by_summoner
signal reward_UP(type: int)
signal _Add_Reward
signal enemy_killed(pos: Vector2)
signal game_over(stats: Dictionary)

const WALL_MAX_HEALTH := 10
const REWARD_MAX_LEVEL := 3
const SAVE_PATH := "user://save.cfg"

# ---------------------------------------------------------------------------
# BOSS 与滚动苹果
#   BOSS：9 级后按时间间隔刷新，间隔随进度缩短（有下限），场上同时只能有一只，
#         出场时从 BOSS_SCENES 里随机挑一只。
#   苹果：6 级后少量出现、10 级后大量出现（间隔见 apple_interval()）。
# ---------------------------------------------------------------------------
const BOSS_UNLOCK_LEVEL := 9
const BOSS_INTERVAL_BASE := 80.0     # 基础间隔（秒）
const BOSS_INTERVAL_STEP := 7.0      # 每点进度缩短多少秒
const BOSS_INTERVAL_MIN := 42.0      # 间隔下限（不会太快）
const BOSS_SCENES := [preload("res://Scene/Enemy/boss_slime_king.tscn")]

const APPLE = preload("res://Scene/Enemy/scrolling_apple.tscn")
const APPLE_MIN_LEVEL := 6           # 6 级后少量出现
const APPLE_DENSE_LEVEL := 10        # 10 级后大量出现
const APPLE_INTERVAL_SPARSE := 5.0
const APPLE_INTERVAL_DENSE := 1.6

const SLIME = preload("uid://dsius4s52bn05")
const MOLE = preload("uid://bxb7lmgyhnjq")
const KULOU = preload("uid://dpa6enra6k5r1")

const ARCHER = preload("uid://bvom1mu118qet")
const MAGICIAN = preload("uid://dtfl3ya8p8suk")
const SUMMONER = preload("uid://rb1dxn2su676")

const SUMMONING_CRACK = preload("uid://cg3ij86pwh0v4")
const SUMMON_MINION = preload("res://Scene/Character/weapon/summon_minion.tscn")
const KNIFE_WEAPON = preload("res://Resource/Instance/weapon_primordial_knife.tres")
const REWARD_PANEL = preload("uid://bxxkbjxtoc6av")

var Reward_Asset_All = preload("uid://fedevop0l3cx")

const BATTLE_SCENE_PATH = "uid://xhdi7ngj7j0e"
const CHOSING_CHARACTER_PATH = "uid://7kkk204rx2hf"
const START_SCENE_PATH = "uid://l04o6k4a24wp"

# 奖励池按「阶段」组织：以后新增阶段只要在这里补一行，
# 再用 _add_reward(角色, 阶段号) 把该阶段的新奖励追加进池子即可。
const REWARD_STAGES := {
	0: {  # 弓箭手
		1: [0, 1, 2, 3, 4, 5, 6, 7, 21, 29],
		2: [19, 30],  # 第一阶段满了（Lv9）之后解锁：淬锋之矢、鹰眼
	},
	1: {  # 法师
		1: [0, 8, 9, 10, 11, 12, 13, 21, 29],
		2: [31],  # Lv9 之后解锁：魔力解构
	},
	2: {  # 召唤师
		1: [0, 14, 15, 16, 17, 18, 20, 21, 29],
		2: [32, 33],  # Lv9 之后解锁：解离恶咒、解脱恩赐
	},
}

var Wall_Health := WALL_MAX_HEALTH
var Wall_Max := WALL_MAX_HEALTH
var Character_option := 2

var GameProgress := 0
var Enemy_Arr = [SLIME, MOLE, KULOU]

var Exp_max := 10.0
var Exp_cur := 0.0
var level := 0

var reward_finished := true
var Rewards_pool: Array = []
var reward_times := 0
var reward_stage_2_added := false
var _reward_loop_active := false

var _boss_timer := 0.0   # BOSS 刷新计时（场上有 BOSS 时暂停）
var _apple_timer := 0.0  # 滚动苹果刷新计时

var Enemies_creator_creator
var Reward_Creator
var Bow
var Magic_Cricle
var Summoner

# --- 单局统计与最高记录 ---
var in_run := false
var is_game_over := false
var tutorial_enabled := true   # 开始界面的「游戏引导」开关
var tutorial_active := false   # 本局正在走引导（期间城墙免伤）
var run_time := 0.0
var kill_count := 0

var best_time := 0.0
var best_level := 0
var best_wave := 0
var best_kills := 0

# --- 技能状态（0 表示未解锁）---
var summon_attack_interval := 0.5   # 20 提升召唤物攻速（攻击间隔，秒）
var summon_crack_level := 0         # 15 此岸渡蚀
var summon_proliferate_level := 0   # 16 溶原增殖
var summon_heal_level := 0          # 17 行炁淬锋
var summon_hallucination_level := 0 # 18 负向幻觉
var archer_bleed_level := 0         # 19 淬锋之矢
var summon_buff_duration := 5.0

# 人物穿透：抵消怪物防御带来的伤害减免（破甲奖励 29）
var penetration := 0.0
# 鹰眼（30）：百分比穿透，最高 50%
var penetration_pct := 0.0
# 法师 31 魔力解构 / 召唤师 32 解离恶咒 / 33 解脱恩赐
var arcane_level := 0
var totem_curse_level := 0
var totem_blessing_level := 0

# --- 武器状态（21–28）---
var weapon_info: Resource
var weapon_node: Node2D
var weapon_owned := false
var weapon_ratio_bonus := 0.0   # 22 利刃：追加飞刀倍率
var weapon_interval_mult := 1.0
var weapon_maxhp_pct_level := 0
var weapon_echo_level := 0
var weapon_archer_sync := false
var weapon_magician_fire := false
var weapon_summoner_burial := false

# ---------------------------------------------------------------------------
# 统一伤害体系：所有技能/武器伤害都从「角色攻击力」派生，不再各自维护基础值。
#   技能伤害 = 角色攻击力 × 倍率（带成长项时按对应奖励的等级加）
#   调平衡：改下面的倍率表 + 各奖励提供的百分比即可。
# ---------------------------------------------------------------------------
const CLASS_BASE_DAMAGE := [20.0, 15.0, 10.0]  # 弓箭手 / 法师 / 召唤师
const DAMAGE_PER_LEVEL := 2.0                  # 每级给角色加的固定攻击力

const RATIO_ARROW := 1.0        # 弓箭普攻
const RATIO_KNIFE := 2.0        # 原初飞刀
const RATIO_MAGIC_BOLT := 1.0   # 法师普攻魔法弹
const RATIO_THUNDER := 3.0      # 雷电
const RATIO_FIRE := 2.0         # 火焰弹 / 炼狱火场
const RATIO_SNOW := 1.5         # 暴雪
const RATIO_WIND := 0.5         # 风卷（单发）
const RATIO_ARCANE := 3.0       # 奥术魔弹
const RATIO_CRACK := 1.2        # 此岸渡蚀
const RATIO_SUMMONER_MAIN := 0.5  # 主召唤物
const RATIO_MINION := 0.25      # 溶原增殖的临时单位
const RATIO_TOTEM := 0.5        # 解离恶咒图腾（每跳）
const RATIO_BLEED := 0.08       # 淬锋之矢（每跳每层）

const GROW_THUNDER := 0.75      # 对应奖励每升一级的倍率成长
const GROW_FIRE := 0.5
const GROW_SNOW := 0.3
const GROW_ARCANE := 1.0
const GROW_CRACK := 0.5
const GROW_MINION := 0.05
const GROW_TOTEM := 0.2

var damage_flat := 0.0          # 奖励给的固定攻击力
var damage_pct := 0.0           # 奖励给的百分比攻击力（1 = +100%）

const SUMMON_ATTACK_INTERVAL_BASE := 0.5
const SUMMON_ATTACK_INTERVAL_MIN := 0.18
const SUMMON_ATTACK_SPEED_STEP := 0.85  # 每次「提升攻速」把间隔乘 0.85


func _ready() -> void:
	connect("reward_UP", _reward_detect)
	connect("_Add_Reward", _receive_add_reward)
	connect("enemy_killed", _on_enemy_killed)
	load_record()


func _process(delta: float) -> void:
	if in_run and not is_game_over and not get_tree().paused:
		run_time += delta
	_tick_boss(delta)
	_tick_apple(delta)


# --- 场景与单局 -------------------------------------------------------------

func _change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)


func start_run(character_option: int) -> void:
	Character_option = character_option
	_reset_run()
	_add_reward(Character_option, 1)
	in_run = true
	Audio.play("click")
	_change_scene(BATTLE_SCENE_PATH)


func return_to_menu() -> void:
	_reset_run()
	in_run = false
	Audio.play("click")
	_change_scene(START_SCENE_PATH)


func _reset_run() -> void:
	Wall_Health = WALL_MAX_HEALTH
	Wall_Max = WALL_MAX_HEALTH
	GameProgress = 0
	Exp_max = 10
	Exp_cur = 0
	level = 0
	reward_times = 0
	reward_finished = true
	reward_stage_2_added = false
	_reward_loop_active = false
	Rewards_pool.clear()

	Bow = null
	Magic_Cricle = null
	Summoner = null
	Reward_Creator = null
	Enemies_creator_creator = null

	in_run = false
	is_game_over = false
	tutorial_active = false
	run_time = 0.0
	kill_count = 0
	_boss_timer = 0.0
	_apple_timer = 0.0

	# 统一伤害体系
	damage_flat = 0.0
	damage_pct = 0.0

	summon_attack_interval = SUMMON_ATTACK_INTERVAL_BASE
	summon_crack_level = 0
	summon_proliferate_level = 0
	summon_heal_level = 0
	summon_hallucination_level = 0
	archer_bleed_level = 0
	summon_buff_duration = 5.0
	penetration = 0.0
	penetration_pct = 0.0
	arcane_level = 0
	totem_curse_level = 0
	totem_blessing_level = 0

	weapon_info = null
	weapon_node = null
	weapon_owned = false
	weapon_ratio_bonus = 0.0
	weapon_interval_mult = 1.0
	weapon_maxhp_pct_level = 0
	weapon_echo_level = 0
	weapon_archer_sync = false
	weapon_magician_fire = false
	weapon_summoner_burial = false

	for info in Reward_Asset_All.reward_list:
		info.level = 0
	ParticleDirector.reset()
	get_tree().paused = false


# --- 城墙 -------------------------------------------------------------------

func _BeDamaged(damage: float) -> void:
	if is_game_over or tutorial_active:
		return
	Wall_Health -= int(damage)
	Wall_Health = maxi(Wall_Health, 0)
	emit_signal("Damage_Wall")
	Audio.play("hurt")
	if Wall_Health <= 0:
		_trigger_game_over()


func _heal_wall(amount: int) -> void:
	if amount <= 0:
		return
	Wall_Health = mini(Wall_Health + amount, Wall_Max)
	emit_signal("Damage_Wall")


# BOSS 击杀奖励：提高城墙血量上限（并顺带补上这部分耐久）
func _raise_wall_max(amount: int) -> void:
	if amount <= 0:
		return
	Wall_Max += amount
	Wall_Health = mini(Wall_Health + amount, Wall_Max)
	emit_signal("Damage_Wall")


# --- 经验与波次 -------------------------------------------------------------

func _Change_Exp(exp_num: float) -> void:
	if is_game_over:
		return
	Exp_cur += exp_num
	emit_signal("change_Exp")
	var leveled := false
	while Exp_cur >= Exp_max:
		Exp_cur -= Exp_max
		level += 1
		Exp_max += level * 10
		reward_times += 1
		leveled = true
		if level > 0 and level % 3 == 0:
			GameProgress += 1
			emit_signal("GameProgress_forward", GameProgress)
			Audio.play("wave")
		_check_reward_stage_unlock()
	emit_signal("change_Exp")
	if leveled:
		Audio.play("levelup")
	if reward_times > 0:
		_reward_creat()


func _check_reward_stage_unlock() -> void:
	# 第一阶段奖励池满级（Lv9）后，追加下一阶段的奖励
	if level >= 9 and not reward_stage_2_added:
		reward_stage_2_added = true
		_add_reward(Character_option, 2)


# --- BOSS -------------------------------------------------------------------

# BOSS 出现规则：
#   * 9 级后开始计时，之后按「时间间隔」刷新（不再按波次/等级台阶触发）
#   * 间隔由游戏进度决定：进度越高间隔越短，但有下限，不会太快
#   * 场上同时只能有一只 BOSS（有 BOSS 时计时暂停）
#   * 出场时从已登记的 BOSS 列表里随机挑一只
func _tick_boss(delta: float) -> void:
	if not in_run or is_game_over or tutorial_active:
		return
	if level < BOSS_UNLOCK_LEVEL:
		return
	if _boss_alive():
		return
	_boss_timer += delta
	if _boss_timer < boss_interval():
		return
	_boss_timer = 0.0
	_spawn_random_boss()


# 当前进度下的 BOSS 间隔（秒）
func boss_interval() -> float:
	return maxf(BOSS_INTERVAL_BASE - BOSS_INTERVAL_STEP * float(maxi(GameProgress, 1)), BOSS_INTERVAL_MIN)


func _boss_alive() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	return not tree.get_nodes_in_group("bosses").is_empty()


func _spawn_random_boss() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null or BOSS_SCENES.is_empty():
		return
	var boss_scene: PackedScene = BOSS_SCENES[randi_range(0, BOSS_SCENES.size() - 1)]
	var boss = boss_scene.instantiate()
	tree.current_scene.add_child(boss)
	boss.global_position = Vector2(360.0, -260.0)


# BOSS 死亡：在它周围炸出 3~5 只史莱姆
func _spawn_slime_children(pos: Vector2, count: int) -> void:
	if is_game_over or get_tree() == null or get_tree().current_scene == null:
		return
	var scene := get_tree().current_scene
	var total := maxi(count, 1)
	for i in total:
		var slime = SLIME.instantiate()
		scene.add_child(slime)
		var angle := TAU * float(i) / float(total)
		slime.global_position = pos + Vector2(cos(angle), sin(angle)) * 70.0


# --- 滚动苹果 ---------------------------------------------------------------

func _tick_apple(delta: float) -> void:
	if not in_run or is_game_over or tutorial_active:
		return
	if level < APPLE_MIN_LEVEL:
		return
	_apple_timer -= delta
	if _apple_timer > 0.0:
		return
	_apple_timer = apple_interval()
	_spawn_apple()


# 6 级后少量出现，10 级后大量出现
func apple_interval() -> float:
	return APPLE_INTERVAL_DENSE if level >= APPLE_DENSE_LEVEL else APPLE_INTERVAL_SPARSE


func _spawn_apple() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var apple = APPLE.instantiate()
	tree.current_scene.add_child(apple)
	apple.global_position = Vector2(randf_range(80.0, 500.0), -210.0 + randf_range(-5.0, 5.0))


func _reward_creat() -> void:
	if Reward_Creator == null:
		return
	if _reward_loop_active:
		return
	_reward_loop_active = true
	while reward_times > 0 and not is_game_over:
		if Reward_Creator == null:
			break
		var panel_created: bool = Reward_Creator._creat_reward()
		if not panel_created:
			reward_times = 0
			break
		_Pause_Game()
		await reward_UP
		reward_times -= 1
		await get_tree().create_timer(0.01).timeout
	reward_times = 0
	_reward_loop_active = false


# --- 奖励池 -----------------------------------------------------------------

func _receive_add_reward() -> void:
	_add_reward(Character_option, 1)


func _add_reward(type: int, stage: int = 1) -> void:
	if not REWARD_STAGES.has(type):
		return
	var stage_rewards: Dictionary = REWARD_STAGES[type]
	if not stage_rewards.has(stage):
		return
	Rewards_pool.append_array(stage_rewards[stage])


func reward_is_available(index: int) -> bool:
	if index < 0 or index >= Reward_Asset_All.reward_list.size():
		return false
	# 已经拿到武器后，不再刷“获得武器”的卡片
	if index == int(KNIFE_WEAPON.get("reward_acquire")) and weapon_owned:
		return false
	return Reward_Asset_All.reward_list[index].level < REWARD_MAX_LEVEL


func _consume_reward(index: int) -> void:
	# 一次性奖励（拿到武器、职业专属解锁）：直接标满，不再出现在池子里
	if index < 0 or index >= Reward_Asset_All.reward_list.size():
		return
	Reward_Asset_All.reward_list[index].level = REWARD_MAX_LEVEL


func _bump_reward_level(index: int) -> void:
	if index < 0 or index >= Reward_Asset_All.reward_list.size():
		return
	var info = Reward_Asset_All.reward_list[index]
	info.level = mini(info.level + 1, REWARD_MAX_LEVEL)


func _reward_detect(type: int) -> void:
	match type:
		0:
			_heal_wall(1)
			_bump_reward_level(0)
		1:
			# 弓箭手：提升攻击力（+20%/级，作用于所有伤害）
			damage_pct += 0.2
			_bump_reward_level(1)
		2:
			if Bow != null:
				Bow.shoot_speed += 10.0
			_bump_reward_level(2)
		3:
			if Bow != null:
				Bow._san_she_times += 2
			_bump_reward_level(3)
		4:
			if Bow != null:
				Bow.shoot_times += 1
			_bump_reward_level(4)
		5:
			if Bow != null:
				Bow.hp += 2
			_bump_reward_level(5)
		6:
			if Bow != null:
				if Bow.kill_line == 0:
					Bow.kill_line += 0.15
				else:
					Bow.kill_line += 0.05
			_bump_reward_level(6)
		7:
			if Bow != null:
				# 残殇：叠加「当前生命/已损失生命」的附加伤害
				if Bow.per == 0.0:
					Bow.per += 0.05
				else:
					Bow.per += 0.02
			_bump_reward_level(7)
		8:
			# 法师：提升攻击力（+20%/级，作用于所有伤害）
			damage_pct += 0.2
			_bump_reward_level(8)
		9:
			if Magic_Cricle != null:
				Magic_Cricle.attack_speed += 8.0
			_bump_reward_level(9)
		10:
			# 雷电：首次解锁，之后等级越高倍率越高（伤害由 dmg_thunder 派生）
			if Magic_Cricle != null and not Magic_Cricle.thunder_magic_unlock:
				Magic_Cricle.thunder_magic_unlock = true
			_bump_reward_level(10)
		11:
			if Magic_Cricle != null and not Magic_Cricle.fire_magic_unlock:
				Magic_Cricle.fire_magic_unlock = true
			_bump_reward_level(11)
		12:
			if Magic_Cricle != null and not Magic_Cricle.frozen_magic_unlock:
				Magic_Cricle.frozen_magic_unlock = true
			_bump_reward_level(12)
		13:
			if Magic_Cricle != null:
				if not Magic_Cricle.wind_magic_ulock:
					Magic_Cricle.wind_magic_ulock = true
				else:
					Magic_Cricle.wind_nums += 1
			_bump_reward_level(13)
		14:
			# 召唤师：提升攻击力（+30%/级）——主召唤物与临时单位都从它派生
			damage_pct += 0.3
			refresh_summons()
			_bump_reward_level(14)
		15:
			# 召唤师：此岸渡蚀（裂隙由 SummonerSkillManager 维护）
			summon_crack_level += 1
			_bump_reward_level(15)
		16:
			# 召唤师：溶原增殖（击杀后生成临时单位）
			summon_proliferate_level += 1
			_bump_reward_level(16)
		17:
			# 召唤师：行炁淬锋
			summon_heal_level += 1
			summon_buff_duration = 4.0 + float(summon_heal_level)
			_bump_reward_level(17)
		18:
			# 召唤师：负向幻觉
			summon_hallucination_level += 1
			_bump_reward_level(18)
		19:
			# 弓箭手：淬锋之矢（流血强度由 dmg_bleed 派生）
			archer_bleed_level += 1
			_bump_reward_level(19)
		20:
			# 召唤师：提升召唤物攻速（缩短攻击间隔）
			summon_attack_interval = maxf(
				summon_attack_interval * SUMMON_ATTACK_SPEED_STEP,
				SUMMON_ATTACK_INTERVAL_MIN
			)
			refresh_summons()
			_bump_reward_level(20)
		21:
			# 获得武器：原初飞刀
			acquire_weapon(KNIFE_WEAPON)
			_consume_reward(21)
		22:
			# 利刃：飞刀倍率 +0.2/级
			weapon_ratio_bonus += 0.2
			refresh_weapon()
			_bump_reward_level(22)
		23:
			weapon_interval_mult = maxf(weapon_interval_mult * 0.85, 0.2)
			refresh_weapon()
			_bump_reward_level(23)
		24:
			weapon_maxhp_pct_level += 1
			refresh_weapon()
			_bump_reward_level(24)
		25:
			weapon_echo_level += 1
			refresh_weapon()
			_bump_reward_level(25)
		26:
			weapon_archer_sync = true
			refresh_weapon()
			_consume_reward(26)
		27:
			weapon_magician_fire = true
			refresh_weapon()
			_consume_reward(27)
		28:
			weapon_summoner_burial = true
			refresh_weapon()
			_consume_reward(28)
		29:
			# 通用：破甲（穿透 +8，抵消防御减免）
			penetration += 8.0
			_bump_reward_level(29)
		30:
			# 弓箭手：鹰眼（百分比穿透 20% / 35% / 50%）
			var eye_level = Reward_Asset_All.reward_list[30].level
			penetration_pct = [0.2, 0.35, 0.5][mini(int(eye_level), 2)]
			_bump_reward_level(30)
		31:
			# 法师：魔力解构（魔法阵读取等级后周期性丢奥术魔弹）
			arcane_level += 1
			_bump_reward_level(31)
		32:
			# 召唤师：解离恶咒图腾
			totem_curse_level += 1
			_bump_reward_level(32)
		33:
			# 召唤师：解脱恩赐图腾
			totem_blessing_level += 1
			_bump_reward_level(33)
	Audio.play("reward")
	_Remove_Pause_Game()


# --- 召唤物 -----------------------------------------------------------------

func notify_enemy_killed(pos: Vector2) -> void:
	kill_count += 1
	enemy_killed.emit(pos)


func refresh_summons() -> void:
	for node in get_tree().get_nodes_in_group("summons"):
		if node.has_method("recalc_damage"):
			node.recalc_damage()
		if node.has_method("apply_attack_interval"):
			node.apply_attack_interval()


# --- 武器 -------------------------------------------------------------------

func acquire_weapon(info: Resource) -> void:
	if info == null or weapon_owned:
		return
	weapon_info = info
	weapon_owned = true
	# 武器节点挂在角色身上：既负责开火，也在角色身边显示出来
	var character := get_tree().get_first_node_in_group("character")
	var weapon_scene: PackedScene = info.get("scene")
	if character != null and weapon_scene != null:
		weapon_node = weapon_scene.instantiate()
		character.add_child(weapon_node)
		if weapon_node.has_method("refresh_stats"):
			weapon_node.refresh_stats()
	# 这条武器的升级 / 技能 / 职业专属奖励进入奖励池
	var upgrades: Array = info.get("reward_upgrades")
	var skills: Array = info.get("reward_skills")
	var extras: Dictionary = info.get("reward_class_extras")
	Rewards_pool.append_array(upgrades)
	Rewards_pool.append_array(skills)
	var extra := int(extras.get(Character_option, -1))
	if extra >= 0:
		Rewards_pool.append(extra)
	Audio.play("reward", -6.0)


func refresh_weapon() -> void:
	if weapon_node != null and is_instance_valid(weapon_node):
		if weapon_node.has_method("refresh_stats"):
			weapon_node.refresh_stats()


func weapon_max_hp_pct() -> float:
	# 原初之力：0 / 3% / 6% / 9%
	return 0.03 * float(weapon_maxhp_pct_level)


# --- 统一伤害：角色攻击力与各技能倍率 ---------------------------------------

# 角色攻击力（唯一的伤害基准）
func character_damage() -> float:
	var base: float = CLASS_BASE_DAMAGE[clampi(Character_option, 0, 2)]
	return (base + DAMAGE_PER_LEVEL * float(maxi(level - 1, 0))) * (1.0 + damage_pct) + damage_flat


func _reward_level_of(index: int) -> int:
	if index < 0 or index >= Reward_Asset_All.reward_list.size():
		return 0
	return int(Reward_Asset_All.reward_list[index].level)


# 倍率 → 实际伤害（growth / reward_index 用于“该技能每升一级提高倍率”）
func skill_damage(ratio: float, growth: float = 0.0, reward_index: int = -1) -> float:
	var mult := ratio
	if reward_index >= 0 and growth > 0.0:
		mult += growth * float(maxi(_reward_level_of(reward_index) - 1, 0))
	return character_damage() * mult


func dmg_arrow() -> float:
	return character_damage() * RATIO_ARROW


func dmg_knife() -> float:
	return character_damage() * (RATIO_KNIFE + weapon_ratio_bonus)


func dmg_magic_bolt() -> float:
	return character_damage() * RATIO_MAGIC_BOLT


func dmg_thunder() -> float:
	return skill_damage(RATIO_THUNDER, GROW_THUNDER, 10)


func dmg_fire() -> float:
	return skill_damage(RATIO_FIRE, GROW_FIRE, 11)


func dmg_snow() -> float:
	return skill_damage(RATIO_SNOW, GROW_SNOW, 12)


func dmg_wind() -> float:
	return character_damage() * RATIO_WIND


func dmg_arcane() -> float:
	return skill_damage(RATIO_ARCANE, GROW_ARCANE, 31)


func dmg_crack() -> float:
	return skill_damage(RATIO_CRACK, GROW_CRACK, 15)


func dmg_summoner_main() -> float:
	# 主召唤物：完全由召唤师攻击力派生
	return character_damage() * RATIO_SUMMONER_MAIN


func dmg_minion() -> float:
	# 击杀后生成的临时单位：同样只看召唤师攻击力
	return skill_damage(RATIO_MINION, GROW_MINION, 16)


func dmg_totem() -> float:
	return skill_damage(RATIO_TOTEM, GROW_TOTEM, 32)


func dmg_bleed() -> float:
	return character_damage() * RATIO_BLEED * float(maxi(archer_bleed_level, 1))


func _on_enemy_killed(pos: Vector2) -> void:
	if summon_proliferate_level <= 0 or is_game_over:
		return
	if get_tree().current_scene == null:
		return
	# 击杀可能发生在物理回调里，生成新 Area2D 必须延后到物理帧结束
	_spawn_minion.call_deferred(pos)


func _spawn_minion(pos: Vector2) -> void:
	if is_game_over or get_tree().current_scene == null:
		return
	# 超过上限时优先删掉剩余存活时间最少的临时单位，再补新的
	if get_tree().get_nodes_in_group("summon_minions").size() >= 99:
		_evict_weakest_minion()
	var minion = SUMMON_MINION.instantiate()
	get_tree().current_scene.add_child(minion)
	# 出生点自动错开，避免连续击杀时新单位全叠在同一个点上
	minion.global_position = _find_free_minion_spot(pos, minion.separation_radius, minion)
	var minion_hp := 70.0 + 20.0 * float(summon_proliferate_level - 1)
	var minion_life_time = 10+(10*float(summon_proliferate_level - 1)-5)
	# 伤害不再单独传：统一由 GameManager.dmg_minion() 派生
	minion.setup(minion_life_time, minion_hp)


func _evict_weakest_minion() -> void:
	# 剩余存活时间最少的那个（含 100 秒上限与燃血剩余血量的较小值）
	var weakest: Node2D = null
	var weakest_left := INF
	for minion in get_tree().get_nodes_in_group("summon_minions"):
		if not is_instance_valid(minion):
			continue
		var left: float = INF
		if minion.has_method("remaining_life"):
			left = minion.remaining_life()
		if left < weakest_left:
			weakest_left = left
			weakest = minion
	if weakest != null:
		weakest.queue_free()


func _find_free_minion_spot(origin: Vector2, spacing: float, self_node: Node2D) -> Vector2:
	var step := maxf(spacing, 60.0) * 1.05
	for attempt in 16:
		var radius := step * (1.0 + 0.35 * float(attempt))
		var angle := float(attempt) * 2.399963  # 黄金角，尽量均匀铺开
		var spot := origin + Vector2(cos(angle), sin(angle)) * radius
		spot.x = clampf(spot.x, 40.0, 680.0)
		spot.y = clampf(spot.y, -140.0, 1080.0)
		var blocked := false
		for other in get_tree().get_nodes_in_group("summon_minions"):
			if other == self_node or not is_instance_valid(other):
				continue
			if other.global_position.distance_to(spot) < spacing:
				blocked = true
				break
		if not blocked:
			return spot
	return origin


# --- 暂停 -------------------------------------------------------------------

func _Pause_Game() -> void:
	get_tree().paused = true


func _Remove_Pause_Game() -> void:
	get_tree().paused = false


# --- 结算与存档 -------------------------------------------------------------

func _trigger_game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	in_run = false
	var new_record := _update_record()
	Audio.play("gameover")
	get_tree().paused = true
	emit_signal("game_over", {
		"time": run_time,
		"level": level,
		"wave": GameProgress,
		"kills": kill_count,
		"new_record": new_record,
		"best_time": best_time,
		"best_level": best_level,
	})


func _update_record() -> bool:
	var new_record := false
	if run_time > best_time:
		best_time = run_time
		new_record = true
	if level > best_level:
		best_level = level
		new_record = true
	if GameProgress > best_wave:
		best_wave = GameProgress
		new_record = true
	if kill_count > best_kills:
		best_kills = kill_count
		new_record = true
	if new_record:
		save_record()
	return new_record


func _load_config() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	return config


func save_record() -> void:
	var config := _load_config()
	config.set_value("record", "best_time", best_time)
	config.set_value("record", "best_level", best_level)
	config.set_value("record", "best_wave", best_wave)
	config.set_value("record", "best_kills", best_kills)
	config.save(SAVE_PATH)


func load_record() -> void:
	var config := _load_config()
	best_time = config.get_value("record", "best_time", 0.0)
	best_level = config.get_value("record", "best_level", 0)
	best_wave = config.get_value("record", "best_wave", 0)
	best_kills = config.get_value("record", "best_kills", 0)
	tutorial_enabled = bool(config.get_value("settings", "tutorial", true))


func set_tutorial_enabled(value: bool) -> void:
	tutorial_enabled = value
	var config := _load_config()
	config.set_value("settings", "tutorial", value)
	config.save(SAVE_PATH)


func best_record_text() -> String:
	if best_time <= 0.0 and best_level <= 0 and best_kills <= 0:
		return "最高记录：暂无"
	return "最高记录：Lv %d · 存活 %s · 击杀 %d" % [best_level, format_time(best_time), best_kills]


func format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var minutes := floori(total / 60.0)
	return "%02d:%02d" % [minutes, total % 60]


# --- 瞄准 -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if is_game_over:
		return
	var target_pos: Vector2
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		target_pos = get_viewport().get_mouse_position()
		if target_pos.y > 1250.0:
			return
		change_target_pos.emit(target_pos)
	if event is InputEventScreenTouch and event.pressed:
		target_pos = event.position
		if target_pos.y > 1250.0:
			return
		change_target_pos.emit(target_pos)
