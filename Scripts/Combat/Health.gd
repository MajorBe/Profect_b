extends Node
class_name Health

# --- Сигналы ---
signal damaged_event(dmg: DamageEvent, applied: int)
signal died
signal health_changed(current: int, max: int)
signal damaged(amount: int, from: Vector3)  # совместимость

# --- Параметры ---
@export var max_health: int = 100
@export var team: StringName = &"neutral"      # "player" | "enemy" | "boss" | "neutral"
@export var base_armor: int = 0                # плоская броня
@export var resist: Dictionary = {}            # {"fire":0.5, "ice":1.2}

# --- Runtime ---
var current_health: int
var _recent_hits: Dictionary = {}              # hit_id -> ttl (float, сек)

func _ready() -> void:
	current_health = max(max_health, 1)
	emit_signal("health_changed", current_health, max_health)

func _process(delta: float) -> void:
	# уменьшить TTL для всех записей
	for k in _recent_hits.keys():
		_recent_hits[k] = float(_recent_hits[k]) - delta

	# собрать ключи на удаление
	var to_erase: Array = []
	for k in _recent_hits.keys():
		if float(_recent_hits[k]) <= 0.0:
			to_erase.append(k)
	for k in to_erase:
		_recent_hits.erase(k)

# --- Утилиты состояния ---
func is_dead() -> bool:
	return current_health <= 0

func is_full() -> bool:
	return current_health >= max_health

# --- Настройки здоровья ---
func set_max_health(val: int) -> void:
	max_health = max(1, val)
	current_health = clamp(current_health, 0, max_health)
	emit_signal("health_changed", current_health, max_health)

func set_current_health(val: int) -> void:
	var new_val: int = clamp(val, 0, max_health)
	if new_val == current_health:
		return
	current_health = new_val
	emit_signal("health_changed", current_health, max_health)
	if current_health <= 0:
		emit_signal("died")

func heal(amount: int) -> void:
	if amount <= 0 or current_health <= 0 or current_health >= max_health:
		return
	current_health = min(current_health + amount, max_health)
	emit_signal("health_changed", current_health, max_health)

func reset_health() -> void:
	current_health = max_health
	emit_signal("health_changed", current_health, max_health)

# --- Команды и дружеский огонь ---
func _same_team(a: StringName, b: StringName) -> bool:
	return a == b

func _instigator_team(dmg: DamageEvent) -> StringName:
	if dmg == null or dmg.instigator == null:
		return &""
	if not dmg.instigator.has_node("Health"):
		return &""
	var h: Health = dmg.instigator.get_node("Health") as Health
	if h == null:
		return &""
	return h.team

# --- Расчёт итогового урона ---
func _final_amount(dmg: DamageEvent) -> int:
	var v: int = max(dmg.amount, 0)
	if not dmg.pierce_armor:
		v = max(v - base_armor, 0)
		if resist.has(dmg.type):
			var mul_val: float = float(resist[dmg.type])
			v = int(round(float(v) * mul_val))
	return v

# --- Главный вход урона ---
func apply_damage(dmg: DamageEvent) -> int:
	# 0) дедуп мультихита
	if dmg.hit_id != 0:
		if _recent_hits.has(dmg.hit_id):
			return 0
		_recent_hits[dmg.hit_id] = 0.1  # сек

	# 1) гейткепы
	if current_health <= 0:
		return 0

	# 2) friendly-fire off
	var inst_team: StringName = _instigator_team(dmg)
	if inst_team != &"" and _same_team(inst_team, team):
		return 0

	# 3) расчёт и применение
	var applied: int = _final_amount(dmg)
	if applied <= 0:
		return 0

	var prev: int = current_health
	current_health = max(current_health - applied, 0)

	emit_signal("damaged_event", dmg, applied)
	emit_signal("damaged", applied, dmg.origin)          # совместимость
	emit_signal("health_changed", current_health, max_health)

	# 4) нокбэк, если цель умеет
	if applied > 0 and dmg.impulse != 0.0:
		var host: Node = get_parent()
		if host != null and host.has_method("on_damage_knockback"):
			host.on_damage_knockback(dmg.direction, dmg.impulse)

	# 5) смерть
	if prev > 0 and current_health == 0:
		emit_signal("died")
		var host2: Node = get_parent()
		if host2 != null and host2.has_method("on_death"):
			host2.on_death()

	return applied

# --- Обратная совместимость: старые вызовы ---
func take_damage(amount: int, from: Vector3) -> void:
	if amount <= 0:
		return
	var d: DamageEvent = DamageEvent.new()
	d.amount = amount
	d.origin = from
	apply_damage(d)

func damage(amount: int, from: Vector3) -> void:
	take_damage(amount, from)
