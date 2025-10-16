extends Health
class_name PlayerHealth

@export var slide_iframes: bool = true          # иммунитет во время слайда (условный, не i-frames)
@export var roll_iframes: bool = true           # иммунитет во время ролла (условный, не i-frames)
@export var per_source_grace: float = 0.2       # анти-дубль: пауза для одного источника удара (сабля/хитбокс), сек

# анти-дубль: 1 хит за физический кадр
var _last_hit_frame: int = -1
# анти-дубль: краткая пауза по конкретному источнику (source.get_instance_id())
var _source_grace: Dictionary = {}  # int -> float (ttl)

func _ready() -> void:
	team = &"player"
	super._ready()

func _process(delta: float) -> void:
	# базовый дедуп по hit_id из Health
	super._process(delta)

	# тикаем локальные паузы по источникам
	var to_erase: Array = []
	for k in _source_grace.keys():
		_source_grace[k] = float(_source_grace[k]) - delta
		if float(_source_grace[k]) <= 0.0:
			to_erase.append(k)
	for k in to_erase:
		_source_grace.erase(k)

func apply_damage(dmg: DamageEvent) -> int:
	var host: Node = get_parent()

	# 1) условный иммунитет во время слайда/ролла (НЕ i-frames, а «стейтовая защита»)
	if host != null:
		if slide_iframes and host.has_method("is_sliding") and host.is_sliding():
			return 0
		if roll_iframes and host.has_method("is_rolling") and host.is_rolling():
			return 0

	# 2) анти-дубль: не более одного урона в один physics-кадр
	var frame: int = Engine.get_physics_frames()
	if _last_hit_frame == frame:
		return 0

	# 3) анти-дубль: короткий grace для одного и того же источника удара
	var sid: int = 0
	if dmg != null and dmg.source != null:
		sid = dmg.source.get_instance_id()
		if _source_grace.has(sid) and float(_source_grace[sid]) > 0.0:
			return 0

	# 4) базовая обработка (броня/резисты/friendly-fire/дедуп по hit_id), без i-frames
	var applied: int = super.apply_damage(dmg)

	# 5) пост-эффекты игрока и фиксация анти-дубля
	if applied > 0:
		_last_hit_frame = frame
		if per_source_grace > 0.0 and sid != 0:
			_source_grace[sid] = per_source_grace

	return applied
