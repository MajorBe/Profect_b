extends Resource
class_name DamageEvent

@export var amount: int = 1
@export var type: StringName = &"slash"
@export var tags: Array[StringName] = []

var source: Node = null        # кто нанёс хит (сабля/хитбокс)
var instigator: Node = null    # владелец атаки (Player/Enemy)

@export var origin: Vector3 = Vector3.ZERO
@export var direction: Vector3 = Vector3.ZERO
@export var impulse: float = 0.0
@export var poise: float = 0.0
@export var crit: bool = false
@export var pierce_armor: bool = false
@export var hit_id: int = 0
@export var bypass_iframes: bool = false
