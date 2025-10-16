extends Area3D
class_name DamagePoint

# --- Параметры удара ---
@export var amount: int = 1
@export var damage_type: StringName = &"hazard"
@export var tags_array: Array[StringName] = [&"hazard"]
@export var impulse_value: float = 0.0          # 0.0 = без нокбэка

# Владелец атаки (может быть null для нейтральной ловушки)
@export var instigator: Node

# Тики урона, пока цель находится внутри зоны
@export var tick_sec: float = 0.15              # наносим урон каждые tick_sec секунд
@export var respect_iframes: bool = false       # false = пробиваем i-frames (но слайд/ролл игрока блокируют)

# Кого бьём
@export var hit_bodies: bool = true
@export var hit_areas: bool = false

# Внутренняя таблица: victim(Node) -> время до следующего тика
var _victims: Dictionary = {}

func _ready() -> void:
	monitoring = true
	monitorable = true

	if hit_bodies and not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if hit_areas and not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if hit_bodies and not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if hit_areas and not area_exited.is_connected(_on_area_exited):
		area_exited.connect(_on_area_exited)

func _process(delta: float) -> void:
	# Обновляем таймеры тиков
	for k in _victims.keys():
		_victims[k] = float(_victims[k]) - delta

	var to_tick: Array = []
	for k in _victims.keys():
		if float(_victims[k]) <= 0.0:
			to_tick.append(k)

	for v in to_tick:
		_apply_tick(v)
		_victims[v] = tick_sec

func _on_body_entered(body: Node) -> void:
	_add_victim(body)

func _on_area_entered(ar: Area3D) -> void:
	var victim: Node = ar.get_parent() if ar.get_parent() != null else ar
	_add_victim(victim)

func _on_body_exited(body: Node) -> void:
	_victims.erase(body)

func _on_area_exited(ar: Area3D) -> void:
	var victim: Node = ar.get_parent() if ar.get_parent() != null else ar
	_victims.erase(victim)

func _add_victim(victim: Node) -> void:
	if victim == null:
		return
	# КЛЮЧ: если уже внутри — не дублируем (фикс двойных хитов в один кадр)
	if _victims.has(victim):
		return
	# Наносим урон сразу при входе и заводим таймер на следующий тик
	_apply_tick(victim)
	_victims[victim] = tick_sec

func _apply_tick(target: Node) -> void:
	if target == null:
		return

	var dmg := DamageEvent.new()
	dmg.amount = amount
	dmg.type = damage_type
	dmg.tags = tags_array.duplicate()
	dmg.source = self
	dmg.instigator = instigator
	dmg.origin = global_transform.origin

	# Направление только по X с мёртвой зоной, чтобы не «дёргало»
	var dx: float = target.global_transform.origin.x - global_transform.origin.x
	var dir_x: float = 0.0
	if dx > 0.1:
		dir_x = 1.0
	elif dx < -0.1:
		dir_x = -1.0
	dmg.direction = Vector3(dir_x, 0.0, 0.0)

	dmg.impulse = impulse_value
	dmg.bypass_iframes = not respect_iframes

	# КЛЮЧ: один источник = один hit_id → Health отфильтрует дубли «в этот же момент»
	dmg.hit_id = self.get_instance_id()

	# Унифицированное нанесение урона
	if target.has_node("Health"):
		var h: Node = target.get_node("Health")
		if h != null and h.has_method("apply_damage"):
			h.apply_damage(dmg)
			return

	# Fallback (на всякий случай)
	if target.has_method("damage"):
		target.damage(dmg.amount, dmg.origin)
	elif target.has_method("take_damage"):
		target.take_damage(dmg.amount, dmg.origin)
