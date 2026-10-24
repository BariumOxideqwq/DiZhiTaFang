extends Resource
class_name WeaponInfo

# ---------------------------------------------------------------------------
# 通用武器定义（数据驱动）
# 角色拿到武器后：把武器节点挂到角色身上，并把这条武器对应的
# 基础升级 / 技能 / 职业专属奖励条目追加进奖励池。
# 以后加新武器 = 做一个新的 WeaponInfo + 武器场景，再在奖励表里补词条。
# ---------------------------------------------------------------------------

@export var id: StringName = &"weapon"
@export var weapon_name: String = "武器"
@export_multiline var context: String = ""

## 武器节点场景（挂在角色身上，负责显示与开火）
@export var scene: PackedScene

## 奖励表里“获得该武器”的条目 id
@export var reward_acquire: int = -1

## 基础升级条目（攻击 / 攻速……）
@export var reward_upgrades: Array[int] = []

## 技能条目
@export var reward_skills: Array[int] = []

## 职业专属额外奖励：{ 角色编号(0弓/1法/2召): 奖励条目 id }
@export var reward_class_extras: Dictionary = {}
