extends Health
class_name EnemyHealth

# =========================
# Signals
# =========================
signal request_evade   # База просит владельца выполнить уклонение/эвейд

# =========================
# Tunables
# =========================
@export var hp_override: int = -1            # Быстрый тест: можно выставить HP в инспекторе
@export var hits_before_evade: int = 3       # После скольких попаданий просить эвейд

# =========================
# Refs
# =========================
var actor: Node3D                             # Нейтральный владелец (любой враг)
@onready var HpBase: Health = get_node_or_null("HpBase") as Health

# =========================
# State
# =========================
var _hits_taken: int = 0

# =========================
# Lifecycle
# =========================
func _ready() -> void:
	# Этот компонент — вражеский: задаём команду и зовём базовую инициализацию
	team = &"enemy"
	super._ready()

	# Ссылка на владельца (ожидаем, что EnemyHealth — прямой ребёнок врага)
	actor = get_parent() as Node3D

	# Переопределение HP для тестов
	if hp_override > 0:
		set_max_health(hp_override)
		set_current_health(hp_override)

	# Проксируем события из дочернего HpBase наверх
	if HpBase != null:
		if HpBase.has_signal("damaged_event") and not HpBase.damaged_event.is_connected(_on_base_damaged_event):
			HpBase.damaged_event.connect(_on_base_damaged_event)
		if HpBase.has_signal("died") and not HpBase.died.is_connected(_on_base_died):
			HpBase.died.connect(_on_base_died)

	# ВАЖНО: больше не коннектим собственный died к приватным методам конкретного врага.
	# Конкретика (например, EnemyCossack) сама подпишется на сигнал died/request_evade по месту.

# =========================
# Public API
# =========================
func apply_damage(dmg: DamageEvent) -> int:
	# Обрабатываем урон через базовый Health
	var applied: int = super.apply_damage(dmg)
	if applied > 0:
		_hits_taken += 1

		# Триггер «эвейда» после N попаданий (без навязывания конкретного класса владельца)
		if hits_before_evade > 0 and _hits_taken >= hits_before_evade:
			_hits_taken = 0
			# 1) Предпочтительно — сигнал: владелец решает сам, что делать
			emit_signal("request_evade")
			# 2) Мягкий фолбэк на старое поведение — если у владельца есть такой метод
			if actor != null and actor.has_method("force_evade"):
				actor.force_evade()

	return applied

# =========================
# Proxies from HpBase
# =========================
func _on_base_damaged_event(dmg: DamageEvent, applied: int) -> void:
	emit_signal("damaged_event", dmg, applied)

func _on_base_died() -> void:
	emit_signal("died")
