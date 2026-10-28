extends Node2D

# ---------------------------------------------------------------------------
# 冒烟测试：在真实项目里（带 Autoload）跑一遍本版新增/修复的逻辑。
# 运行：godot --headless --path . --quit-after 9000 tests/smoke_test.tscn
# 断言失败时以退出码 1 结束，方便接 CI。
# ---------------------------------------------------------------------------

var failures: Array[String] = []
var checks := 0
var battle: Node2D


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS  ", label)
	else:
		failures.append(label)
		print("FAIL  ", label)


func _run() -> void:
	GameManager.tutorial_enabled = false  # 主流程不弹引导，单独测
	await _test_archer_rewards()
	await _test_weapon_and_pause()
	await _test_magician_weapon()
	await _test_defense()
	await _test_reward_refresh()
	await _test_healing_particles()
	await _test_stage2_rewards()
	await _test_boss()
	await _test_apple()
	await _test_spawn_pressure()
	await _test_tutorial()
	await _test_reward_pool_guard()
	await _test_summoner_skills()
	await _test_damage_heal()
	await _test_game_over_and_record()

	print("======== %d checks, %d failed ========" % [checks, failures.size()])
	for failure in failures:
		print("  FAILED: ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)


# --- 工具 -------------------------------------------------------------------

func _make_battle(character: int) -> void:
	if battle != null and is_instance_valid(battle):
		get_tree().current_scene = null
		battle.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	GameManager._reset_run()
	GameManager.Character_option = character
	GameManager._add_reward(character, 1)
	var scene: PackedScene = load("uid://xhdi7ngj7j0e")
	battle = scene.instantiate()
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	await get_tree().process_frame
	await get_tree().process_frame


func _find_by_script_suffix(root: Node, suffix: String) -> Node:
	for child in root.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(suffix):
			return child
	return null


func _dismiss_reward_panel() -> void:
	if GameManager.Reward_Creator == null:
		return
	if GameManager.Reward_Creator.get_child_count() > 0:
		GameManager.emit_signal("reward_UP", -1)
		await get_tree().process_frame
	GameManager._Remove_Pause_Game()
	GameManager.reward_times = 0


# --- 弓箭手奖励与残殇字段 ---------------------------------------------------

func _test_archer_rewards() -> void:
	await _make_battle(0)
	check(GameManager.Bow != null, "弓箭手武器已注册到 GameManager")
	check(is_equal_approx(GameManager.Bow.per, 0.0), "残殇初始 per 为 0")

	GameManager._reward_detect(7)
	check(is_equal_approx(GameManager.Bow.per, 0.05), "奖励7 首次 +0.05 per（残殇）")
	check(GameManager.Bow.kill_line == 0.0, "奖励7 不再误加到 kill_line（狙击）")

	GameManager._reward_detect(7)
	check(is_equal_approx(GameManager.Bow.per, 0.07), "奖励7 再次 +0.02 per")
	check(GameManager.Bow.kill_line == 0.0, "奖励7 多次仍不污染 kill_line")

	GameManager._reward_detect(6)
	check(is_equal_approx(GameManager.Bow.kill_line, 0.15), "奖励6 才加 kill_line")

	var damage_before: float = GameManager.dmg_arrow()
	GameManager._reward_detect(1)
	check(GameManager.dmg_arrow() > damage_before, "奖励1 提升箭矢伤害（统一由攻击力派生）")
	check(is_equal_approx(GameManager.dmg_arrow(), damage_before * 1.2), "奖励1 提供 +20% 攻击力")

	# 19 淬锋之矢：流血层数与持续伤害
	GameManager._reward_detect(19)
	check(GameManager.archer_bleed_level == 1, "奖励19 解锁流血")
	check(is_equal_approx(GameManager.dmg_bleed(), GameManager.character_damage() * GameManager.RATIO_BLEED),
		"奖励19 流血强度随角色攻击力派生")
	var bleed_target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(bleed_target)
	bleed_target.global_position = Vector2(600.0, 900.0)
	await get_tree().process_frame
	for i in 4:
		bleed_target._add_bleed(1)
	check(bleed_target.bleed_stacks == 3, "流血层数上限 3（实际 %d）" % bleed_target.bleed_stacks)
	var hp_before_bleed: float = bleed_target.HP
	await get_tree().create_timer(0.7).timeout
	if is_instance_valid(bleed_target):
		check(bleed_target.HP < hp_before_bleed, "流血持续掉血")
		bleed_target.queue_free()
	else:
		check(false, "流血目标提前消失")

	# 拖拽：可见范围命中、边界夹紧、y 不变
	var character: Node2D = battle.get_node("Character_creator").get_child(0)
	check(character._point_on_me(character.global_position), "点人物身上能命中")
	check(not character._point_on_me(character.global_position + Vector2(250.0, 0.0)), "点远处不命中")
	character._begin_drag(character.global_position)
	character._move_to_x(99999.0)
	check(is_equal_approx(character.global_position.x, character.max_x), "拖到右侧被夹紧")
	character._move_to_x(-99999.0)
	check(is_equal_approx(character.global_position.x, character.min_x), "拖到左侧被夹紧")
	check(is_equal_approx(character.global_position.y, character._original_y), "拖拽不改 y")
	character.is_dragging = false

	# 音效 / BGM
	check(Audio._streams.size() >= 10, "音效已生成（%d 个）" % Audio._streams.size())
	check(Audio._bgm_player.stream != null and Audio._bgm_player.stream.get_length() > 1.0, "BGM 已生成")

	# 狙击特效：滑入 → 摇摆 → 锁定 → 斩杀 → 淡出
	GameManager.Exp_max = 1000000.0  # 防止测试过程中升级弹出奖励面板打断动画
	GameManager.Bow.kill_line = 0.15
	var snipe_target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(snipe_target)
	snipe_target.global_position = Vector2(400.0, 700.0)
	await get_tree().process_frame
	GameManager.Bow.call("_play_snipe", snipe_target, 0.0, true)
	await get_tree().process_frame
	var snipe_fx: Node = _find_by_script_suffix(battle, "sniping_target.gd")
	check(snipe_fx != null, "狙击时生成了狙击准星特效")
	await get_tree().create_timer(1.3).timeout
	check(not is_instance_valid(snipe_fx), "狙击特效播放完自动消失")
	check(not is_instance_valid(snipe_target), "狙击斩杀目标已死亡")


# --- 暂停界面与通用武器（原初飞刀）-----------------------------------------

func _test_weapon_and_pause() -> void:
	var pause_panel := battle.get_node_or_null("Overlay/PausePanel") as Control
	check(pause_panel != null, "战斗场景带了暂停界面")
	check(pause_panel != null and not pause_panel.visible, "默认不显示暂停界面")
	if pause_panel != null:
		pause_panel.call("open")
		check(pause_panel.visible and get_tree().paused, "暂停界面打开后游戏暂停")
		pause_panel.call("close")
		check(not pause_panel.visible and not get_tree().paused, "继续游戏后恢复运行")

	# 武器资源数据
	var info: Resource = load("res://Resource/Instance/weapon_primordial_knife.tres")
	check(info != null and str(info.get("weapon_name")) == "原初飞刀", "武器资源：原初飞刀")
	var upgrades: Array = info.get("reward_upgrades")
	check(upgrades.size() == 2, "武器资源配了 2 项基础升级")
	var extras: Dictionary = info.get("reward_class_extras")
	check(int(extras.get(0, -1)) == 26 and int(extras.get(1, -1)) == 27 and int(extras.get(2, -1)) == 28,
		"武器资源配好三职业专属奖励")

	# 获得武器
	check(not GameManager.weapon_owned, "开局还没有武器")
	GameManager._reward_detect(21)
	check(GameManager.weapon_owned, "抽到“获得武器”后标记已拥有")
	var character := get_tree().get_first_node_in_group("character")
	check(GameManager.weapon_node != null and is_instance_valid(GameManager.weapon_node), "武器节点已实例化")
	check(GameManager.weapon_node.get_parent() == character, "武器挂在角色节点下（角色附近显示）")
	check(GameManager.weapon_node.get_node_or_null("Icon") != null, "武器带显示图标")
	check(GameManager.weapon_node.get("_icon") != null and (GameManager.weapon_node.get("_icon") as CanvasItem).visible,
		"武器图标节点可见（换素材后也会自动跟随）")
	check(GameManager.Rewards_pool.has(22) and GameManager.Rewards_pool.has(23), "武器基础升级进池")
	check(GameManager.Rewards_pool.has(24) and GameManager.Rewards_pool.has(25), "武器技能进池")
	check(GameManager.Rewards_pool.has(26), "弓箭手专属奖励进池")
	check(not GameManager.reward_is_available(21), "拿到武器后不再刷“获得武器”")

	# 基础升级
	var knife: Node2D = GameManager.weapon_node
	var drop_attack_before: float = knife.get("damage")
	GameManager._reward_detect(22)
	check(float(knife.get("damage")) > drop_attack_before, "利刃：飞刀伤害提升（倍率制）")
	check(is_equal_approx(GameManager.weapon_ratio_bonus, 0.2), "利刃：倍率 +0.2")
	var interval_before: float = knife.get("attack_interval")
	GameManager._reward_detect(23)
	check(float(knife.get("attack_interval")) < interval_before, "疾投：投掷间隔缩短")

	# 技能
	GameManager._reward_detect(24)
	check(is_equal_approx(GameManager.weapon_max_hp_pct(), 0.03), "原初之力：3% 最大生命")
	GameManager._reward_detect(25)
	check(GameManager.weapon_echo_level == 1, "原初回响：1 级")

	# 职业专属：原初同调（弓箭手）
	GameManager._reward_detect(26)
	check(GameManager.weapon_archer_sync, "原初同调已解锁")
	check(float(knife.get("attack_interval")) < interval_before, "同调后飞刀比升级前更快")
	check(GameManager.Bow != null and GameManager.Bow.get_interval() > 0.0, "弓箭射速可读")

	# 瞄准转向时，武器图标要固定在角色身边（不能绕圈）
	var icon = knife.get("_icon")
	if icon != null:
		knife.rotation = 0.0
		await get_tree().process_frame
		var icon_at_zero: Vector2 = (icon as Node2D).global_position
		knife.rotation = -1.8
		await get_tree().process_frame
		var icon_at_turn: Vector2 = (icon as Node2D).global_position
		check(icon_at_zero.distance_to(icon_at_turn) < 12.0,
			"瞄准转向时武器图标不绕圈（位移 %.1f）" % icon_at_zero.distance_to(icon_at_turn))
		knife.rotation = 0.0
	else:
		check(false, "武器图标节点缺失")

	# 飞刀命中：普通伤害 + 最大生命百分比
	var target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(target)
	target.global_position = Vector2(400.0, 820.0)
	target.Max_HP = 1000.0
	target.HP = 1000.0
	target.defense = 0.0  # 本用例只验证“武器伤害 + 3% 最大生命”，先排除防御减免
	await get_tree().process_frame
	knife.call("fire_now")
	await get_tree().process_frame
	var projectile: Node = null
	for child in battle.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("knife_projectile.gd"):
			projectile = child
	check(projectile != null, "投掷会生成飞刀投射物")
	if projectile != null:
		var hp_before: float = target.HP
		projectile.call("_on_body_entered", target)
		var dropped: float = hp_before - target.HP
		check(dropped >= 80.0, "飞刀命中伤害含 3%% 最大生命（掉落 %.1f）" % dropped)
		check(projectile.is_queued_for_deletion(), "命中后飞刀消失")
	target.queue_free()
	for child in battle.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("knife_projectile.gd"):
			child.queue_free()
	await get_tree().process_frame


# --- 法师专属：淬火刀锋 -----------------------------------------------------

func _test_magician_weapon() -> void:
	await _make_battle(1)
	GameManager._reward_detect(21)
	check(GameManager.weapon_owned, "法师也能拿到原初飞刀")
	check(GameManager.Rewards_pool.has(27), "淬火刀锋进入法师奖励池")
	GameManager._reward_detect(27)
	check(GameManager.weapon_magician_fire, "淬火刀锋已解锁")
	var knife: Node2D = GameManager.weapon_node
	check(not bool(knife.get("_fire_armed")), "初始没有装填火焰")
	knife.call("_on_fire_timer_timeout")
	check(bool(knife.get("_fire_armed")), "周期到点后装填下一把飞刀")

	var target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(target)
	target.global_position = Vector2(400.0, 800.0)
	await get_tree().process_frame
	knife.call("fire_now")
	await get_tree().process_frame
	var projectile: Node = _find_by_script_suffix(battle, "knife_projectile.gd")
	check(projectile != null, "飞刀已投出")
	if projectile != null:
		projectile.call("_on_body_entered", target)
	await get_tree().process_frame
	var fire: Node = _find_by_script_suffix(battle, "fire_area.gd")
	check(fire != null, "命中处触发炼狱之路")
	target.queue_free()
	if fire != null:
		fire.queue_free()
	for child in battle.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("knife_projectile.gd"):
			child.queue_free()
	await get_tree().process_frame


# --- 防御值 / 穿透 ----------------------------------------------------------

func _test_defense() -> void:
	var target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(target)
	target.global_position = Vector2(120.0, 300.0)
	target.Max_HP = 5000.0
	target.HP = 5000.0
	await get_tree().process_frame

	# 无防御 → 全额
	target.defense = 0.0
	GameManager.penetration = 0.0
	var before: float = target.HP
	target._Damage(100.0)
	check(is_equal_approx(before - target.HP, 100.0), "无防御时伤害全额生效")

	# 防御 100 → 减免 50%
	target.defense = 100.0
	before = target.HP
	target._Damage(100.0)
	check(is_equal_approx(before - target.HP, 50.0),
		"防御 100 时减免 50%%（实际掉落 %.2f）" % (before - target.HP))

	# 穿透抵消防御
	GameManager.penetration = 100.0
	before = target.HP
	target._Damage(100.0)
	check(is_equal_approx(before - target.HP, 100.0), "穿透 ≥ 防御时恢复全额伤害")

	# 减免上限 2/3
	GameManager.penetration = 0.0
	target.defense = 100000.0
	before = target.HP
	target._Damage(100.0)
	var capped_drop: float = before - target.HP
	check(absf(capped_drop - 100.0 / 3.0) < 0.05,
		"防御再高减免也不超过 2/3（实际掉落 %.2f）" % capped_drop)

	# 治疗不吃防御减免
	target.defense = 0.0
	target.HP = 10.0
	target._Heal(50.0)
	check(is_equal_approx(target.HP, 60.0), "治疗不受防御影响")

	# 破甲奖励
	GameManager.penetration = 0.0
	check(GameManager.Reward_Asset_All.reward_list[29].name.contains("破甲"), "奖励表新增破甲词条")
	GameManager._reward_detect(29)
	check(is_equal_approx(GameManager.penetration, 8.0), "破甲奖励 +8 穿透")
	target.queue_free()
	await get_tree().process_frame


# --- 奖励卡片单独刷新 -------------------------------------------------------

func _test_reward_refresh() -> void:
	GameManager.Rewards_pool = [1, 2, 3, 4, 5, 6, 7, 8]
	var created: bool = GameManager.Reward_Creator._creat_reward()
	check(created, "为刷新测试生成了奖励面板")
	var panel = GameManager.Reward_Creator.get_child(0)
	await get_tree().process_frame
	var cards: Array = panel.get("_cards")
	var buttons: Array = panel.get("_refresh_buttons")
	check(cards.size() == 3 and buttons.size() == 3, "三张卡各带一个刷新按钮")

	var first_id: int = int(cards[0].reward_context)
	buttons[0].pressed.emit()
	check(int(cards[0].reward_context) != first_id, "刷新后换成了别的奖励")
	check(bool(buttons[0].disabled), "刷新按钮用过就置灰")
	var after: int = int(cards[0].reward_context)
	buttons[0].pressed.emit()
	check(int(cards[0].reward_context) == after, "同一张卡只能刷新一次")

	var ids: Array[int] = []
	for card in cards:
		ids.append(int(card.reward_context))
	var duplicated := ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]
	check(not duplicated, "刷新后三张卡不重复")

	for slot in [1, 2]:
		var old_id: int = int(cards[slot].reward_context)
		buttons[slot].pressed.emit()
		check(int(cards[slot].reward_context) != old_id, "第 %d 张卡也能单独刷新" % (slot + 1))

	await _dismiss_reward_panel()
	check(GameManager.Reward_Creator.get_child_count() == 0, "刷新测试后面板正常关闭")


# --- 治疗粒子 / 全局粒子调度 ------------------------------------------------

func _test_healing_particles() -> void:
	ParticleDirector.reset()
	check(ParticleDirector.active_count() == 0, "粒子调度初始为空")

	# 强度函数：并发越多，单体越弱
	var first := ParticleDirector.acquire()
	check(is_equal_approx(first, 1.0), "第一个粒子对象满强度")
	var second := ParticleDirector.acquire()
	check(second < first, "同时播放的对象变多后强度下降")
	for i in 10:
		ParticleDirector.acquire()
	var many := ParticleDirector.strength()
	check(many < 0.4, "并发 12 个对象时强度明显下降（%.2f）" % many)
	check(ParticleDirector.particle_count(many) >= 2, "强度再低也保留最少粒子数")
	check(ParticleDirector.particle_count(1.0) == ParticleDirector.BASE_PARTICLES, "满强度时粒子数等于基准值")
	ParticleDirector.reset()
	check(ParticleDirector.active_count() == 0, "可以重置全局粒子统计")

	# 名额上限跟着帧率动态调整
	check(ParticleDirector.max_active() == 60, "默认名额上限 60")
	ParticleDirector._apply_fps_sample(30.0)
	check(ParticleDirector.max_active() < 60, "帧率吃紧时收紧名额")
	for i in 8:
		ParticleDirector._apply_fps_sample(30.0)
	check(ParticleDirector.max_active() >= 18, "名额收紧有下限（实际 %d）" % ParticleDirector.max_active())
	for i in 20:
		ParticleDirector._apply_fps_sample(60.0)
	check(ParticleDirector.max_active() == 96, "帧率健康时名额放宽到 96")
	ParticleDirector.reset()

	# 敌人被治疗 → 在该位置生成治疗粒子
	var target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(target)
	target.global_position = Vector2(200.0, 620.0)
	target.Max_HP = 100.0
	target.HP = 10.0
	await get_tree().process_frame
	target._Heal(30.0)
	await get_tree().process_frame
	# 只找这个单位身上新生成的那一簇（场上可能有之前测试残留的粒子）
	var burst: Node = null
	for child in battle.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("heal_burst.gd") \
				and (child as Node2D).global_position.distance_to(target.global_position) < 8.0:
			burst = child
	check(burst != null, "敌人治疗时生成治疗粒子")
	check(ParticleDirector.active_count() >= 1, "治疗粒子计入全局统计")
	if burst != null:
		var particles := burst.get_node_or_null("Particles") as GPUParticles2D
		check(particles != null and particles.amount >= 2, "治疗粒子数量符合强度换算")
		check((burst as Node2D).global_position.distance_to(target.global_position) < 8.0,
			"治疗粒子出现在被治疗单位处")
		# 粒子跟随单位：单位移动后粒子应该跟着走（粒子必须在局部空间才会真的跟）
		check(particles != null and particles.local_coords, "治疗粒子使用局部空间（粒子会跟着单位走）")
		target.global_position += Vector2(120.0, 0.0)
		await get_tree().process_frame
		check((burst as Node2D).global_position.distance_to(target.global_position) < 8.0,
			"治疗粒子会跟随被治疗单位")
	await get_tree().create_timer(1.2).timeout
	check(not is_instance_valid(burst), "治疗粒子播完自动销毁")
	check(ParticleDirector.active_count() == 0, "销毁后归还全局计数")
	target.queue_free()
	await get_tree().process_frame


# --- 阶段二奖励：鹰眼 / 魔力解构 / 两个图腾 / 召唤物燃血 ----------------------

func _test_stage2_rewards() -> void:
	# 弓箭手：Lv9 解锁阶段二 + 鹰眼
	await _make_battle(0)
	GameManager.level = 9
	GameManager._check_reward_stage_unlock()
	check(GameManager.Rewards_pool.has(19), "Lv9 后弓箭手解锁淬锋之矢")
	check(GameManager.Rewards_pool.has(30), "Lv9 后弓箭手解锁鹰眼")
	check(GameManager.Reward_Asset_All.reward_list[30].name.contains("鹰眼"), "奖励表新增鹰眼词条")
	GameManager.penetration = 0.0
	GameManager._reward_detect(30)
	check(is_equal_approx(GameManager.penetration_pct, 0.2), "鹰眼 1 级：20% 穿透")
	GameManager._reward_detect(30)
	check(is_equal_approx(GameManager.penetration_pct, 0.35), "鹰眼 2 级：35% 穿透")
	GameManager._reward_detect(30)
	check(is_equal_approx(GameManager.penetration_pct, 0.5), "鹰眼 3 级：50% 穿透（最高）")

	var dummy: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(dummy)
	dummy.global_position = Vector2(120.0, 300.0)
	dummy.Max_HP = 5000.0
	dummy.HP = 5000.0
	dummy.defense = 100.0
	await get_tree().process_frame
	var hp_before: float = dummy.HP
	dummy._Damage(100.0)
	var drop: float = hp_before - dummy.HP
	# 防御 100 → 百分比穿透 50% → 有效 50 → 减免 50/150 = 1/3 → 掉 66.67
	check(absf(drop - 200.0 / 3.0) < 0.1, "鹰眼满级：防御 100 只减免 1/3（实际掉 %.2f）" % drop)
	dummy.queue_free()
	await get_tree().process_frame
	GameManager.penetration_pct = 0.0

	# 法师：魔力解构
	await _make_battle(1)
	GameManager.level = 9
	GameManager._check_reward_stage_unlock()
	check(GameManager.Rewards_pool.has(31), "Lv9 后法师解锁魔力解构")
	check(GameManager.Reward_Asset_All.reward_list[31].name.contains("魔力解构"), "奖励表新增魔力解构词条")
	GameManager._reward_detect(31)
	check(GameManager.arcane_level == 1, "魔力解构 1 级")
	var circle = GameManager.Magic_Cricle
	check(circle != null, "法师魔法阵存在")
	circle._fire_arcane()
	await get_tree().process_frame
	var bolt: Node = null
	for child in circle.get_children():
		var sc: Script = child.get_script()
		if sc != null and str(sc.resource_path).ends_with("arcane_bolt.gd"):
			bolt = child
	check(bolt != null, "魔力解构丢出奥术魔弹")
	check(bolt != null and is_equal_approx(float(bolt.damage), GameManager.dmg_arcane()),
		"奥术魔弹伤害由角色攻击力派生（%.0f）" % GameManager.dmg_arcane())
	var target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(target)
	target.global_position = Vector2(300.0, 600.0)
	target.Max_HP = 5000.0
	target.HP = 5000.0
	target.defense = 100.0
	await get_tree().process_frame
	var target_hp: float = target.HP
	bolt.call("_start_move")
	bolt.call("_on_body_entered", target)
	check(target.HP < target_hp, "奥术魔弹命中造成伤害")
	check(target.defense_debuff > 0.0, "奥术魔弹命中降低目标防御")
	check(target.effective_defense() < 100.0, "降防后有效防御下降")
	target.queue_free()
	await get_tree().process_frame

	# 召唤师：两个图腾 + 燃血召唤物
	await _make_battle(2)
	GameManager.level = 9
	GameManager._check_reward_stage_unlock()
	check(GameManager.Rewards_pool.has(32) and GameManager.Rewards_pool.has(33), "Lv9 后召唤师解锁两个图腾")
	GameManager._reward_detect(32)
	GameManager._reward_detect(33)
	check(GameManager.totem_curse_level == 1, "解离恶咒已解锁")
	check(GameManager.totem_blessing_level == 1, "解脱恩赐已解锁")
	var manager = GameManager.Summoner.get_node("Skill_Manager")

	# 解离恶咒：敌人受伤 + 降防
	var enemy: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(enemy)
	enemy.global_position = Vector2(360.0, 800.0)
	enemy.Max_HP = 5000.0
	enemy.HP = 5000.0
	enemy.defense = 100.0
	await get_tree().process_frame
	manager._place_curse_totem()
	await get_tree().process_frame
	var curse_totem: Node = _find_by_script_suffix(battle, "totem.gd")
	check(curse_totem != null, "解离恶咒放下了图腾")
	check(str(curse_totem.get("kind")) == "hurt", "解离恶咒图腾是伤害型")
	var enemy_hp: float = enemy.HP
	curse_totem.call("_apply_tick")
	check(enemy.HP < enemy_hp, "图腾范围内敌人持续受伤")
	check(enemy.defense_debuff > 0.0, "图腾范围内敌人防御被削弱")
	check(curse_totem.global_position.distance_to(enemy.global_position) <= float(curse_totem.get("radius")),
		"图腾放在目标身边且覆盖到它")

	# 回归：怪少（都在远处）时也必须能放下图腾（原来会直接放弃）
	curse_totem.queue_free()
	await get_tree().process_frame
	enemy.queue_free()
	await get_tree().process_frame
	var far_enemy: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(far_enemy)
	far_enemy.global_position = Vector2(360.0, -120.0)  # 距离召唤师 >> 620px
	await get_tree().process_frame
	check(far_enemy.global_position.distance_to(GameManager.Summoner.global_position) > 620.0,
		"远处的敌人不在 620px 范围内")
	check(manager._place_curse_totem(), "只有一只远处敌人时也能放下图腾")
	await get_tree().process_frame
	var far_totem: Node = null
	for child in battle.get_children():
		var sc: Script = child.get_script()
		if sc != null and str(sc.resource_path).ends_with("totem.gd") and str(child.get("kind")) == "hurt":
			far_totem = child
	check(far_totem != null, "图腾落到了那只远处敌人附近")
	if far_totem != null:
		# 落点会在场地边界（y ≥ -60）被夹住，所以允许一点偏差
		check(far_totem.global_position.distance_to(far_enemy.global_position) < 150.0,
			"图腾位置贴着那只远处的敌人（%.0f px）" % far_totem.global_position.distance_to(far_enemy.global_position))
		far_totem.queue_free()
		await get_tree().process_frame
	far_enemy.queue_free()
	await get_tree().process_frame

	# 回归：场上一个敌人也没有时，退化成和解脱恩赐一样的随机落点
	check(manager._place_curse_totem(), "场上没有敌人时也能放下图腾（随机落点）")
	await get_tree().process_frame
	var lone_totem: Node = null
	for child in battle.get_children():
		var sc: Script = child.get_script()
		if sc != null and str(sc.resource_path).ends_with("totem.gd"):
			lone_totem = child
	check(lone_totem != null, "空场时图腾确实生成")
	if lone_totem != null:
		lone_totem.queue_free()
		await get_tree().process_frame

	# 解脱恩赐：己方单位回血
	var ally: Node2D = load("res://Scene/Character/weapon/summon_minion.tscn").instantiate()
	battle.add_child(ally)
	ally.global_position = Vector2(360.0, 700.0)
	ally.hp = 10.0
	await get_tree().process_frame
	manager._place_blessing_totem()
	await get_tree().process_frame
	var bless_totem: Node = null
	for child in battle.get_children():
		var sc: Script = child.get_script()
		if sc != null and str(sc.resource_path).ends_with("totem.gd") and str(child.get("kind")) == "heal":
			bless_totem = child
	check(bless_totem != null, "解脱恩赐放下了治疗图腾")
	bless_totem.global_position = ally.global_position
	var ally_hp: float = ally.hp
	bless_totem.call("_apply_tick")
	check(ally.hp > ally_hp, "治疗图腾范围内己方单位回血")

	# 图腾到时间会消失
	var totem_duration: float = float(bless_totem.get("duration"))
	bless_totem.set("_age", totem_duration - 0.01)
	bless_totem.call("_process", 0.05)
	await get_tree().process_frame
	check(not is_instance_valid(bless_totem), "图腾到时间自动消失")

	# 召唤物燃血生存
	var minion_scene: PackedScene = load("res://Scene/Character/weapon/summon_minion.tscn")
	var minion: Node2D = minion_scene.instantiate()
	battle.add_child(minion)
	minion.setup(10.0, 100.0)
	check(is_equal_approx(minion.drain_rate, 5.0), "燃血速率 = 血量/原寿命 × 50%")
	var minion_hp: float = minion.hp
	minion._physics_process(1.0)
	check(minion.hp < minion_hp, "非攻击状态会流逝血量")
	var remain_before: float = minion.remaining_life()
	minion.hp = minion.max_hp * 0.2
	check(minion.remaining_life() < remain_before, "剩余存活时间随血量下降")
	check(minion.remaining_life() <= 100.0, "剩余存活时间不超过 100 秒上限")

	# 快没命时透明度也不会低于 45%
	minion.hp = 1.0
	minion.set("age", 99.9)
	minion._update_alpha()
	var minion_sprite := minion.get_node("Sprite2D") as Sprite2D
	check(minion_sprite.modulate.a >= 0.449, "召唤物透明度下限 45%%（实际 %.2f）" % minion_sprite.modulate.a)
	minion.set("age", 0.0)

	# 超过上限时优先删除剩余时间最少的
	var weak: Node2D = minion_scene.instantiate()
	battle.add_child(weak)
	weak.setup(10.0, 100.0)
	weak.hp = 20.0
	var strong: Node2D = minion_scene.instantiate()
	battle.add_child(strong)
	strong.setup(10.0, 100.0)
	strong.hp = 100.0
	minion.hp = 100.0
	await get_tree().process_frame
	check(weak.remaining_life() < minion.remaining_life(), "血量少的剩余时间更短")
	GameManager._evict_weakest_minion()
	check(weak.is_queued_for_deletion(), "超过 99 只时优先删除剩余时间最少的")
	check(not minion.is_queued_for_deletion() and not strong.is_queued_for_deletion(), "其余召唤物保留")

	# 存在时间上限 100 秒
	minion.set("age", 100.0)
	minion.hp = minion.max_hp
	minion._physics_process(0.1)
	await get_tree().process_frame
	check(not is_instance_valid(minion), "到达 100 秒存在上限后消失")

	for leftover in [curse_totem, enemy, ally, strong]:
		if leftover != null and is_instance_valid(leftover):
			leftover.queue_free()
	await get_tree().process_frame


# --- BOSS：史莱姆王 ---------------------------------------------------------

func _test_boss() -> void:
	await _make_battle(0)

	# 9 级之前不计时、不刷
	GameManager.in_run = true
	GameManager.level = 8
	GameManager.GameProgress = 2
	GameManager._boss_timer = 0.0
	GameManager._tick_boss(9999.0)
	await get_tree().process_frame
	check(_find_by_script_suffix(battle, "boss_slime_king.gd") == null, "9 级前不刷 BOSS")

	# 9 级后按「时间间隔」刷新（不再按波次台阶触发）
	GameManager.level = 9
	GameManager.GameProgress = 3
	GameManager._boss_timer = 0.0
	var boss_gap: float = GameManager.boss_interval()
	check(boss_gap >= 42.0 and boss_gap <= 80.0, "BOSS 间隔由进度决定（%.0f 秒）" % boss_gap)
	GameManager._tick_boss(boss_gap - 1.0)
	await get_tree().process_frame
	check(_find_by_script_suffix(battle, "boss_slime_king.gd") == null, "还没到间隔不刷 BOSS")
	GameManager._tick_boss(2.0)
	await get_tree().process_frame
	var boss = _find_by_script_suffix(battle, "boss_slime_king.gd")
	check(boss != null, "到间隔后刷出 BOSS")
	check(not get_tree().get_nodes_in_group("bosses").is_empty(), "BOSS 注册到 bosses 分组")
	check(boss != null and int(boss.damage) == 5, "史莱姆王对城墙伤害 5 点")
	check(boss != null and boss.get_node_or_null("HP_Bar") is ProgressBar, "BOSS 血条用 ProgressBar")
	check(boss != null and boss.get_node_or_null("Show_HP") == null, "BOSS 不显示血量数字")
	check(boss != null and boss.get_node_or_null("Crown") != null, "BOSS 头上有皇冠")
	var boss_hp_early: float = boss.Max_HP
	var boss_def_early: float = boss.defense
	var bar: ProgressBar = boss.get_node("HP_Bar")
	check(is_equal_approx(bar.max_value, boss_hp_early), "血条上限等于 BOSS 血量")
	boss._Damage(boss_hp_early * 0.25)
	check(bar.value < bar.max_value, "受伤后血条按比例下降")
	boss.queue_free()
	await get_tree().process_frame

	# 场上有 BOSS 时不会再刷第二只
	var boss_dup = GameManager.BOSS_SCENES[0].instantiate()
	battle.add_child(boss_dup)
	await get_tree().process_frame
	GameManager._boss_timer = 0.0
	GameManager._tick_boss(9999.0)
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("bosses").size() == 1, "场上同时只有一只 BOSS")
	boss_dup.queue_free()
	await get_tree().process_frame

	# 间隔随进度缩短，但有下限
	var early_gap: float = GameManager.boss_interval()
	GameManager.GameProgress = 7
	var late_gap: float = GameManager.boss_interval()
	check(late_gap < early_gap, "进度越高 BOSS 间隔越短（%.0f → %.0f 秒）" % [early_gap, late_gap])
	GameManager.GameProgress = 40
	check(GameManager.boss_interval() >= 42.0, "BOSS 间隔有下限，不会刷屏（%.0f 秒）" % GameManager.boss_interval())

	# 间隔到点后会从 BOSS 列表里随机挑一只再刷
	GameManager.level = 9
	GameManager.GameProgress = 7
	GameManager._boss_timer = 0.0
	GameManager._tick_boss(GameManager.boss_interval() + 1.0)
	await get_tree().process_frame
	var boss7 = _find_by_script_suffix(battle, "boss_slime_king.gd")
	check(boss7 != null, "间隔到点后再刷一只 BOSS")
	check(boss7.Max_HP > boss_hp_early and boss7.defense > boss_def_early, "BOSS 血量与防御随进度成长")

	# 击杀奖励：大量经验 + 城墙上限 + 炸出 3~5 只史莱姆
	GameManager.Exp_max = 1000000.0  # 本段只验证掉经验，不让等级奖励弹板打断
	var exp_before: float = GameManager.Exp_cur
	var wall_max_before: int = GameManager.Wall_Max
	var death_pos: Vector2 = boss7.global_position
	var known_ids := {}
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		known_ids[enemy_node.get_instance_id()] = true
	boss7._Damage(999999.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameManager.Wall_Max == wall_max_before + 1, "击杀 BOSS 提升城墙血量上限（%d）" % GameManager.Wall_Max)
	check(GameManager.Wall_Health > 0, "击杀 BOSS 后城墙仍可用")
	check(GameManager.Exp_cur > exp_before, "击杀 BOSS 掉落大量经验（%.0f）" % GameManager.Exp_cur)
	var spawned := 0
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if known_ids.has(enemy_node.get_instance_id()):
			continue
		if (enemy_node as Node2D).global_position.distance_to(death_pos) < 220.0:
			spawned += 1
	check(spawned >= 3 and spawned <= 5, "BOSS 死后在周围炸出 3~5 只史莱姆（实际 %d）" % spawned)

	# BOSS 撞墙扣 5 点耐久（不 await，避免它自己的 _physics_process 先把墙撞了）
	GameManager.Wall_Health = 10
	GameManager.Wall_Max = 10
	var boss_wall = load("res://Scene/Enemy/boss_slime_king.tscn").instantiate()
	battle.add_child(boss_wall)
	boss_wall.global_position = Vector2(360.0, 1300.0)
	boss_wall._detect_self()
	check(GameManager.Wall_Health == 5, "BOSS 撞墙扣 5 点耐久（实际 %d）" % GameManager.Wall_Health)
	GameManager.Wall_Max = GameManager.WALL_MAX_HEALTH
	GameManager.Wall_Health = GameManager.WALL_MAX_HEALTH
	await get_tree().process_frame

	# BOSS 专属减伤①：比例伤害只吃 25%
	var boss_pct = load("res://Scene/Enemy/boss_slime_king.tscn").instantiate()
	battle.add_child(boss_pct)
	boss_pct.global_position = Vector2(300.0, 600.0)
	await get_tree().process_frame
	check(is_equal_approx(boss_pct.percent_resist, 0.75), "BOSS 有 75% 比例伤害抗性")
	var boss_max: float = boss_pct.Max_HP
	boss_pct.defense = 0.0  # 单看比例抗性，先排除防御
	var boss_pct_hp: float = boss_pct.HP
	boss_pct._damage_percent_hp(0.10)
	var boss_pct_drop: float = boss_pct_hp - boss_pct.HP
	check(absf(boss_pct_drop - boss_max * 0.10 * 0.25) < 2.0,
		"10%% 最大生命的比例伤害对 BOSS 只剩 1/4（实际 %.0f / %.0f）" % [boss_pct_drop, boss_max])

	# 普通怪的比例伤害完全不受影响
	var slime_pct: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(slime_pct)
	slime_pct.global_position = Vector2(520.0, 600.0)
	await get_tree().process_frame
	slime_pct.defense = 0.0
	slime_pct.Max_HP = 1000.0
	slime_pct.HP = 1000.0
	slime_pct._damage_percent_hp(0.10)
	check(absf((1000.0 - slime_pct.HP) - 100.0) < 1.0, "普通怪的比例伤害照旧（掉 100）")

	# BOSS 专属减伤②：斩杀对 BOSS 只有 10% 效果，不再秒杀
	var boss_exec_hp: float = boss_pct.HP
	boss_pct._execute()
	check(is_instance_valid(boss_pct) and boss_pct.HP > 0.0, "BOSS 不会被斩杀直接秒掉")
	var exec_drop: float = boss_exec_hp - boss_pct.HP
	check(absf(exec_drop - boss_max * 0.10) < 2.0,
		"BOSS 的斩杀只有 10%% 效果（实际掉落 %.0f / %.0f）" % [exec_drop, boss_max])

	# 普通怪斩杀仍然是秒杀
	slime_pct._execute()
	await get_tree().process_frame
	check(not is_instance_valid(slime_pct), "普通怪斩杀仍是秒杀")
	boss_pct.queue_free()
	await get_tree().process_frame


# --- 滚动苹果 ---------------------------------------------------------------

func _test_apple() -> void:
	await _make_battle(0)
	GameManager.in_run = true

	# 6 级前不刷
	GameManager.level = 5
	GameManager._apple_timer = 0.0
	GameManager._tick_apple(999.0)
	await get_tree().process_frame
	check(_find_by_script_suffix(battle, "scrolling_apple.gd") == null, "6 级前不刷滚动苹果")

	# 6 级后少量、10 级后大量
	GameManager.level = 6
	check(is_equal_approx(GameManager.apple_interval(), 5.0), "6 级后苹果少量出现（间隔 5 秒）")
	GameManager.level = 10
	check(is_equal_approx(GameManager.apple_interval(), 1.6), "10 级后苹果大量出现（间隔 1.6 秒）")

	GameManager._apple_timer = 0.0
	GameManager._tick_apple(0.1)
	await get_tree().process_frame
	var apple = _find_by_script_suffix(battle, "scrolling_apple.gd")
	check(apple != null, "到间隔后刷出滚动苹果")
	check(apple != null and get_tree().get_nodes_in_group("enemies").has(apple), "苹果是普通敌人（进 enemies 分组）")
	check(apple != null and apple.angle_deg >= 30.0 and apple.angle_deg <= 60.0,
		"滚动角度在 30°~60° 之间（%.0f°）" % apple.angle_deg)

	# 基础速度略快于其他敌人
	var slime_cmp: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(slime_cmp)
	await get_tree().process_frame
	check(apple.speed > slime_cmp.speed, "苹果基础速度略快于史莱姆（%s / %s）" % [str(apple.speed), str(slime_cmp.speed)])
	slime_cmp.queue_free()

	# 登场加速：0~1 秒 +100%，1~2 秒衰减，之后恢复
	apple.set("_spawn_time", 0.5)
	check(is_equal_approx(apple.current_boost(), 2.0), "登场瞬间 +100% 速度")
	apple.set("_spawn_time", 1.5)
	var mid_boost: float = apple.current_boost()
	check(mid_boost > 1.0 and mid_boost < 2.0, "1 秒后加速开始衰减（x%.2f）" % mid_boost)
	apple.set("_spawn_time", 2.5)
	check(is_equal_approx(apple.current_boost(), 1.0), "2 秒后加速完全消失")

	# 贴图一直旋转
	var apple_sprite: AnimatedSprite2D = apple.get_node("AnimatedSprite2D")
	var rot_before: float = apple_sprite.rotation
	apple.set("_spawn_time", 5.0)
	apple._physics_process(0.1)
	check(absf(apple_sprite.rotation - rot_before) > 0.01, "苹果贴图持续旋转")

	# 撞左右边界反弹并换角度
	var old_sign: float = apple.dir_sign
	apple.global_position = Vector2(652.0, 600.0)
	apple._bounce_if_needed()
	check(apple.dir_sign != old_sign, "撞边界后横向方向反弹")
	check(apple.angle_deg >= 30.0 and apple.angle_deg <= 60.0, "反弹后角度重新落在 30°~60°")
	check(apple.global_position.x < 652.0, "反弹后回到场地内")

	# 斜着滚动：横纵坐标同时在变
	apple.global_position = Vector2(360.0, 700.0)
	apple.set("_spawn_time", 5.0)
	var pos_before: Vector2 = apple.global_position
	apple._physics_process(0.5)
	check(absf(apple.global_position.x - pos_before.x) > 0.01, "苹果是斜着滚动的（横向也在变）")
	check(apple.global_position.y > pos_before.y, "同时继续向下推进")

	apple.queue_free()
	await get_tree().process_frame


# --- 12 级后的出怪量 --------------------------------------------------------

func _test_spawn_pressure() -> void:
	await _make_battle(0)
	var spawner: Node = _find_by_script_suffix(battle, "enemies_creator_creator.gd")
	check(spawner != null, "战斗场景带刷怪器")
	if spawner == null:
		return
	var before: int = spawner.get_child_count()
	spawner.call("_creat_new_creator", 4)
	var after4: int = spawner.get_child_count()
	check(after4 - before == 2, "12 级（progress 4）额外增加 2 条刷怪线（%d）" % (after4 - before))
	spawner.call("_creat_new_creator", 6)
	var after6: int = spawner.get_child_count()
	check(after6 - after4 == 3, "更后期（progress 6）额外增加 3 条刷怪线（%d）" % (after6 - after4))


# --- 新手引导 ---------------------------------------------------------------

func _test_tutorial() -> void:
	GameManager.tutorial_enabled = true
	await _make_battle(0)
	var panel := battle.get_node_or_null("Overlay/TutorialPanel") as Control
	check(panel != null, "战斗场景带了引导界面")
	check(panel != null and panel.visible, "开启引导后开局会显示引导")
	check(GameManager.tutorial_active, "引导期间处于引导状态")
	check(get_tree().paused, "引导期间整局暂停（不会刷怪/掉城墙）")
	check(get_tree().get_nodes_in_group("enemies").is_empty(), "引导期间没有怪物")
	var pause_button := battle.get_node_or_null("UI/PauseButton") as Control
	check(pause_button != null and not pause_button.visible, "引导期间隐藏暂停按钮")

	# 引导期间城墙不掉血
	GameManager.Wall_Health = 10
	GameManager._BeDamaged(5)
	check(GameManager.Wall_Health == 10, "引导期间城墙不会掉耐久")

	# 第 1 步：在屏幕上点一下 → 武器转向 + 进入下一步
	check(int(panel.get("step_index")) == 0, "引导从基本操作开始")
	var aim_event := InputEventMouseButton.new()
	aim_event.button_index = MOUSE_BUTTON_LEFT
	aim_event.pressed = true
	aim_event.position = Vector2(360.0, 500.0)
	panel.call("_input", aim_event)
	await get_tree().process_frame
	check(int(panel.get("step_index")) == 1, "点按屏幕后进入第 2 步")

	# 第 2 步：按住角色拖动（暂停态下由引导面板驱动）
	var character: Node2D = get_tree().get_first_node_in_group("character")
	var x_before: float = character.global_position.x
	var screen_pos: Vector2 = character.get_global_transform_with_canvas().origin
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen_pos
	panel.call("_input", press)
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos + Vector2(90.0, 0.0)
	panel.call("_input", motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = screen_pos + Vector2(90.0, 0.0)
	panel.call("_input", release)
	await get_tree().process_frame
	await get_tree().process_frame
	check(character.global_position.x > x_before + 30.0, "暂停态下也能拖动角色（教学）")
	check(int(panel.get("step_index")) == 2, "拖动角色后进入系统介绍")

	# 第 3–5 步：点下一步读完
	for i in 3:
		panel.call("_next_step")
		await get_tree().process_frame
	check(not panel.visible, "引导结束后隐藏")
	check(not GameManager.tutorial_active, "引导结束后退出引导状态")
	check(not get_tree().paused, "引导结束后解除暂停")
	check(pause_button != null and pause_button.visible, "引导结束后恢复暂停按钮")

	# 引导结束后城墙恢复正常受伤
	GameManager._BeDamaged(1)
	check(GameManager.Wall_Health == 9, "引导结束后城墙正常掉耐久")

	# 开关写进存档
	GameManager.set_tutorial_enabled(false)
	var config := ConfigFile.new()
	check(config.load("user://save.cfg") == OK, "设置存档可读")
	check(config.get_value("settings", "tutorial", true) == false, "引导开关写进存档")
	GameManager.load_record()
	check(not GameManager.tutorial_enabled, "重新读取存档后开关保持关闭")
	GameManager.tutorial_enabled = false
	await get_tree().process_frame


# --- 奖励面板与「池子抽空」保护 ---------------------------------------------

func _test_reward_pool_guard() -> void:
	var created: bool = GameManager.Reward_Creator._creat_reward()
	check(created, "奖励面板生成了卡片")
	var panel = GameManager.Reward_Creator.get_child(0)
	check(panel != null and panel.option_count > 0, "卡片数量大于 0")
	check(panel.process_mode == Node.PROCESS_MODE_WHEN_PAUSED, "奖励面板可在暂停时点击")
	await _dismiss_reward_panel()
	check(GameManager.Reward_Creator.get_child_count() == 0, "选完奖励后面板已销毁")
	check(not get_tree().paused, "选完奖励后恢复运行")

	# 全部奖励满级 → 不再弹面板，也不能把游戏卡在暂停
	for info in GameManager.Reward_Asset_All.reward_list:
		info.level = 3
	var created_when_full: bool = GameManager.Reward_Creator._creat_reward()
	check(not created_when_full, "奖励全部满级时不出卡片")
	check(not get_tree().paused, "池子为空时不会暂停游戏")
	await get_tree().process_frame


# --- 召唤师 14–20、临时单位、18、28 ----------------------------------------

func _test_summoner_skills() -> void:
	await _make_battle(2)
	check(GameManager.Summoner != null, "召唤师已注册到 GameManager")
	var unit: Node = GameManager.Summoner.get_node("summing_one")
	check(is_equal_approx(unit.damage, GameManager.dmg_summoner_main()), "召唤物伤害由角色攻击力派生")
	check(GameManager.Rewards_pool.has(14), "召唤师池子里有「提升攻击力」")
	check(GameManager.Rewards_pool.has(20), "召唤师池子里有「提升召唤物攻速」")
	check(GameManager.Reward_Asset_All.reward_list[20].name.contains("攻速"),
		"奖励表新增了攻速词条（%s）" % GameManager.Reward_Asset_All.reward_list[20].name)

	var unit_timer: Timer = unit.get_node("Timer")
	check(is_equal_approx(unit_timer.wait_time, 0.5), "召唤物初始攻击间隔 0.5s")
	GameManager._reward_detect(20)
	check(is_equal_approx(GameManager.summon_attack_interval, 0.425),
		"奖励20 把攻击间隔缩短到 0.425s（实际 %s）" % str(GameManager.summon_attack_interval))
	check(is_equal_approx(unit_timer.wait_time, 0.425), "召唤物的攻击计时器同步变快")
	GameManager._reward_detect(20)
	check(GameManager.summon_attack_interval < 0.425, "奖励20 可叠加")

	var cd_before_reward14: float = GameManager.character_damage()
	GameManager._reward_detect(14)
	GameManager.refresh_summons()
	check(GameManager.character_damage() > cd_before_reward14, "奖励14 提升召唤师攻击力")
	check(is_equal_approx(unit.damage, GameManager.dmg_summoner_main()), "主召唤物伤害跟着召唤师攻击力走")
	check(is_equal_approx(GameManager.dmg_summoner_main(),
		GameManager.character_damage() * GameManager.RATIO_SUMMONER_MAIN),
		"主召唤物 = 召唤师攻击力 × 0.5（没有独立加成）")
	check(is_equal_approx(GameManager.dmg_minion(),
		GameManager.character_damage() * GameManager.RATIO_MINION),
		"临时单位也只看召唤师攻击力")

	GameManager._reward_detect(15)
	await get_tree().process_frame
	await get_tree().process_frame
	var crack: Node = _find_by_script_suffix(battle, "summoning_crack.gd")
	check(crack != null, "奖励15 生成裂隙")
	if crack != null:
		check(is_equal_approx(crack.scale.x, 0.75), "1 级裂隙体型 0.75")
		GameManager._reward_detect(15)
		await get_tree().process_frame
		check(is_equal_approx(crack.per, 0.15), "2 级裂隙斩杀线 15%")
		check(is_equal_approx(crack.scale.x, 0.84), "2 级裂隙体型变大")

	GameManager._reward_detect(16)
	GameManager._reward_detect(17)
	GameManager.Wall_Health = 5
	var manager: Node = GameManager.Summoner.get_node("Skill_Manager")
	manager._heal_timer = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameManager.Wall_Health == 6, "奖励17 城墙治疗 +1（实际 %d）" % GameManager.Wall_Health)

	# 16 溶原增殖：击杀后生成临时单位
	var slime: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(slime)
	slime.global_position = Vector2(400.0, 700.0)
	await get_tree().process_frame
	slime._Damage(10000.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("summon_minions").size() >= 1, "奖励16 击杀后生成临时单位")
	await _dismiss_reward_panel()

	# 临时单位：血量 / 索敌移动 / 随机游荡 / 被攻击 / 被治疗 / 攻速继承
	var minion: Node2D = get_tree().get_nodes_in_group("summon_minions")[0]
	check(minion.max_hp > 0.0 and minion.hp > 0.0 and minion.hp <= minion.max_hp + 0.01,
		"临时单位有血量（%s / %s）" % [str(snappedf(minion.hp, 0.1)), str(minion.max_hp)])
	check(is_equal_approx(minion.attack_interval, GameManager.summon_attack_interval * 2.0),
		"临时单位攻速为本体的 50%%（间隔 %s，本体 %s）" % [
			str(minion.attack_interval), str(GameManager.summon_attack_interval),
		])
	check(minion.attack_radius > 0.0 and minion.detect_radius > minion.attack_radius * 2.0,
		"索敌范围明显大于攻击范围（攻击 %.0f / 索敌 %.0f）" % [minion.attack_radius, minion.detect_radius])
	var minion_pos: Vector2 = minion.global_position
	var bait: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(bait)
	bait.global_position = minion_pos + Vector2(0.0, -minion.detect_radius * 0.8)
	await get_tree().process_frame
	var dist_before: float = minion.global_position.distance_to(bait.global_position)
	minion._update_move(1.0)
	check(minion.global_position.distance_to(bait.global_position) < dist_before, "索敌范围内会朝敌人移动")
	bait.queue_free()
	await get_tree().process_frame
	minion._has_wander_target = false
	minion._wander_timer = 0.0
	minion._update_move(0.016)
	check(minion._has_wander_target, "没有敌人时会挑一个随机目标")
	var before_wander: Vector2 = minion.global_position
	minion._update_move(1.0)
	check(minion.global_position.distance_to(before_wander) > 5.0, "随机目标下会缓慢移动")

	var attacker: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(attacker)
	attacker.global_position = minion.global_position + Vector2(40.0, 0.0)
	await get_tree().process_frame
	var minion_hp_before: float = minion.hp
	attacker._tick_ally_combat(1.3)
	check(minion.hp < minion_hp_before, "敌人会攻击附近的召唤单位")
	var attacker_pos: Vector2 = attacker.global_position
	attacker._walk(1.0)
	var grappled_move: float = attacker.global_position.distance_to(attacker_pos)
	check(grappled_move > 1.0, "被召唤单位缠住的敌人仍会前进（不再堵住出生点）")
	# 松开缠绕后同样一次 _walk 的位移应该正好是缠绕时的两倍 → 独立 50% 乘区
	attacker._ally_target = null
	var free_pos: Vector2 = attacker.global_position
	attacker._walk(1.0)
	var free_move: float = attacker.global_position.distance_to(free_pos)
	check(free_move > 1.0 and absf(free_move / maxf(grappled_move, 0.001) - 2.0) < 0.15,
		"缠绕减速是独立的 50%% 乘区（缠绕 %.2f / 正常 %.2f）" % [grappled_move, free_move])
	attacker.queue_free()
	minion._heal(9999.0)
	check(is_equal_approx(minion.hp, minion.max_hp), "临时单位能被治疗满血")

	# 同处连续生成时出生点要错开
	var spawn_point := Vector2(320.0, 760.0)
	for i in 3:
		GameManager._spawn_minion(spawn_point)
	await get_tree().process_frame
	var all_minions := get_tree().get_nodes_in_group("summon_minions")
	var newest: Array = all_minions.slice(maxi(all_minions.size() - 3, 0))
	var overlaps := 0
	for i in newest.size():
		for j in range(i + 1, newest.size()):
			var gap: float = (newest[i] as Node2D).global_position.distance_to((newest[j] as Node2D).global_position)
			if gap < (newest[i] as Node2D).separation_radius * 0.9:
				overlaps += 1
	check(overlaps == 0, "同处生成的临时单位出生点会错开（重叠 %d 对）" % overlaps)

	# 两个单位被挪到同一位置时会被推开
	var unit_a: Node2D = newest[0]
	var unit_b: Node2D = newest[1]
	unit_a.global_position = Vector2(320.0, 700.0)
	unit_b.global_position = unit_a.global_position
	for i in 20:
		unit_a._apply_separation(0.1)
		unit_b._apply_separation(0.1)
	var gap_after: float = unit_a.global_position.distance_to(unit_b.global_position)
	check(gap_after > unit_a.separation_radius * 0.5, "重叠的临时单位会互相推开（间距 %.0f）" % gap_after)
	await get_tree().process_frame

	# 主召唤物：血量 / 被治疗 / 击倒后复活
	var summon_unit: Node2D = GameManager.Summoner.get_node("summing_one")
	check(summon_unit.max_hp >= 100.0 and is_equal_approx(summon_unit.hp, summon_unit.max_hp), "主召唤物有血量")
	summon_unit._take_damage(30.0)
	check(summon_unit.hp < summon_unit.max_hp, "主召唤物会受伤")
	summon_unit._heal(9999.0)
	check(is_equal_approx(summon_unit.hp, summon_unit.max_hp), "主召唤物能被治疗")
	summon_unit._take_damage(9999.0)
	check(not summon_unit.is_alive(), "主召唤物会被击倒")
	summon_unit._physics_process(4.5)
	check(summon_unit.is_alive() and is_equal_approx(summon_unit.hp, summon_unit.max_hp), "主召唤物 4 秒后满血复活")
	await get_tree().process_frame

	# 召唤物被治疗也会生成治疗粒子
	ParticleDirector.reset()
	summon_unit.hp = 10.0
	summon_unit._heal(20.0)
	await get_tree().process_frame
	var summon_heal_fx: Node = _find_by_script_suffix(battle, "heal_burst.gd")
	check(summon_heal_fx != null, "召唤物被治疗时生成治疗粒子")
	await get_tree().create_timer(1.2).timeout
	ParticleDirector.reset()
	await get_tree().process_frame

	# 18 负向幻觉：随机传送/抹除 + 幻象闪动
	GameManager._reward_detect(18)
	var target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(target)
	target.global_position = Vector2(400.0, 700.0)
	await get_tree().process_frame
	manager._hallucination_timer = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	var moved_or_erased := (not is_instance_valid(target)) or target.global_position.y < 400.0
	check(moved_or_erased, "奖励18 敌人被传送或抹除")
	var fx: Node = _find_by_script_suffix(battle, "unnameable_hole.gd")
	check(fx != null, "奖励18 生成了幻象表现")
	await _dismiss_reward_panel()

	# 召唤师专属：永葬秘法（从裂隙位置连射飞刀）
	GameManager._reward_detect(21)
	check(GameManager.weapon_owned, "召唤师也能拿到原初飞刀")
	check(GameManager.Rewards_pool.has(28), "永葬秘法进入召唤师奖励池")
	GameManager._reward_detect(28)
	check(GameManager.weapon_summoner_burial, "永葬秘法已解锁")
	manager._burial_timer = 0.0
	manager._tick_burial(0.016)
	check(manager._burial_left > 0.0, "永葬秘法进入 3 秒连射")
	for i in 5:
		manager._tick_burial(0.05)
	await get_tree().process_frame
	var burial_knives := 0
	for child in battle.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("knife_projectile.gd"):
			burial_knives += 1
	check(burial_knives >= 3, "裂隙位置连续投出飞刀（%d 把）" % burial_knives)
	for child in battle.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("knife_projectile.gd"):
			child.queue_free()
	# 粒子名额紧张时：优先给离玩家最近的召唤物
	ParticleDirector.reset()
	for old in get_tree().get_nodes_in_group("summon_minions"):
		old.queue_free()
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("character") as Node2D
	var main_unit := GameManager.Summoner.get_node("summing_one") as Node2D
	main_unit.global_position = Vector2(620.0, 240.0)
	var minion_scene: PackedScene = load("res://Scene/Character/weapon/summon_minion.tscn")
	var near_ally: Node2D = minion_scene.instantiate()
	var far_ally: Node2D = minion_scene.instantiate()
	battle.add_child(near_ally)
	battle.add_child(far_ally)
	near_ally.global_position = player.global_position + Vector2(60.0, 0.0)
	far_ally.global_position = player.global_position + Vector2(460.0, 0.0)
	near_ally.hp = 10.0
	far_ally.hp = 10.0
	ParticleDirector.set("_cap", 1)
	manager._heal_allies()
	await get_tree().process_frame
	var near_fx: Node = null
	var far_fx: Node = null
	for child in battle.get_children():
		var script: Script = child.get_script()
		if script == null or not str(script.resource_path).ends_with("heal_burst.gd"):
			continue
		var spot: Vector2 = (child as Node2D).global_position
		if spot.distance_to(near_ally.global_position) < 20.0:
			near_fx = child
		elif spot.distance_to(far_ally.global_position) < 20.0:
			far_fx = child
	check(near_fx != null, "名额紧张时优先给离玩家最近的召唤物")
	check(far_fx == null, "名额用完后远处的召唤物分不到粒子")
	ParticleDirector.reset()
	near_ally.queue_free()
	far_ally.queue_free()
	await get_tree().process_frame


# --- 伤害 / 治疗分离 --------------------------------------------------------

func _test_damage_heal() -> void:
	var slime: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(slime)
	slime.global_position = Vector2(200.0, 500.0)
	await get_tree().process_frame
	check(is_equal_approx(slime.HP, 100.0) and is_equal_approx(slime.Max_HP, 100.0), "史莱姆初始 100/100")

	slime.defense = 0.0  # 本用例只验证伤害/治疗分离，先排除防御减免
	slime._Damage(30.0)
	check(is_equal_approx(slime.HP, 70.0), "伤害只走 _Damage")

	slime._Heal(50.0)
	check(is_equal_approx(slime.HP, 100.0), "治疗不超过当前上限")
	check(is_equal_approx(slime.Max_HP, 100.0), "普通治疗不改 Max_HP")

	slime._Heal(50.0, true)
	check(is_equal_approx(slime.Max_HP, 150.0), "raise_max 治疗抬高上限")
	check(is_equal_approx(slime.HP, 150.0), "raise_max 治疗同时回血")

	var label: Label = slime.get_node("Show_HP")
	check(label.text == "150", "血量文本跟随治疗刷新（%s）" % label.text)
	slime.queue_free()
	await get_tree().process_frame


# --- 结算与存档 -------------------------------------------------------------

func _test_game_over_and_record() -> void:
	var panel: Control = battle.get_node_or_null("Overlay/GameOverPanel")
	check(panel != null, "战斗场景带了结算界面")
	check(panel != null and not panel.visible, "未结束时不显示结算")

	GameManager.Wall_Health = 1
	GameManager.kill_count = 7
	GameManager.in_run = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameManager.run_time > 0.0, "存活时间在累计")
	GameManager._BeDamaged(5)
	check(GameManager.is_game_over, "城墙归零触发结算")
	check(get_tree().paused, "结算时暂停游戏")
	check(panel != null and panel.visible, "结算界面已显示")
	if panel != null:
		var record_text: String = panel.get_node("Panel/Margin/VBox/Record").text
		check(not record_text.is_empty(), "结算显示记录文案（%s）" % record_text)
		check(panel.get_node("Panel/Margin/VBox/StatInfo").text.contains("7"), "结算显示击杀数")
		var time_text: String = panel.get_node("Panel/Margin/VBox/StatTime").text
		check(time_text.contains(":"), "结算显示存活时间（%s）" % time_text)

	check(FileAccess.file_exists("user://save.cfg"), "最高记录已写盘")
	var config := ConfigFile.new()
	check(config.load("user://save.cfg") == OK, "存档可读")
	check(int(config.get_value("record", "best_kills", -1)) == 7, "存档记录击杀数")
	check(GameManager.best_record_text() != "最高记录：暂无", "主界面记录文案可用")

	var paused_before: bool = get_tree().paused
	GameManager._reset_run()
	check(not GameManager.is_game_over, "重开后清除结算状态")
	check(GameManager.Wall_Health == 10, "重开后城墙满血")
	check(GameManager.level == 0 and is_equal_approx(GameManager.Exp_cur, 0.0), "重开后等级/经验归零")
	check(GameManager.Rewards_pool.is_empty(), "重开后奖励池清空")
	check(not get_tree().paused, "重开后解除暂停")
	check(not GameManager.weapon_owned and GameManager.weapon_node == null, "重开后武器状态清空")
	print("     (结算前 paused=%s, 重开后 paused=%s)" % [paused_before, get_tree().paused])

	# 测试写入的存档删掉，别污染玩家记录
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	check(not FileAccess.file_exists("user://save.cfg"), "测试存档已清理")
