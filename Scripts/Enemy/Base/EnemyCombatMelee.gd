extends Node
class_name EnemyCombatMelee

# ========================= # Const / Tunables # =========================
const MIN_COOLDOWN: float = 0.10     # нижний предел отката после удара
const COOLDOWN_K: float = 0.20       # доля от длины клипа на откат

# Refs (устанавливаются в setup)

var actor: Node3D                     # владелец (любой враг)
var anim: EnemyAnimation              # универсальный аниматор
var locomotion: EnemyLocomotion       # опционально найдём по ноде "Locomotion"

# State

var _next: int = 1                    # 1/2 — чередование атак
var _active: bool = false             # флаг «атака идёт»
var _cooldown: float = 0.0            # текущий откат

# ========================= # Lifecycle # =========================
func setup(_actor: Node3D, _anim: EnemyAnimation) -> void:
	# Было: EnemyCossack → теперь нейтральный Node3D
	actor = _actor
	anim = _anim
	# Пытаемся найти локомоушен по стандартному имени ноды (не обязательно)
	locomotion = actor.get_node_or_null("Locomotion") as EnemyLocomotion
	set_physics_process(true)

func _physics_process(dt: float) -> void:
	if _cooldown > 0.0:
		_cooldown = max(0.0, _cooldown - dt)

# ========================= # Public API # =========================
func start_attack_cycle() -> void:
	if _cooldown > 0.0 or _active:
		return
	_active = true
	if _next == 1:
		anim.play_attack1()
		_next = 2
	else:
		anim.play_attack2()
		_next = 1

func end_attack(length: float) -> void:
	_active = false
	close_hitbox()
	_cooldown = max(MIN_COOLDOWN, length * COOLDOWN_K)

func is_finished() -> bool:
	return not _active

# ========================= # Animation Callbacks (Call Method Track) # =========================
func open_hitbox() -> void:
	var hb := actor.get_node_or_null("Hitbox") as Area3D
	if hb == null:
		return

	# Поворот хитбокса по текущему фейсу — через универсальный аниматор,
	# чтобы не требовать поля actor.Anim у владельца.
	var dir := 1
	if anim != null and anim.sprite != null:
		dir = (1 if anim.sprite.flip_h else -1)

	var hb3 := hb as Node3D
	var p := hb3.position
	p.x = abs(p.x) * float(dir)
	hb3.position = p

	# Включаем мониторинг. (Срабатывание коллизий начнётся на ближайшем физ. тике.)
	hb.set_deferred("monitoring", true)

func close_hitbox() -> void:
	var hb := actor.get_node_or_null("Hitbox") as Area3D
	if hb:
		hb.set_deferred("monitoring", false)

func nudge_forward() -> void:
	# Мягкая зависимость: если есть компонент Locomotion — используем его толчок
	if locomotion != null and locomotion.has_method("nudge_forward"):
		locomotion.nudge_forward()
