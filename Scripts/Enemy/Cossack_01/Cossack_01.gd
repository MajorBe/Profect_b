extends Node3D
class_name EnemyCossack

# ========================= #   Exports / Debug # =========================
@export var facing_dir: int = -1
@export var debug_logs: bool = false

# Эвэйд-логика по попаданиям (локальная надстройка над базовым Health)
@export var evade_after_hits: int = 3
@export var hit_chain_reset_sec: float = 1.2

@export_category("AI / Chaos (overrides)")
@export var enable_approach_chaos: bool = true

# --- OVERRIDES: если оставить -1, то берётся значение из EnemyConfig (базовое)
@export var chaos_pause_chance_override: float    = -1.0
@export var chaos_pause_min_override: float       = -1.0
@export var chaos_pause_max_override: float       = -1.0
@export var chaos_backstep_chance_override: float = -1.0
@export var chaos_backstep_dist_override: float   = -1.0
@export var chaos_backstep_steps_override: int    = -1
@export var chaos_backstep_step_time_override: float = -1.0
@export var chaos_decision_interval_override: float = 0.8
@export var chaos_idle_grace_override: float = 1.0

@export_group("Overrides / Distances (optional)")
@export_range(0.0, 5.0, 0.01) var attack_x_window_override: float = 1.0
@export_range(0.0, 5.0, 0.01) var attack_z_window_override: float = 0.30
@export_range(0.0, 5.0, 0.01) var approach_stop_x_override: float = 0.5
@export_range(0.0, 5.0, 0.01) var approach_x_window_override: float = 0.10

#   Refs (узлы/компоненты)

var Body: CharacterBody3D
var Anim: EnemyAnimation
var Perception: EnemyPerception
var Locomotion: EnemyLocomotion
@onready var HealthNode: EnemyHealth = get_node_or_null("Health") as EnemyHealth

#   FSM

var state: EnemyState
var _pending_state: EnemyState = null          # отложенная/безопасная смена
var _switching_now: bool = false

#   Visual follow plane

var _follow_nodes: Array[Node3D] = []
var _follow_offsets: Array[Vector3] = []
var _plane_z: float = 0.0

#   Evade / Hit-chain state

var EvadeCooldownLeft: float = 0.0
var _consecutive_hits: int = 0
var _last_hit_ms: int = -1

#   Chaos state

var _chaos_idle_grace_left: float = 0.0
var _chaos_last_frame: int = -1
var _chaos_cached_target: Vector3 = Vector3.ZERO

var _chaos_rng := RandomNumberGenerator.new()
var _chaos_state: String = "idle"           # "idle" | "paused" | "backstep"
var _chaos_timer: float = 0.0
var _chaos_backstep_steps_left: int = 0
var _chaos_decision_cooldown: float = 0.90  # базовый, реальное берём через конфиг
var _chaos_decision_cd_left: float = 0.0

#  Константы Анимаций

const ST_IDLE     : StringName = &"idle"
const ST_PATROL   : StringName = &"patrol"
const ST_APPROACH : StringName = &"approach"
const ST_ATTACK   : StringName = &"attack"
const ST_EVADE    : StringName = &"evade"
const ST_JUMP     : StringName = &"jump"
const ST_FALL     : StringName = &"fall"
const ST_HITSTUN  : StringName = &"hitstun"
const ST_DEATH    : StringName = &"death"


# ========================= #   Ready # =========================
func _ready() -> void:
	# --- кэш узлов (безопасно) ---
	Body       = get_node_or_null("Body")            as CharacterBody3D
	Anim       = get_node_or_null("Anim")            as EnemyAnimation
	Perception = get_node_or_null("Perception")      as EnemyPerception
	Locomotion = get_node_or_null("Locomotion")      as EnemyLocomotion

	# --- плоскость и «следование визуалов» (если используется) ---
	if Body != null:
		_plane_z = Body.global_position.z
	else:
		_plane_z = global_position.z
	_follow_nodes.clear()
	_follow_offsets.clear()

	# --- направление взгляда по умолчанию ---
	if facing_dir != 0 and Anim != null and Anim.has_method("set_facing"):
		Anim.set_facing(facing_dir)

	# --- подписки на здоровье ---
	if HealthNode != null:
		if HealthNode.has_signal("damaged_event") and not HealthNode.damaged_event.is_connected(_on_health_damaged_event):
			HealthNode.damaged_event.connect(_on_health_damaged_event)
		if HealthNode.has_signal("died") and not HealthNode.died.is_connected(_on_health_died):
			HealthNode.died.connect(_on_health_died)
		if HealthNode.has_signal("request_evade") and not HealthNode.request_evade.is_connected(_on_health_request_evade):
			HealthNode.request_evade.connect(_on_health_request_evade)

	_chaos_rng.randomize()

	# --- стартовое состояние ---
	if state == null:
		state = Cossack_01_IdleState.new(self)
		if state.has_method("enter"):
			state.enter()

# ========================= #   Physics # =========================
func _physics_process(dt: float) -> void:
	# обновление активного стейта (строго один раз за кадр)
	var cur: EnemyState = state
	if cur:
		cur.update(dt)

	if EvadeCooldownLeft > 0.0:
		EvadeCooldownLeft = max(0.0, EvadeCooldownLeft - dt)

	# базовый шаг локомоушена
	if Locomotion:
		Locomotion.baseline_step()

	_sync_visual_to_body()

# ========================= #   Visual follow # =========================
func _collect_visuals_to_follow() -> void:
	_follow_nodes.clear()
	_follow_offsets.clear()
	if Body == null:
		return
	for child in get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		if n3 == Body:
			continue
		if child == Anim or child == Perception or child == Locomotion:
			continue
		_follow_nodes.append(n3)
		_follow_offsets.append(n3.global_position - Body.global_position)

func _sync_visual_to_body() -> void:
	if Body == null:
		return
	if _follow_nodes.is_empty():
		_collect_visuals_to_follow()
	for i in range(_follow_nodes.size()):
		var n: Node3D = _follow_nodes[i]
		if n and is_instance_valid(n):
			var pos: Vector3 = Body.global_position + _follow_offsets[i]
			pos.z = _plane_z
			n.global_position = pos

# ========================= #   FSM: безопасная смена # =========================

func _change_state(ns: EnemyState) -> void:
	if ns == null:
		return
	# Не пересоздаём тот же класс стейта
	if state != null and ns.get_script() != null and state.get_script() == ns.get_script():
		if debug_logs:
			var _same_p: String = String(ns.get_script().resource_path) if ns.get_script() != null else "<null>"
		return
	# Защита от реэнтранта
	if _switching_now:
		return

	_pending_state = ns
	# Меняем стейт deferred — вне текущего апдейта
	call_deferred("_apply_pending_state")

	# Сброс счётчиков при уходе в эвейд
	if ns is Cossack_01_EvadeState:
		_consecutive_hits = 0
		_last_hit_ms = -1

func _apply_pending_state() -> void:
	if _pending_state == null:
		return
	_switching_now = true
	if state != null:
		state.exit()
	state = _pending_state
	_pending_state = null
	if state != null:
		state.enter()
	_switching_now = false

# ========================= #   Адаптер для base: вход по имени # =========================

func change_state_by_name(state_key: StringName) -> void:
	var next: EnemyState = null
	match state_key:
		ST_IDLE:
			next = Cossack_01_IdleState.new(self)
		ST_PATROL:
			next = Cossack_01_PatrolState.new(self)
		ST_APPROACH:
			next = Cossack_01_ApproachState.new(self)
		ST_ATTACK:
			next = Cossack_01_AttackState.new(self)
		ST_EVADE:
			next = Cossack_01_EvadeState.new(self)
		ST_JUMP:
			next = Cossack_01_JumpState.new(self)
		ST_FALL:
			next = Cossack_01_FallState.new(self)
		ST_HITSTUN:
			next = Cossack_01_HitStunState.new(self)
		ST_DEATH:
			next = Cossack_01_DeathState.new(self)
		_:
			push_warning("Unknown state key: %s" % [String(state_key)])
			return

	_change_state(next)

# ========================= #   Прокси к анимации # =========================

func anim_play(anim_name: StringName, blend: float = 0.0, speed: float = 1.0, from_end: bool = false) -> void:
	if Anim:
		Anim.play(anim_name, blend, speed, from_end)

func anim_stop(reset: bool = false) -> void:
	if Anim:
		Anim.stop(reset)

func anim_is_playing(anim_name: StringName = &"") -> bool:
	return Anim != null and Anim.is_playing(anim_name)

func set_facing_dir(dir: int) -> void:
	dir = clamp(dir, -1, 1)
	if dir == 0 or dir == facing_dir:
		return
	facing_dir = dir
	if Anim:
		Anim.set_facing(facing_dir)

func get_anim_map() -> Dictionary:
	return {
		"idle":   "Cossack_01_Idle",
		"walk":   "Cossack_01_Walk",
		"attack1":"Cossack_01_Attack_1",
		"attack2":"Cossack_01_Attack_2",
		"hurt":   "Cossack_01_Hurt",
		"jump":   "Cossack_01_Jump",
		"fall":   "Cossack_01_Fall",
		"evade":  "Cossack_01_Evasion",
		"death":  "Cossack_01_Death",
	}

# ========================= #   Health handlers (сигналы) # =========================

func _on_health_damaged_event(dmg: DamageEvent, applied: int) -> void:
	if applied <= 0 or dmg == null:
		return
	# Не прерываем смерть
	if state is Cossack_01_DeathState:
		return

	# Обновим цепочку попаданий
	var now_ms: int = Time.get_ticks_msec()
	if _last_hit_ms < 0 or float(now_ms - _last_hit_ms) > hit_chain_reset_sec * 1000.0:
		_consecutive_hits = 0
	_last_hit_ms = now_ms
	_consecutive_hits += 1

	# Порог достигнут → эвейд
	if _consecutive_hits >= evade_after_hits:
		_consecutive_hits = 0
		_change_state(Cossack_01_EvadeState.new(self))
		return

	# Обычный хит-стан (либо обновляем текущий)
	if state == null or not (state is Cossack_01_HitStunState):
		var hs := Cossack_01_HitStunState.new(self)
		if hs.has_method("setup_hit"):
			hs.setup_hit(dmg, applied)
		_change_state(hs)
	else:
		var hs2 := state as Cossack_01_HitStunState
		if hs2 and hs2.has_method("refresh"):
			hs2.refresh(dmg, applied)

func _on_health_died() -> void:
	# Безопасно закрыть хитбоксы/атаки
	var cm := get_node_or_null("CombatMelee")
	if cm != null and cm.has_method("close_hitbox"):
		cm.close_hitbox()
	_change_state(Cossack_01_DeathState.new(self))

func _on_health_request_evade() -> void:
	# Не эвейдимся из смерти
	if state is Cossack_01_DeathState:
		return
	_change_state(Cossack_01_EvadeState.new(self))

# ========================= #   Совместимость/ручки (опц.) # =========================

# Старые имена, если где-то ещё дергаются:
func _on_hp_damaged(dmg: DamageEvent, applied: int) -> void:
	_on_health_damaged_event(dmg, applied)

func _on_hp_died() -> void:
	_on_health_died()

func _on_hp_death() -> void:
	# Гарантированно уводим ИИ в стейт смерти (если кто-то старый вызвал)
	_change_state(Cossack_01_DeathState.new(self))

func force_evade() -> void:
	if Locomotion != null and Locomotion.has_method("begin_evade"):
		Locomotion.begin_evade()

# ========================= #   Chaos: API # =========================
func get_chaotic_approach_target(player_pos: Vector3, default_stop_pos: Vector3, dt: float) -> Vector3:
	if not enable_approach_chaos:
		return default_stop_pos
	if chaos_pause_chance() <= 0.0 and chaos_backstep_chance() <= 0.0:
		return default_stop_pos

	var pf := Engine.get_physics_frames()
	if pf != _chaos_last_frame:
		_chaos_last_frame = pf
		_tick_chaos_once(dt, player_pos, default_stop_pos)

	return _chaos_cached_target

# ========================= #   Chaos: Tick # =========================
func _tick_chaos_once(dt: float, player_pos: Vector3, default_stop_pos: Vector3) -> void:
	_chaos_cached_target = default_stop_pos

	var decision_interval: float = chaos_decision_interval()
	_chaos_decision_cooldown = decision_interval

	var idle_grace_val: float = chaos_idle_grace()

	_chaos_decision_cd_left = max(0.0, _chaos_decision_cd_left - dt)
	_chaos_idle_grace_left  = max(0.0, _chaos_idle_grace_left - dt)

	var p_pause_dt: float = 1.0 - pow(1.0 - clamp(chaos_pause_chance(), 0.0, 1.0), dt)
	var p_back_dt:  float = 1.0 - pow(1.0 - clamp(chaos_backstep_chance(), 0.0, 1.0), dt)

	if _chaos_state == "idle" and _chaos_decision_cd_left <= 0.0 and _chaos_idle_grace_left <= 0.0:
		var r := _chaos_rng.randf()
		if r < p_pause_dt:
			_chaos_state = "paused"
			_chaos_timer = _chaos_rng.randf_range(chaos_pause_min(), chaos_pause_max())
			_chaos_decision_cd_left = _chaos_decision_cooldown
		elif r < p_pause_dt + p_back_dt:
			_chaos_state = "backstep"
			_chaos_backstep_steps_left = max(1, chaos_backstep_steps())
			_chaos_timer = chaos_backstep_step_time()
			_chaos_decision_cd_left = _chaos_decision_cooldown

	match _chaos_state:
		"paused":
			_chaos_timer -= dt
			if _chaos_timer <= 0.0:
				_chaos_state = "idle"
				_chaos_idle_grace_left = idle_grace_val
				_chaos_decision_cd_left = _chaos_decision_cooldown
			_chaos_cached_target = (Body.global_position if Body != null else default_stop_pos)

		"backstep":
			_chaos_timer -= dt
			if _chaos_timer <= 0.0:
				_chaos_backstep_steps_left -= 1
				if _chaos_backstep_steps_left > 0:
					_chaos_timer = chaos_backstep_step_time()
				else:
					_chaos_state = "idle"
					_chaos_idle_grace_left = idle_grace_val
					_chaos_decision_cd_left = _chaos_decision_cooldown

			var back_pos := default_stop_pos
			var to_player_x := player_pos.x - default_stop_pos.x
			var away_sign := -1.0 if to_player_x > 0.0 else 1.0
			back_pos.x += away_sign * chaos_backstep_dist()
			_chaos_cached_target = back_pos

		_:
			_chaos_cached_target = default_stop_pos

# ========================= #   Config helpers # =========================
func _get_config() -> Object:
	var c = get("config")
	if c != null:
		return c
	c = get("Config")
	if c != null:
		return c
	c = get("enemy_config")
	if c != null:
		return c
	if has_method("get_config"):
		var v = call("get_config")
		if v != null:
			return v
	return null

func _cfg_get(prop: String, fallback):
	var cfg = _get_config()
	if cfg != null:
		var v = cfg.get(prop)
		if v != null:
			return v
	return fallback

func _cfg_or_default_float(override_val: float, cfg_prop: String, fallback: float) -> float:
	if override_val >= 0.0: return override_val
	return float(_cfg_get(cfg_prop, fallback))

func _cfg_or_default_int(override_val: int, cfg_prop: String, fallback: int) -> int:
	if override_val >= 0: return override_val
	return int(_cfg_get(cfg_prop, fallback))

func chaos_pause_chance() -> float:
	return _cfg_or_default_float(chaos_pause_chance_override, "chaos_pause_chance_base", 0.12)
func chaos_pause_min() -> float:
	return _cfg_or_default_float(chaos_pause_min_override, "chaos_pause_min_base", 0.30)
func chaos_pause_max() -> float:
	return _cfg_or_default_float(chaos_pause_max_override, "chaos_pause_max_base", 0.90)
func chaos_backstep_chance() -> float:
	return _cfg_or_default_float(chaos_backstep_chance_override, "chaos_backstep_chance_base", 0.08)
func chaos_backstep_dist() -> float:
	return _cfg_or_default_float(chaos_backstep_dist_override, "chaos_backstep_dist_base", 0.25)
func chaos_backstep_steps() -> int:
	return _cfg_or_default_int(chaos_backstep_steps_override, "chaos_backstep_steps_base", 1)
func chaos_backstep_step_time() -> float:
	return _cfg_or_default_float(chaos_backstep_step_time_override, "chaos_backstep_step_time_base", 0.18)
func chaos_decision_interval() -> float:
	return _cfg_or_default_float(chaos_decision_interval_override, "chaos_decision_interval_base", 0.35)
func chaos_idle_grace() -> float:
	return _cfg_or_default_float(chaos_idle_grace_override, "chaos_idle_grace_base", chaos_decision_interval())
