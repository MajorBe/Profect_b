extends Node
class_name EnemyActivationLOD

signal lod_changed(state: int)                # 0=OFF, 1=IDLE, 2=ACTIVE
signal rest_mode_changed(on: bool)            # true — вошли в «отдых», false — вышли

enum LOD { OFF, IDLE, ACTIVE }

@export var recheck_interval: float = 0.15
@export var force_active: bool = false
@export var use_anchor_model: bool = true

# Режим «отдых на дальнем расстоянии» (порог берём из Anchor или оверрайда)
@export var rest_idle_radius_override: float = -1.0  # < 0 — брать из EnemyAnchor.forget_radius
@export var rest_hysteresis: float = 1.0             # зазор выхода из отдыха
@export var debug_logs: bool = false

var _owner: Node3D
var _perception: EnemyPerception
var _on_screen: VisibleOnScreenNotifier3D
var _player: Node3D
var _cfg: EnemyConfig

var _state: int = LOD.IDLE
var _accum: float = 0.0
var _rest_mode: bool = false

func _ready() -> void:
	_owner = get_parent() as Node3D
	_perception = _owner.get_node_or_null("Perception") as EnemyPerception
	_on_screen = _owner.get_node_or_null("VisibleOnScreenNotifier3D")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_cfg = _owner.get("config") as EnemyConfig
	_state = LOD.IDLE
	_set_meta_lod(false)
	set_physics_process(true)

	# Просыпаемся мгновенно, если персепшн увидел игрока
	if _perception and _perception.has_signal("seen_player"):
		_perception.seen_player.connect(func(_pos: Vector3) -> void:
			if _rest_mode:
				_rest_mode = false
				_apply_rest_mode(false)
			_set_state(LOD.ACTIVE)
		)

func _physics_process(dt: float) -> void:
	_accum += dt
	if _accum < recheck_interval:
		return
	_accum = 0.0
	_update_lod()

func _update_lod() -> void:
	if force_active:
		if _rest_mode:
			_rest_mode = false
			_apply_rest_mode(false)
		_set_state(LOD.ACTIVE)
		return

	# --- Расстояние только по X (2.5D) ---
	var d_x: float = INF
	if _player != null and is_instance_valid(_player):
		d_x = absf(_owner.global_position.x - _player.global_position.x)

	# --- Порог «отдыха» (из Anchor либо из override) + гистерезис ---
	var rest_r: float = _get_rest_radius_from_anchor_or_override()
	var enter_rest: bool = (d_x >= rest_r)
	var exit_rest: bool = (d_x <= maxf(0.0, rest_r - maxf(0.0, rest_hysteresis)))

	var prev_rest: bool = _rest_mode
	if _rest_mode:
		if exit_rest:
			_rest_mode = false
	else:
		if enter_rest:
			_rest_mode = true
	if _rest_mode != prev_rest:
		_apply_rest_mode(_rest_mode)
		rest_mode_changed.emit(_rest_mode)

	# В «отдыхе» держим IDLE и не идём дальше
	if _rest_mode:
		_set_state(LOD.IDLE)
		return

	# --- Остальная логика активности ---
	# Если уже вовлечён в бой — активны
	var engaged: bool = (_perception != null) and bool(_perception.has_target)
	if engaged:
		_set_state(LOD.ACTIVE)
		return

	# «Рядом» — near_range как есть
	var near_active_r: float = 8.0
	if _perception != null:
		near_active_r = float(_perception.near_range)
	var near_player: bool = d_x <= near_active_r

	# На экране? Если нет нотайфера — считаем видимым (не глушим на глазах)
	var on_screen_now: bool = true
	if _on_screen != null:
		on_screen_now = _on_screen.is_on_screen()

	# Активны, если видно или рядом; иначе idle
	if on_screen_now or near_player:
		_set_state(LOD.ACTIVE)
	else:
		_set_state(LOD.IDLE)

func _get_rest_radius_from_anchor_or_override() -> float:
	if rest_idle_radius_override > 0.0:
		return rest_idle_radius_override
	var parent_anchor: EnemyAnchor = _owner.get_parent() as EnemyAnchor
	if parent_anchor != null:
		return float(parent_anchor.forget_radius)
	return 60.0

func _set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	_set_meta_lod(_state == LOD.ACTIVE)
	_apply_lod()
	lod_changed.emit(_state)

func _set_meta_lod(active: bool) -> void:
	_owner.set_meta("lod_is_active", active)

func _apply_lod() -> void:
	var agent: NavigationAgent3D = _owner.get_node_or_null("Body/NavigationAgent3D") as NavigationAgent3D
	var combat: Node = _owner.get_node_or_null("Combat") as Node

	match _state:
		LOD.OFF:
			if agent: agent.enabled = false
			if _perception: _perception.set_physics_process(false)
			if combat: combat.set_process(false)
			_force_idle_patrol()
		LOD.IDLE:
			if agent: agent.enabled = false
			if _perception: _perception.set_physics_process(true)
			if combat: combat.set_process(false)
			_force_idle_patrol()
		LOD.ACTIVE:
			if agent: agent.enabled = true
			if _perception: _perception.set_physics_process(true)
			if combat: combat.set_process(true)

func _apply_rest_mode(on: bool) -> void:
	# Заморозка движения и навигации
	var body: CharacterBody3D = _owner.get_node_or_null("Body") as CharacterBody3D
	var agent: NavigationAgent3D = _owner.get_node_or_null("Body/NavigationAgent3D") as NavigationAgent3D
	if on:
		if agent: agent.enabled = false
		if body: body.velocity.x = 0.0
		# чуть повернёмся к игроку, чтобы не стоять «задом»
		if _player and is_instance_valid(_player) and _owner.has_method("set_facing_dir"):
			var dir := signf(_player.global_position.x - _owner.global_position.x)
			_owner.set_facing_dir(int(dir))
		# мягко в Idle (если есть обёртка анимаций)
		var anim_node: Node = _owner.get_node_or_null("Animation")
		if anim_node and anim_node.has_method("play_idle"):
			anim_node.call("play_idle")
	else:
		if agent: agent.enabled = true

func _force_idle_patrol() -> void:
	if _owner == null:
		return
	var st: Object = null
	if _owner.has_method("get"):
		st = _owner.get("state")
	if st == null:
		return

	var ok_idle: bool = false
	if st.has_method("is_idle_like"):
		ok_idle = bool(st.call("is_idle_like"))
	else:
		ok_idle = (st is Cossack_01_IdleState) \
			or (st is Cossack_01_ApproachState) \
			or (st is Cossack_01_PatrolState) \
			or (st is Cossack_01_JumpState) \
			or (st is Cossack_01_FallState)

	if not ok_idle:
		if _owner.has_method("change_state_by_name"):
			_owner.call("change_state_by_name", "Patrol")
		elif _owner.has_signal("request_state_change"):
			_owner.emit_signal("request_state_change", "Patrol")

func get_lod_state() -> int:
	return _state
