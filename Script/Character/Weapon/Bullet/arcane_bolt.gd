extends Area2D

# 魔力解构：凝聚魔力 → 朝前方丢出一颗巨大的奥术魔弹。
#   * 先原地蓄力放大 0.35s，然后直线飞行
#   * 命中造成大量伤害，并降低命中单位的防御
#   * 巨大弹体穿透敌人（碰到多个都会结算）

const CHARGE_TIME := 0.35
const LIFETIME := 2.4

var damage := 80.0
var defense_down := 0.3
var defense_down_time := 5.0
var speed := 520.0
var penetrable := true

var _moving := false
var _age := 0.0


func setup(level: int) -> void:
	var lv := maxi(level, 1)
	# 统一伤害：奥术魔弹伤害由角色攻击力派生
	damage = GameManager.dmg_arcane()
	defense_down = clampf(0.20 + 0.10 * float(lv), 0.0, 0.75)
	defense_down_time = 4.0 + float(lv)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	scale = Vector2(0.25, 0.25)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), CHARGE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_start_move)


func _start_move() -> void:
	_moving = true


func _physics_process(delta: float) -> void:
	if not _moving:
		return
	global_position += Vector2.UP.rotated(rotation) * speed * delta
	_age += delta
	if _age >= LIFETIME:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not _moving:
		return
	if body.has_method("_Damage"):
		body._Damage(damage)
		if body.has_method("_lower_defense"):
			body._lower_defense(defense_down, defense_down_time)
	if not penetrable:
		queue_free()
