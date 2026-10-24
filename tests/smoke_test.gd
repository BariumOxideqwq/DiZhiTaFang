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

	var damage_before: float = GameManager.Bow.damage
	GameManager._reward_detect(1)
	check(is_equal_approx(GameManager.Bow.damage, damage_before + 10.0), "奖励1 提升箭矢伤害 +10")

	# 19 淬锋之矢：流血层数与持续伤害
	GameManager._reward_detect(19)
	check(GameManager.archer_bleed_level == 1, "奖励19 解锁流血")
	check(is_equal_approx(GameManager.archer_bleed_dps, 2.0), "奖励19 流血强度 2/s/层")
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
	check(GameManager.Rewards_pool.has(22) and GameManager.Rewards_pool.has(23), "武器基础升级进池")
	check(GameManager.Rewards_pool.has(24) and GameManager.Rewards_pool.has(25), "武器技能进池")
	check(GameManager.Rewards_pool.has(26), "弓箭手专属奖励进池")
	check(not GameManager.reward_is_available(21), "拿到武器后不再刷“获得武器”")

	# 基础升级
	var knife: Node2D = GameManager.weapon_node
	var drop_attack_before: float = knife.get("damage")
	GameManager._reward_detect(22)
	check(is_equal_approx(float(knife.get("damage")), drop_attack_before + 15.0), "利刃：飞刀伤害 +15")
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

	# 飞刀命中：普通伤害 + 最大生命百分比
	var target: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(target)
	target.global_position = Vector2(400.0, 820.0)
	target.Max_HP = 1000.0
	target.HP = 1000.0
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
	check(is_equal_approx(unit.damage, 5.0), "召唤物基础伤害 5")
	check(GameManager.Rewards_pool.has(14), "召唤师池子里有「提升召唤物伤害」")
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

	GameManager._reward_detect(14)
	check(is_equal_approx(unit.damage, 10.0), "奖励14 召唤物伤害 +5")

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
	check(minion.max_hp > 0.0 and is_equal_approx(minion.hp, minion.max_hp), "临时单位有血量")
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
	check(attacker.global_position.distance_to(attacker_pos) < 1.0, "被召唤单位缠住的敌人会停下")
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
	await get_tree().process_frame


# --- 伤害 / 治疗分离 --------------------------------------------------------

func _test_damage_heal() -> void:
	var slime: Node2D = load("res://Scene/Enemy/slime.tscn").instantiate()
	battle.add_child(slime)
	slime.global_position = Vector2(200.0, 500.0)
	await get_tree().process_frame
	check(is_equal_approx(slime.HP, 100.0) and is_equal_approx(slime.Max_HP, 100.0), "史莱姆初始 100/100")

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
