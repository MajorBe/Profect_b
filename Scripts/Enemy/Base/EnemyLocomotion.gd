extends Node
class_name EnemyLocomotion

# =============================================================================
# ПАРАМЕТРЫ / КОНСТАНТЫ
# =============================================================================
@export_group("Wall / Hop")
@export var wall_forward_rays: Array[RayCast3D] = []
@export var wall_hop_cooldown: float = 0.25
var _last_wall_hop_time: float = -999.0

const FACE_EPS: float = 0.05
const ANIM_EPS: float = 0.03
const IDLE_THR: float = 0.03
const WALK_THR: float = 0.06
const IDLE_FACE_STICK_X: float = 0.18

const JUMP_REASON_NONE: int = 0
const JUMP_REASON_GAP:  int = 1
const JUMP_REASON_NEED: int = 2
const JUMP_REASON_CHASE:int = 3

@export var platform_layer_mask: int = 1 << 3
@export var ground_layer_mask:   int = 1 << 0

@export_group("Debug")
@export var debug_jump_ai: bool = true
@export var debug_force_jump_probe: bool = false
@export var debug_probe_period: float = 0.35
@export var debug_tick_period:  float = 1.0
@export var debug_verbose_probes: bool = false
@export var debug_probe_log_period: float = 0.35
@export var debug_gap_calc: bool = true

@export_group("Sensors / Gaps")
@export var gap_probe_forward: float = 0.25
@export var gap_probe_down: float = 1.20
@export var patrol_turn_forward: float = 0.60
@export var patrol_turn_down: float = 1.20

# Прыжок через яму только с кромки:
@export var edge_jump_trigger_forward: float = 0.22
@export var post_jump_edge_ignore: float = 0.35

@export_group("Gaps / Precision")
@export var treat_step_drop_as_gap: float = 0.40
@export var max_gap_scan_forward: float = 6.0
@export var gap_scan_step: float = 0.05
@export var min_gap_width_to_jump: float = 0.20

@export_group("Jump / Physics")
@export var jump_buffer: float = 0.12
@export var coyote_time: float = 0.10
@export var drop_duration: float = 0.30
@export var min_down_vel: float = -0.2
@export var zero_snap: bool = true
@export var fall_multiplier: float = 3.0
@export var drop_cooldown_sec: float = 0.40
@export var player_body_layer_bit: int = 2

@export_group("Jump Toggles")
@export var allow_upward_jumps: bool = true
@export var require_player_above_for_upward: bool = true
@export var allow_gap_jumps: bool = true
@export var allow_drop_down: bool = true
@export var env_probe_interval: float = 1.0

# Порог "слишком глубокого падения" как кратность высоты прыжка
@export var max_safe_drop_multiplier: float = 2.0

@export_group("Chase Policy")
@export var require_player_for_wall_hop: bool = true
@export var chase_jump_max_dist_x: float = 4.5
@export var chase_jump_min_dy: float = 0.20

# =============================================================================
# ССЫЛКИ / СОСТОЯНИЕ
# =============================================================================
var actor: Node3D
var body: CharacterBody3D
var cfg: EnemyConfig
var _anim: EnemyAnimation
var _perc: EnemyPerception
var _ahead: Node3D

var _hitboxes: Node3D
var _hitboxes_ok: bool = false
var _ahead_ok: bool = false

var _last_delta: float = 0.0
var _evade_left: float = 0.0
var _plane_z: float = 0.0
var _last_step_frame: int = -1
var _move_state: int = -1
var _last_facing: int = 0
var _pending_reason: int = JUMP_REASON_NONE

var _edge_hold_active: bool = false
var _edge_hold_dir: float = 0.0
var _edge_hold_run_v: float = 0.0
var _edge_snap_backup: float = 0.0
var _edge_hold_no_gap_t: float = 0.0

var _jump_buf_t: float = 0.0
var _coyote_t: float = 0.0
var _pending_hx: float = 0.0
var _jump_cd_left: float = 0.0
var _evade_cd_left: float = 0.0
var _feint_cd_left: float = 0.0

var _drop_active: bool = false
var _drop_timer: float = 0.0
var _drop_cd_t: float = 0.0
var _cached_mask: int = 0
var _snap_backup: float = 0.0

var _shape_cache: Dictionary = {}
var _shape_cache_hooked: Dictionary = {}

var __dbg_tick_acc: float = 0.0
var __probe_acc: float = 0.0
var __probe_log_acc: float = 0.0

var _just_blocked_jump_frames: int = 0
var _post_jump_edge_ignore_t: float = 0.0

# =============================================================================
# DEBUG
# =============================================================================
func _dbg(msg: String) -> void:
	if debug_jump_ai:
		print("[JUMP_AI] ", msg)

func _dbg_probe(msg: String) -> void:
	if not debug_jump_ai or not debug_verbose_probes:
		return
	if __probe_log_acc > 0.0:
		return
	print("[JUMP_AI] ", msg)
	__probe_log_acc = debug_probe_log_period

# =============================================================================
# LIFE CYCLE
# =============================================================================
func _ready() -> void:
	randomize()
	if debug_jump_ai:
		var scr: GDScript = get_script() as GDScript
		var path := (scr.resource_path if scr != null else "<no path>")
		print("[JUMP_AI] READY on ", get_path(), " script=", path, " id=", get_instance_id())
	set_physics_process(true)

	# Поиск ссылок в иерархии
	if actor == null:
		actor = get_parent() as Node3D

	if actor != null and body == null:
		body = actor.get_node_or_null(NodePath("Body")) as CharacterBody3D
		if body == null and actor is CharacterBody3D:
			body = actor as CharacterBody3D

	if actor != null:
		_anim = actor.get_node_or_null(NodePath("Animation")) as EnemyAnimation
		if _anim == null:
			for p in [NodePath("Body/Animation"), NodePath("Anim")]:
				var node: Node = actor.get_node_or_null(p)
				if node is EnemyAnimation:
					_anim = node as EnemyAnimation
					break

	_perc = actor.get_node_or_null(NodePath("Perception")) as EnemyPerception
	_hitboxes = actor.get_node_or_null(NodePath("Body/Hitboxes")) as Node3D
	_hitboxes_ok = (_hitboxes != null)
	_ahead = actor.get_node_or_null(NodePath("Body/Ahead")) as Node3D
	_ahead_ok = (_ahead != null)

	if body != null:
		body.set_collision_mask_value(player_body_layer_bit, false)

	# ==== КОНФИГ ====
	if cfg == null and actor != null:
		var cfg_node: Node = actor.get_node_or_null(NodePath("Config"))
		if cfg_node != null and cfg_node is EnemyConfig:
			cfg = cfg_node as EnemyConfig
		else:
			cfg = EnemyConfig.new()
			cfg.name = "Config"
			actor.add_child(cfg)

	# Диагностика: что за cfg и какие значения реально видим
	if debug_jump_ai and cfg != null:
		_dbg("CFG node: %s class=%s walk_speed=%s jump_speed=%s gravity=%s" % [
			str(cfg.get_path()),
			(str(cfg.get_class()) if cfg.has_method("get_class") else str(cfg)),
			str(cfg.get("walk_speed")),
			str(cfg.get("jump_speed")),
			str(cfg.get("gravity"))
		])

	# Плоскость
	if body != null:
		_plane_z = body.global_position.z
	elif actor != null:
		_plane_z = actor.global_position.z

	_last_facing = 0
	_apply_facing()
	_lock_to_plane()

func setup(_actor: Node3D, _body: CharacterBody3D, _cfg: Variant) -> void:
	# Жёстко фиксируем источник cfg, чтобы брать ИМЕННО то, что вы правите в дереве.
	actor = _actor
	body  = _body

	# 1) Явно переданный EnemyConfig
	if _cfg != null and _cfg is EnemyConfig:
		cfg = _cfg as EnemyConfig
		_ready()
		return

	# 2) Экспорт ресурса у актора (часто указывают в инспекторе)
	if actor != null:
		for name in ["Config", "config", "enemy_config"]:
			if actor.has_method("get"):
				var cand: Variant = actor.get(name)
				if cand != null and cand is EnemyConfig:
					cfg = cand as EnemyConfig
					_ready()
					return

		# 3) Кастомный метод-обёртка
		if actor.has_method("get_config"):
			var v: Variant = actor.call("get_config")
			if v != null and v is EnemyConfig:
				cfg = v as EnemyConfig
				_ready()
				return

		# 4) Узел "Config" в дереве
		var cfg_node: Node = actor.get_node_or_null(NodePath("Config"))
		if cfg_node != null and cfg_node is EnemyConfig:
			cfg = cfg_node as EnemyConfig
			_ready()
			return

	# 5) Фолбэк — только если ничего не нашли
	cfg = EnemyConfig.new()
	cfg.name = "Config"
	if actor != null and actor is Node:
		actor.add_child(cfg)
	_ready()

func _physics_process(delta: float) -> void:
	_last_delta = delta

	if debug_jump_ai:
		__dbg_tick_acc += delta
		if __dbg_tick_acc >= max(debug_tick_period, 0.05):
			__dbg_tick_acc = 0.0
			_dbg("PHYS_TICK on " + str(get_path()))

	if debug_jump_ai and debug_force_jump_probe:
		__probe_acc += delta
		if __probe_acc >= max(debug_probe_period, 0.05):
			__probe_acc = 0.0
			_dbg("TICK force probe")
			_try_wall_hop_towards_player()

	_evade_left    = maxf(0.0, _evade_left - delta)
	_evade_cd_left = maxf(0.0, _evade_cd_left - delta)
	_drop_cd_t     = maxf(0.0, _drop_cd_t - delta)
	_jump_cd_left  = maxf(0.0, _jump_cd_left - delta)
	_post_jump_edge_ignore_t = maxf(0.0, _post_jump_edge_ignore_t - delta)

	if _just_blocked_jump_frames > 0:
		_just_blocked_jump_frames -= 1

	_auto_face_player()
	_apply_facing()
	_lock_to_plane()

	if _edge_hold_active:
		var gap_imminent_now: bool = _is_imminent_gap_ahead(0.8, max(gap_probe_down, 1.0))
		if gap_imminent_now:
			_edge_hold_no_gap_t = 0.0
		else:
			_edge_hold_no_gap_t += delta
			if _edge_hold_no_gap_t >= 0.20:
				_stop_edge_hold()

	_validate_pending_jump()
	_edge_safety_guard()
	_update_anim_from_velocity()

	if __probe_log_acc > 0.0:
		__probe_log_acc = maxf(0.0, __probe_log_acc - delta)

# =============================================================================
# ПУБЛИЧНОЕ API
# =============================================================================
func stop() -> void:
	if body != null:
		body.velocity.x = 0.0

func stop_immediately() -> void:
	if body == null:
		return
	body.velocity.x = 0.0

func approach_player(_dist: float) -> void:
	if actor == null or body == null:
		return

	var min_d: float = _cfg_approach_min()
	var max_d: float = _cfg_approach_max()
	var walk_sp: float = _cfg_walk_speed()
	var back_margin: float = _cfg_retreat_margin()

	var p: Node3D = (_perc.get_player() if _perc != null else null)
	if p == null:
		_move_x(0.0)
		return

	var dx: float = p.global_position.x - body.global_position.x
	var dir: float = (-1.0 if dx < 0.0 else 1.0)
	if absf(dx) > FACE_EPS:
		_try_flip_to(int(dir))

	var eff: float = _edge_distance_x(body, p, dir)
	var vx: float = 0.0
	if eff > max_d:
		vx = dir * walk_sp
	elif eff < max(0.0, min_d - back_margin):
		vx = -dir * walk_sp
	else:
		vx = 0.0

	_move_x(vx)
	consider_drop_to_player()
	_try_wall_hop_towards_player()

func approach_to_distance(desired_dist: float, _tol: float = 0.0, _prefer_run: bool = false, accel: float = 18.0) -> bool:
	if body == null:
		return false
	var p: Node3D = (_perc.get_player() if _perc != null else null)
	if p == null:
		_smooth_move_x(0.0, accel)
		return false

	var dx: float = p.global_position.x - body.global_position.x
	var dir_to_player: float = (1.0 if dx >= 0.0 else -1.0)
	if absf(dx) > FACE_EPS:
		_try_flip_to(int(dir_to_player))

	var eff_dist: float = _edge_distance_x(body, p, dir_to_player)
	var back_margin: float = _cfg_retreat_margin()
	var target_vx: float = 0.0
	if eff_dist > desired_dist:
		target_vx = dir_to_player * _cfg_walk_speed()
	elif eff_dist < max(desired_dist - back_margin, 0.0):
		target_vx = -dir_to_player * _cfg_walk_speed()
	else:
		target_vx = 0.0

	_smooth_move_x(target_vx, accel)
	consider_drop_to_player()
	_try_wall_hop_towards_player()
	return absf(target_vx) > 0.01

func walk_patrol() -> void:
	if actor == null or body == null:
		return
	if _should_turn_around():
		if _try_wall_hop_towards_player():
			return
		_try_flip_to(-actor.facing_dir)
		return
	_move_x(float(actor.facing_dir) * _cfg_walk_speed())
	consider_drop_to_player()
	_try_wall_hop_towards_player()

func nudge_forward() -> void:
	if actor == null or body == null:
		return
	var step_vx: float = _cfg_walk_speed() * 0.6
	body.velocity.x += float(actor.facing_dir) * step_vx

func backstep_with_iframes(iframes: float) -> void:
	if actor == null or body == null:
		return
	_evade_left = max(0.0, iframes)
	_evade_cd_left = _cfg_evade_cooldown()
	var back_speed: float = _cfg_evade_back_speed()

	var dir_back: float = -float(actor.facing_dir)
	if _is_imminent_gap_in_dir(dir_back, max(patrol_turn_forward, 0.6), max(patrol_turn_down, 1.2)) and is_on_ground():
		_start_edge_hold(float(actor.facing_dir), 0.0, 0.0)
		body.velocity.x = 0.0
	else:
		body.velocity.x = dir_back * back_speed

	body.velocity.z = 0.0

func can_evade() -> bool: return _evade_cd_left <= 0.0
func can_feint() -> bool: return _feint_cd_left <= 0.0
func mark_feint_used() -> void: _feint_cd_left = _cfg_feint_cooldown()
func is_evade_over() -> bool: return _evade_left <= 0.0

func apply_knockback_from(from_pos: Vector3, impulse_value: float) -> void:
	if body == null or actor == null:
		return
	var dir: float = sign(body.global_position.x - from_pos.x)
	if dir == 0.0:
		dir = float(actor.facing_dir)
	if _is_imminent_gap_in_dir(dir, max(gap_probe_forward, 0.4), max(gap_probe_down, 0.8)) and is_on_ground():
		_start_edge_hold(float(actor.facing_dir), 0.0, 0.0)
		body.velocity.x = 0.0
	else:
		body.velocity.x = dir * max(impulse_value, 2.5)

# =============================================================================
# ПРЫЖКИ: ВЫСОКИЙ УРОВЕНЬ
# =============================================================================
func is_on_ground() -> bool:
	return body != null and body.is_on_floor()

func is_on_air() -> bool:
	return body != null and not body.is_on_floor()

func try_wall_hop_over_wall() -> bool:
	if body == null or not is_on_ground():
		return false

	var dirf: float = float(actor.facing_dir) if actor != null else 1.0
	_dbg("TRY_WALL_HOP_OVER_WALL called")

	var gap_now: bool = _is_imminent_gap_ahead(edge_jump_trigger_forward, max(gap_probe_down, 1.0))
	if gap_now:
		var can_jump_gap: bool = _can_clear_measured_gap(dirf)
		if allow_gap_jumps and can_jump_gap:
			return _jump_forward_walk(dirf)
		else:
			_mark_blocked_for_anim()
			return false

	if _is_wall_ahead(0.5, 0.9) or _needs_step_up_ahead():
		if not allow_upward_jumps:
			_mark_blocked_for_anim()
			return false
		if require_player_above_for_upward and not _has_chase_reason(dirf):
			_mark_blocked_for_anim()
			return false
		if not _has_valid_landing_ahead(dirf):
			_mark_blocked_for_anim()
			return false
		return _jump_forward_walk(dirf)

	return false

func _jump_forward_walk(dirf: float) -> bool:
	var hx: float = dirf * _cfg_walk_speed() * _cfg_jump_horiz_mult()
	return perform_jump(hx, true, true)

# =============================================================================
# СЕНСОРЫ / ЯМЫ
# =============================================================================
func _dirf() -> float:
	return float(actor.facing_dir) if actor != null else 1.0

func _is_imminent_gap_ahead(forward: float, down: float) -> bool:
	if body == null:
		return false
	var up_sign: float = 1.0 if uses_positive_up() else -1.0
	var dirf: float = _dirf()
	var origin: Vector3 = body.global_transform.origin

	var from_here: Vector3 = origin + Vector3(0.0, 0.05 * up_sign, 0.0)
	var to_here:   Vector3 = from_here + Vector3(0.0, -down * up_sign, 0.0)

	var from_ahead: Vector3 = origin + Vector3(dirf * forward, 0.05 * up_sign, 0.0)
	var to_ahead:   Vector3 = from_ahead + Vector3(0.0, -down * up_sign, 0.0)

	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state

	var q_here := PhysicsRayQueryParameters3D.new()
	q_here.from = from_here
	q_here.to = to_here
	q_here.collision_mask = ground_layer_mask | platform_layer_mask
	q_here.hit_from_inside = false

	var q_ahead := PhysicsRayQueryParameters3D.new()
	q_ahead.from = from_ahead
	q_ahead.to = to_ahead
	q_ahead.collision_mask = ground_layer_mask | platform_layer_mask
	q_ahead.hit_from_inside = false

	var hit_here: Dictionary = space.intersect_ray(q_here)
	var hit_ahead: Dictionary = space.intersect_ray(q_ahead)

	return (hit_here.size() > 0) and (hit_ahead.size() == 0)

func _is_imminent_gap_in_dir(dirf: float, forward: float, down: float) -> bool:
	if body == null:
		return false
	var up_sign: float = 1.0 if uses_positive_up() else -1.0
	var origin: Vector3 = body.global_transform.origin

	var from_here: Vector3 = origin + Vector3(0.0, 0.05 * up_sign, 0.0)
	var to_here:   Vector3 = from_here + Vector3(0.0, -down * up_sign, 0.0)

	var from_ahead: Vector3 = origin + Vector3(dirf * forward, 0.05 * up_sign, 0.0)
	var to_ahead:   Vector3 = from_ahead + Vector3(0.0, -down * up_sign, 0.0)

	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state

	var q_here := PhysicsRayQueryParameters3D.new()
	q_here.from = from_here
	q_here.to = to_here
	q_here.collision_mask = ground_layer_mask | platform_layer_mask
	q_here.hit_from_inside = false

	var q_ahead := PhysicsRayQueryParameters3D.new()
	q_ahead.from = from_ahead
	q_ahead.to = to_ahead
	q_ahead.collision_mask = ground_layer_mask | platform_layer_mask
	q_ahead.hit_from_inside = false

	var hit_here: Dictionary = space.intersect_ray(q_here)
	var hit_ahead: Dictionary = space.intersect_ray(q_ahead)
	return (hit_here.size() > 0) and (hit_ahead.size() == 0)

# Профильная «яма»
func _measure_gap_ahead(dirf: float, start_x: float, max_scan_x: float, down: float) -> Dictionary:
	var result := {
		"has_gap": false,
		"width": 0.0,
		"land_y": 0.0,
		"land_found": false,
		"min_y": 0.0
	}
	if body == null:
		return result

	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var origin: Vector3 = body.global_transform.origin
	var up_sign: float = (1.0 if uses_positive_up() else -1.0)
	var step: float = max(0.02, gap_scan_step)

	var self_y: float = body.global_position.y
	var gap_begin_x: float = -1.0
	var gap_end_x: float = -1.0
	var min_y_in_gap: float = self_y

	var x: float = start_x
	while x <= max_scan_x + 0.0001:
		var from_p: Vector3 = origin + Vector3(dirf * x, 0.05 * up_sign, 0.0)
		var to_p:   Vector3 = from_p + Vector3(0.0, -down * up_sign, 0.0)
		var q := PhysicsRayQueryParameters3D.new()
		q.from = from_p
		q.to = to_p
		q.collision_mask = ground_layer_mask | platform_layer_mask
		q.hit_from_inside = false

		var hit: Dictionary = space.intersect_ray(q)
		var has_floor: bool = hit.size() > 0
		var floor_y: float = (float((hit["position"] as Vector3).y) if has_floor else -INF)

		var is_gap_x: bool = (not has_floor) or (has_floor and (self_y - floor_y) >= treat_step_drop_as_gap)

		if is_gap_x:
			if gap_begin_x < 0.0:
				gap_begin_x = x
			if has_floor and floor_y < min_y_in_gap:
				min_y_in_gap = floor_y
		else:
			if gap_begin_x >= 0.0:
				gap_end_x = x
				break
		x += step

	if gap_begin_x >= 0.0 and gap_end_x < 0.0:
		gap_end_x = x

	if gap_begin_x < 0.0 or gap_end_x <= gap_begin_x:
		return result

	# --- Поиск приземления: всегда чуть ЗА краем ямы ---
	var land_found: bool = false
	var land_y: float = self_y
	var x_land: float = gap_end_x + max(step * 0.5, 0.03)

	# глубина для поиска приземления (чтобы достать до «дна» даже после провалов)
	var landing_down: float = max(down, (self_y - min_y_in_gap) + max_safe_drop_multiplier * max_jump_height_estimate() + 0.5)

	while x_land <= max_scan_x + 0.0001:
		var from_p2: Vector3 = origin + Vector3(dirf * x_land, 0.10 * up_sign, 0.0)
		var to_p2:   Vector3 = from_p2 + Vector3(0.0, -landing_down * up_sign, 0.0)
		var q2 := PhysicsRayQueryParameters3D.new()
		q2.from = from_p2
		q2.to = to_p2
		q2.collision_mask = ground_layer_mask | platform_layer_mask
		q2.hit_from_inside = false
		var hit2: Dictionary = space.intersect_ray(q2)
		if hit2.size() > 0:
			land_found = true
			land_y = float((hit2["position"] as Vector3).y)
			break
		x_land += step

	result["has_gap"] = true
	result["width"] = max(0.0, gap_end_x - gap_begin_x)
	result["land_y"] = land_y
	result["land_found"] = land_found
	result["min_y"] = min_y_in_gap

	if debug_gap_calc:
		var walk_vx: float = _cfg_walk_speed() * _cfg_jump_horiz_mult()
		var auto_vx: float = walk_vx # оставлено для читабельности логов
		_dbg("[GAP] begin=%.2f end=%.2f width=%.2f land_found=%s land_y=%.2f min_y=%.2f thr=%.2f scan_limit=%.2f auto=%.2f walk=%.2f" %
			[gap_begin_x, gap_end_x, result["width"], str(land_found), land_y, min_y_in_gap, treat_step_drop_as_gap, max_scan_x, auto_vx, walk_vx])

	return result

# Может ли перепрыгнуть измеренную «яму»
func _can_clear_measured_gap(dirf: float) -> bool:
	if body == null:
		return false

	var start_off: float = max(0.02, edge_jump_trigger_forward * 0.95)
	var scan: Dictionary = _measure_gap_ahead(dirf, start_off, max_gap_scan_forward, 3.5)
	if not bool(scan["has_gap"]):
		return false

	var width: float = float(scan["width"])
	var land_found: bool = bool(scan["land_found"])
	var land_y: float = float(scan["land_y"])
	var self_y: float = body.global_position.y
	var dy: float = land_y - self_y

	if width < min_gap_width_to_jump:
		if debug_gap_calc:
			_dbg("[GAP] width %.2f < min_gap_width_to_jump %.2f -> treat as step" % [width, min_gap_width_to_jump])
		return false

	if not land_found:
		if debug_gap_calc:
			_dbg("[GAP] no landing found -> stop at edge")
		return false

	var max_drop: float = max_safe_drop_multiplier * max_jump_height_estimate()
	if dy < 0.0 and absf(dy) > max_drop:
		if debug_gap_calc:
			_dbg("[GAP] landing too deep dy=%.2f > max_drop=%.2f -> stop" % [absf(dy), max_drop])
		return false

	var walk_vx: float = _cfg_walk_speed() * _cfg_jump_horiz_mult()
	var max_dx_same_or_down: float = _max_horizontal_range_for_dy(min(0.0, dy), walk_vx)
	var max_dx_up: float = _max_horizontal_range_for_dy(max(0.0, dy), walk_vx)
	var max_dx: float = max(max_dx_same_or_down, max_dx_up)

	var ok: bool = (width <= (max_dx + 0.03))
	if debug_gap_calc:
		_dbg("[GAP] width=%.2f, dy=%.2f, max_dx=%.2f (walk_vx=%.2f mult=%.2f) -> can=%s" %
			[width, dy, max_dx, walk_vx, _cfg_jump_horiz_mult(), str(ok)])
	return ok

# Лип/платформа/стены — сенсоры
func _probe_lip_height_ahead(forward_offset: float = 0.6, probe_up: float = 0.9, probe_down: float = 2.5) -> Variant:
	if body == null:
		return null
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var origin: Vector3 = body.get_global_transform().origin + Vector3(_dirf() * forward_offset, probe_up, 0.0)
	var to_point: Vector3 = origin + Vector3(0.0, -probe_down, 0.0)
	var q := PhysicsRayQueryParameters3D.new()
	q.from = origin
	q.to = to_point
	q.collision_mask = ground_layer_mask
	q.collide_with_bodies = true
	q.collide_with_areas = true
	q.exclude = [body.get_rid()]
	var res: Dictionary = space.intersect_ray(q)
	if res.is_empty():
		_dbg_probe("LIP probe from=%s to=%s hit=none" % [str(origin), str(to_point)])
		return null
	var pos: Vector3 = res["position"] as Vector3
	_dbg_probe("LIP probe from=%s to=%s hitY=%.3f" % [str(origin), str(to_point), pos.y])
	return pos.y

func _probe_platform_top_ahead(forward_offset: float = 0.6, probe_up: float = 1.2, probe_down: float = 3.5) -> Variant:
	if body == null:
		return null
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var origin: Vector3 = body.get_global_transform().origin + Vector3(_dirf() * forward_offset, probe_up, 0.0)
	var to_point: Vector3 = origin + Vector3(0.0, -probe_down, 0.0)
	var q := PhysicsRayQueryParameters3D.new()
	q.from = origin
	q.to = to_point
	q.collision_mask = platform_layer_mask
	q.collide_with_bodies = true
	q.collide_with_areas = true
	q.exclude = [body.get_rid()]
	var res: Dictionary = space.intersect_ray(q)
	if res.is_empty():
		_dbg_probe("PLAT probe from=%s to=%s hit=none" % [str(origin), str(to_point)])
		return null
	var pos: Vector3 = res["position"] as Vector3
	_dbg_probe("PLAT probe from=%s to=%s hitY=%.3f" % [str(origin), str(to_point), pos.y])
	return pos.y

func _is_wall_ahead(forward_offset: float = 0.5, chest_height: float = 0.9) -> bool:
	if body == null:
		return false
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var origin: Vector3 = body.global_transform.origin + Vector3(0.0, chest_height, 0.0)
	var to_point: Vector3 = origin + Vector3(_dirf() * forward_offset, 0.0, 0.0)
	var q := PhysicsRayQueryParameters3D.new()
	q.from = origin
	q.to = to_point
	q.collision_mask = ground_layer_mask | platform_layer_mask
	q.collide_with_bodies = true
	q.collide_with_areas = true
	q.exclude = [body.get_rid()]
	var res: Dictionary = space.intersect_ray(q)
	_dbg_probe("WALL probe from=%s to=%s hit=%s" % [str(origin), str(to_point), str(not res.is_empty())])
	return not res.is_empty()

func _has_headroom_at(target_xy: Vector3, up_clearance: float = 1.2) -> bool:
	if body == null:
		return false
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var from_p: Vector3 = target_xy
	var to_p: Vector3 = target_xy + Vector3(0.0, up_clearance, 0.0)
	var q := PhysicsRayQueryParameters3D.new()
	q.from = from_p
	q.to = to_p
	q.collision_mask = ground_layer_mask | platform_layer_mask
	q.collide_with_bodies = true
	q.collide_with_areas = true
	q.exclude = [body.get_rid()]
	var clear: bool = space.intersect_ray(q).is_empty()
	_dbg_probe("HEADROOM probe from=%s to=%s clear=%s" % [str(from_p), str(to_p), str(clear)])
	return clear

func _has_valid_landing_ahead(dirf: float) -> bool:
	if body == null:
		return false

	var pos: Vector3 = body.global_position
	var self_y: float = pos.y

	var eff_vx: float = _cfg_walk_speed() * _cfg_jump_horiz_mult()
	var headroom_h: float = 1.2
	var max_drop: float = max_safe_drop_multiplier * max_jump_height_estimate()

	var max_dx_same_or_down: float = _max_horizontal_range_for_dy(0.0, eff_vx)
	var max_dx_up: float = _max_horizontal_range_for_dy(0.22, eff_vx)
	var max_dx: float = max(max_dx_same_or_down, max_dx_up)
	if max_dx <= 0.0:
		return false

	var step: float = 0.4
	var start_off: float = 0.6
	var limit_off: float = max_dx

	var off: float = start_off
	while off <= limit_off + 0.001:
		var plat_y_v: Variant = _probe_platform_top_ahead(off, 1.2, 3.5)
		var lip_y_v: Variant  = _probe_lip_height_ahead(off, 0.9, 2.5)

		if plat_y_v != null:
			var py: float = float(plat_y_v)
			var dy_p: float = py - self_y
			var ok_down: bool = (dy_p <= 0.0 and absf(dy_p) <= max_drop)
			var ok_up: bool = (dy_p > 0.0) and _can_reach_y_with_jumps(self_y, py, 1, 0.22)
			if ok_down or ok_up:
				var land: Vector3 = Vector3(pos.x + dirf * off, py, pos.z)
				if _has_headroom_at(land, headroom_h):
					return true

		if lip_y_v != null:
			var ly: float = float(lip_y_v)
			var dy_l: float = ly - self_y
			var ok_down_l: bool = (dy_l <= 0.0 and absf(dy_l) <= max_drop)
			var ok_up_l: bool = (dy_l > 0.28) and _can_reach_y_with_jumps(self_y, ly, 1, 0.22)
			if ok_down_l or ok_up_l:
				var land2: Vector3 = Vector3(pos.x + dirf * off, ly, pos.z)
				if _has_headroom_at(land2, headroom_h):
					return true

		off += step

	return false

func _needs_step_up_ahead() -> bool:
	if body == null:
		return false
	var self_y: float = body.global_position.y
	var lip_y_v: Variant = _probe_lip_height_ahead(0.6, 0.9, 2.5)
	if lip_y_v == null:
		return false
	var lip_y: float = float(lip_y_v)
	return (lip_y - self_y) > 0.28

# =============================================================================
# АНИМАЦИЯ / ФЕЙСИНГ
# =============================================================================
func _update_anim_from_velocity() -> void:
	if _anim == null or body == null or actor == null:
		return
	if _just_blocked_jump_frames > 0:
		if body.is_on_floor():
			_update_idle_walk_only()
		return
	var st: Variant = _get_state()
	if _state_blocks_locomotion(st):
		return
	if not body.is_on_floor():
		if _anim != null:
			if (uses_positive_up() and body.velocity.y > 0.2) or (not uses_positive_up() and body.velocity.y < -0.2):
				_anim.play_jump()
			else:
				_anim.play_fall()
		return
	_update_idle_walk_only()

func _update_idle_walk_only() -> void:
	if _anim == null or body == null:
		return
	var ax: float = absf(body.velocity.x)
	var next_state: int = _move_state
	if _move_state == 1:
		next_state = (1 if ax > IDLE_THR else 0)
	else:
		next_state = (1 if ax > WALK_THR else 0)
	if next_state == _move_state:
		return
	_move_state = next_state
	if _move_state == 1:
		if _anim.current != _anim.get_walk_id() or (_anim.sprite != null and not _anim.sprite.is_playing()):
			_anim.play_walk()
	else:
		if _anim.current != _anim.get_idle_id() or (_anim.sprite != null and not _anim.sprite.is_playing()):
			_anim.play_idle()

func _try_flip_to(new_dir: int) -> void:
	if actor == null:
		return
	new_dir = clamp(new_dir, -1, 1)
	if new_dir == 0 or new_dir == actor.facing_dir:
		return
	if _anim != null and _anim.is_flip_locked():
		return
	actor.facing_dir = new_dir
	_apply_facing()

func _apply_facing() -> void:
	if _anim != null:
		_anim.set_facing(actor.facing_dir)
	if actor == null:
		return
	var dir: int = actor.facing_dir
	if dir == _last_facing:
		return
	_last_facing = dir
	var target_y: float = (PI if dir > 0 else 0.0)
	if _hitboxes_ok:
		var rot_h: Vector3 = _hitboxes.rotation
		rot_h.y = target_y
		_hitboxes.rotation = rot_h
	if _ahead != null and _ahead_ok:
		var rot_a: Vector3 = _ahead.rotation
		rot_a.y = target_y
		_ahead.rotation = rot_a

func _auto_face_player() -> void:
	if actor == null or _perc == null or body == null:
		return
	if is_on_air():
		return
	if _anim != null and _anim.is_flip_locked():
		return
	if not _perc.has_target:
		return
	var p: Node3D = _perc.get_player()
	if p == null:
		_move_x(0.0)
		return
	var dx: float = p.global_position.x - body.global_position.x
	var dir: int = (-1 if dx < 0.0 else 1)
	var ax: float = absf(body.velocity.x)
	var idle_like: bool = (ax <= IDLE_THR)
	var switch_eps: float = (maxf(FACE_EPS, IDLE_FACE_STICK_X) if idle_like else FACE_EPS)
	if absf(dx) > switch_eps:
		_try_flip_to(dir)

# =============================================================================
# ФИЗИКА ДВИЖЕНИЯ
# =============================================================================
func _lock_to_plane() -> void:
	if body == null:
		return
	if body.velocity.z != 0.0:
		body.velocity.z = 0.0
	var gp: Vector3 = body.global_position
	if gp.z != _plane_z:
		gp.z = _plane_z
		body.global_position = gp

func _apply_vertical(dt: float = -1.0) -> void:
	if dt < 0.0:
		dt = get_physics_process_delta_time()
	if body == null:
		return

	if _edge_hold_active and is_on_ground():
		body.velocity.x = 0.0

	if is_on_ground():
		_coyote_t = coyote_time
	else:
		_coyote_t = maxf(0.0, _coyote_t - dt)

	if _jump_buf_t > 0.0:
		_jump_buf_t = maxf(0.0, _jump_buf_t - dt)
		if (is_on_ground() or _coyote_t > 0.0):
			if _jump_cd_left <= 0.0:
				_do_jump(_pending_hx)
				_pending_hx = 0.0
			else:
				if _jump_buf_t <= 0.0:
					_pending_hx = 0.0
					_mark_blocked_for_anim()

	var g: float = _cfg_gravity()
	if uses_positive_up():
		body.velocity.y += (-g * (fall_multiplier if body.velocity.y < 0.0 else 1.0)) * dt
	else:
		body.velocity.y += ( g * (fall_multiplier if body.velocity.y > 0.0 else 1.0)) * dt

	var v: Vector3 = body.velocity
	var max_fall: float = _cfg_max_fall_speed()
	if uses_positive_up():
		if v.y < -max_fall: v.y = -max_fall
	else:
		if v.y >  max_fall: v.y =  max_fall
	body.velocity = v

	var mask: int = body.collision_mask
	if _cached_mask == 0:
		_cached_mask = mask
	var going_up: bool = (body.velocity.y > 1.0 if uses_positive_up() else body.velocity.y < -1.0)
	if _drop_active or going_up:
		mask = mask & ~platform_layer_mask
	else:
		mask = mask | platform_layer_mask
	body.collision_mask = mask

	if _drop_active:
		_drop_timer = maxf(0.0, _drop_timer - dt)
		if _drop_timer <= 0.0 and not going_up:
			_drop_active = false
			body.collision_mask = _cached_mask
			if zero_snap:
				body.floor_snap_length = _snap_backup

func _move_x(xv: float) -> void:
	if body == null:
		return
	var lim: float = _cfg_walk_speed()
	body.velocity.x = clamp(xv, -lim, lim)
	_apply_vertical()
	body.velocity.z = 0.0
	body.move_and_slide()
	_lock_to_plane()
	_mark_step_done()

func _smooth_move_x(target_xv: float, accel: float) -> void:
	if body == null:
		return
	var lim: float = _cfg_walk_speed()
	var target: float = clamp(target_xv, -lim, lim)
	var a: float = clamp(accel * _last_delta, 0.0, 1.0)
	var new_vx: float = lerp(body.velocity.x, target, a)
	_move_x(new_vx)

# =============================================================================
# RTTI / STATE
# =============================================================================
func _get_state() -> Variant:
	if actor == null:
		return null
	if actor.has_method("get_state"):
		return actor.call("get_state")
	return actor.get("state")

func _state_blocks_locomotion(st: Variant) -> bool:
	if st == null:
		return false
	if st.has_method("blocks_locomotion"):
		var v: Variant = st.call("blocks_locomotion")
		if typeof(v) == TYPE_BOOL:
			return v
	var cname := (str(st.call("get_class")) if st.has_method("get_class") else str(st)).to_lower()
	return cname.findn("attack") >= 0 or cname.findn("hitstun") >= 0 \
		or cname.findn("evade") >= 0 or cname.findn("jump") >= 0 \
		or cname.findn("fall") >= 0

# =============================================================================
# ГЕОМЕТРИЯ / ХЕЛПЕРЫ
# =============================================================================
func _primary_collision_shape(root: Node) -> CollisionShape3D:
	if root == null:
		return null
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is CollisionShape3D:
				return c
			stack.push_back(c)
	return null

func _primary_collision_shape_cached(root: Node) -> CollisionShape3D:
	if root == null:
		return null
	if _shape_cache.has(root):
		var cached: CollisionShape3D = _shape_cache[root]
		if is_instance_valid(cached) and cached.shape != null:
			return cached
		_shape_cache.erase(root)
	var cs := _primary_collision_shape(root)
	_shape_cache[root] = cs
	if not _shape_cache_hooked.has(root):
		root.tree_exited.connect(_on_shape_owner_exited.bind(root), Object.CONNECT_ONE_SHOT)
		_shape_cache_hooked[root] = true
	return cs

func _on_shape_owner_exited(root: Node) -> void:
	_shape_cache.erase(root)
	_shape_cache_hooked.erase(root)

func _shape_world_half_x(cs: CollisionShape3D) -> float:
	if cs == null or cs.shape == null:
		return 0.0
	var sx: float = cs.global_transform.basis.x.length()
	var s := cs.shape
	if s is BoxShape3D:       return float(s.size.x) * 0.5 * sx
	elif s is CapsuleShape3D: return float(s.radius) * sx
	elif s is CylinderShape3D:return float(s.radius) * sx
	elif s is SphereShape3D:  return float(s.radius) * sx
	return 0.0

func _edges_world_x_for(root: Node) -> Vector2:
	var cx: float = 0.0
	var half: float = 0.0
	if root is Node3D:
		var n3: Node3D = root as Node3D
		cx = n3.global_transform.origin.x
		var cs: CollisionShape3D = _primary_collision_shape_cached(root)
		if cs != null and cs.shape != null:
			cx = cs.global_transform.origin.x
			half = _shape_world_half_x(cs)
	return Vector2(cx - half, cx + half)

func _edge_distance_x(self_root: Node, other_root: Node, dir_to_other: float) -> float:
	var e_self: Vector2 = _edges_world_x_for(self_root)
	var e_other: Vector2 = _edges_world_x_for(other_root)
	if dir_to_other >= 0.0:
		return max(0.0, e_other.x - e_self.y)
	else:
		return max(0.0, e_self.x - e_other.y)

func invalidate_shape_cache_for(root: Node) -> void:
	if root == null:
		return
	_shape_cache.erase(root)

# =============================================================================
# НИЗКИЙ УРОВЕНЬ ПРЫЖКА / DROP-THROUGH
# =============================================================================
func _do_jump(hx: float) -> void:
	if body == null:
		return

	var on_ground_now: bool = is_on_ground()
	var can_coyote: bool = _coyote_t > 0.0
	var can_jump_now: bool = on_ground_now or can_coyote

	if _jump_cd_left > 0.0:
		_pending_hx = hx
		_jump_buf_t = maxf(_jump_buf_t, _jump_cd_left + 0.02)
		_mark_blocked_for_anim()
		_dbg("BLOCK _do_jump: wait cooldown %.2fs (buffer=%.2fs)" % [_jump_cd_left, _jump_buf_t])
		return

	if not can_jump_now:
		_pending_hx = hx
		_jump_buf_t = maxf(_jump_buf_t, jump_buffer)
		_mark_blocked_for_anim()
		_dbg("BLOCK _do_jump: no ground/coyote (buffer=%.2fs)" % _jump_buf_t)
		return

	var dirf: float = float(actor.facing_dir if actor != null else 1.0)
	var base_vx: float = (hx if hx != 0.0 else (dirf * absf(body.velocity.x)))
	var cap: float = _cfg_walk_speed() * _cfg_jump_horiz_mult()
	var capped_vx: float = clamp(base_vx, -cap, cap)

	var js: float = _cfg_jump_speed()
	if uses_positive_up():
		body.velocity = Vector3(capped_vx, js, 0.0)
	else:
		body.velocity = Vector3(capped_vx, -js, 0.0)

	if _edge_hold_active:
		_stop_edge_hold()
	_pending_reason = JUMP_REASON_NONE

	_jump_cd_left = _cfg_jump_cooldown()
	_post_jump_edge_ignore_t = post_jump_edge_ignore
	_dbg("JUMP EXECUTED vx=%.3f js=%.3f (cap≤%.3f)" % [capped_vx, js, cap])

func start_drop_through(duration: float = drop_duration) -> void:
	if body == null:
		return
	if _drop_cd_t > 0.0 or _drop_active:
		return
	if not _drop_active:
		_cached_mask = body.collision_mask
		if zero_snap:
			_snap_backup = body.floor_snap_length
			body.floor_snap_length = 0.0
	_drop_active = true
	_drop_timer = duration
	_drop_cd_t = drop_cooldown_sec
	if uses_positive_up():
		if body.velocity.y > -0.2: body.velocity.y = -0.2
	else:
		if body.velocity.y <  0.2: body.velocity.y =  0.2

func is_dropping() -> bool:
	return _drop_active

# =============================================================================
# МАТЕМАТИКА / КОНФИГ
# =============================================================================
func max_jump_height_estimate() -> float:
	var v: float = _cfg_jump_speed()
	var g: float = absf(_cfg_gravity())
	if g <= 0.0: return 0.0
	return (v * v) / (2.0 * g)

func uses_positive_up() -> bool:
	return true

func is_above(self_y: float, other_y: float, eps: float = 0.10) -> bool:
	return (other_y - self_y) > eps if uses_positive_up() else (other_y - self_y) < -eps

func is_below(self_y: float, other_y: float, eps: float = 0.20) -> bool:
	return (other_y - self_y) < -eps if uses_positive_up() else (other_y - self_y) > eps

func can_reach_y(self_y: float, target_y: float, extra_margin: float = 0.20) -> bool:
	var gap: float = absf(target_y - self_y)
	return gap <= max_jump_height_estimate() + extra_margin

# Горизонтальная досягаемость при заданном DY (vx — эффективная горизонтальная)
func _max_horizontal_range_for_dy(dy: float, vx: float) -> float:
	var g: float = absf(_cfg_gravity())
	var v0: float = _cfg_jump_speed()
	var fm: float = max(1.0, fall_multiplier)

	if g <= 0.0 or vx <= 0.0 or v0 <= 0.0:
		return 0.0

	var h: float = (v0 * v0) / (2.0 * g)

	if dy > 0.0:
		if dy > h:
			return 0.0
		var t_up: float = v0 / g
		var gd: float = g * fm
		var t_down: float = sqrt(max(0.0, 2.0 * (h - dy) / gd))
		return vx * max(0.0, t_up + t_down)

	if absf(dy) <= 1e-5:
		var t_up0: float = v0 / g
		var t_down0: float = v0 / (g * sqrt(fm))
		return vx * max(0.0, t_up0 + t_down0)

	var drop_extra: float = -dy
	var gd1: float = g * fm
	var t_up1: float = v0 / g
	var t_down1: float = sqrt(max(0.0, 2.0 * (h + drop_extra) / gd1))
	return vx * max(0.0, t_up1 + t_down1)

func perform_jump(hx: float, ensure_step: bool = false, respect_cooldown: bool = true) -> bool:
	if body == null:
		return false
	var cap: float = _cfg_walk_speed() * _cfg_jump_horiz_mult()
	hx = clamp(hx, -cap, cap)
	var on_ground_now: bool = is_on_ground()
	var can_coyote: bool = _coyote_t > 0.0
	var can_jump_now: bool = on_ground_now or can_coyote

	if respect_cooldown and _jump_cd_left > 0.0:
		# Не ставим повторную заявку во время кулдауна, чтобы не было второго прыжка после приземления.
		_pending_hx = 0.0
		_jump_buf_t = 0.0
		return false

	if not can_jump_now:
		_pending_hx = hx
		_jump_buf_t = maxf(_jump_buf_t, jump_buffer)
		if ensure_step:
			baseline_step()
		_mark_blocked_for_anim()
		_dbg("QUEUE perform_jump (no ground/coyote) for %.2fs" % _jump_buf_t)
		return false

	_do_jump(hx)
	_pending_hx = 0.0
	_jump_buf_t = 0.0
	_jump_cd_left = _cfg_jump_cooldown()
	_dbg("JUMP fired hx=%.3f (cap≤%.3f)" % [hx, cap])
	return true

# =============================================================================
# EDGE-HOLD / ВАЛИДАЦИЯ / СПУСК
# =============================================================================
func _mark_step_done() -> void:
	_last_step_frame = Engine.get_physics_frames()

func _has_stepped_this_frame() -> bool:
	return _last_step_frame == Engine.get_physics_frames()

func _mark_blocked_for_anim() -> void:
	_just_blocked_jump_frames = 2

func _edge_safety_guard() -> void:
	if body == null or not is_on_ground():
		return
	if _post_jump_edge_ignore_t > 0.0:
		return

	var dirf: float = _dirf()
	var near_edge: bool = _is_imminent_gap_ahead(edge_jump_trigger_forward, max(gap_probe_down, 1.2))
	if not near_edge:
		return

	var can_jump: bool = (allow_gap_jumps and _can_clear_measured_gap(dirf))
	if can_jump and _jump_cd_left <= 0.0:
		_jump_forward_walk(dirf)
	else:
		_start_edge_hold(dirf, _cfg_walk_speed(), dirf * _cfg_walk_speed())

func _try_wall_hop_towards_player() -> bool:
	var acc_key: StringName = &"_hop_acc"
	var acc: float = 0.0
	if has_meta(acc_key):
		var m: Variant = get_meta(acc_key)
		if (typeof(m) == TYPE_FLOAT or typeof(m) == TYPE_INT):
			acc = float(m)
	var dt: float = 1.0 / float(Engine.get_physics_ticks_per_second())
	acc += dt
	set_meta(acc_key, acc)

	var interval: float = max(0.05, env_probe_interval)
	if acc < interval:
		return false
	set_meta(acc_key, 0.0)

	if actor == null or body == null:
		return false

	var dir: int = int(actor.facing_dir)
	var player_ahead: bool = true
	if _perc != null and _perc.has_target:
		var p: Node3D = _perc.get_player() as Node3D
		if p != null:
			var ex: float = body.global_position.x
			var px: float = p.global_position.x
			player_ahead = (dir > 0 and px > ex) or (dir < 0 and px < ex)
	if not player_ahead:
		return false

	if allow_upward_jumps and (not require_player_above_for_upward or _has_chase_reason(_dirf())):
		if _needs_step_up_ahead() and _has_valid_landing_ahead(_dirf()):
			return _jump_forward_walk(_dirf())

	var gap: bool = _is_imminent_gap_ahead(edge_jump_trigger_forward, max(gap_probe_down, 1.0))
	if gap and allow_gap_jumps and _can_clear_measured_gap(_dirf()):
		return _jump_forward_walk(_dirf())

	return false

func _start_edge_hold(dirf: float, run_v: float, hx: float) -> void:
	_edge_hold_active = true
	_edge_hold_dir = dirf
	_edge_hold_run_v = run_v
	_pending_hx = hx
	_edge_hold_no_gap_t = 0.0
	if body != null:
		_edge_snap_backup = body.floor_snap_length
		body.floor_snap_length = max(body.floor_snap_length, 0.6)
	_mark_blocked_for_anim()

func _stop_edge_hold() -> void:
	_edge_hold_active = false
	_edge_hold_dir = 0.0
	_edge_hold_run_v = 0.0
	_edge_hold_no_gap_t = 0.0
	if body != null:
		body.floor_snap_length = _edge_snap_backup

func _set_pending_reason(r: int) -> void:
	_pending_reason = r

func _cancel_pending_jump(why: String) -> void:
	_pending_hx = 0.0
	_jump_buf_t = 0.0
	if _edge_hold_active:
		_stop_edge_hold()
	_dbg("CANCEL pending jump: " + why)
	_pending_reason = JUMP_REASON_NONE

func _validate_pending_jump() -> void:
	if _jump_buf_t <= 0.0:
		return
	var dirf: float = _dirf()
	if _pending_reason == JUMP_REASON_GAP:
		var still_gap: bool = _is_imminent_gap_ahead(edge_jump_trigger_forward, max(gap_probe_down, 1.2))
		if _edge_hold_active:
			if still_gap:
				_edge_hold_no_gap_t = 0.0
			else:
				_edge_hold_no_gap_t += _last_delta
				if _edge_hold_no_gap_t >= 0.20:
					_cancel_pending_jump("gap resolved")
			return
		if not still_gap:
			_cancel_pending_jump("gap resolved")
	elif _pending_reason == JUMP_REASON_CHASE:
		if not _has_chase_reason(dirf):
			_cancel_pending_jump("chase invalidated")
	elif _pending_reason == JUMP_REASON_NEED:
		if not _has_need_overcome(dirf):
			_cancel_pending_jump("obstacle gone")

# Спуск к игроку
func consider_drop_to_player() -> void:
	if not allow_drop_down or body == null or _perc == null or not _perc.has_target:
		return
	if is_on_air() or _drop_active or _drop_cd_t > 0.0:
		return
	if _is_imminent_gap_ahead(edge_jump_trigger_forward, max(gap_probe_down, 1.2)):
		return

	var p: Node3D = _perc.get_player() as Node3D
	if p == null:
		return
	var dy: float = body.global_position.y - p.global_position.y
	if dy <= 0.05:
		return
	var max_drop: float = max_safe_drop_multiplier * max_jump_height_estimate()
	if dy > max_drop:
		return
	var dx: float = absf(p.global_position.x - body.global_position.x)
	if dx > chase_jump_max_dist_x:
		return
	start_drop_through()

# =============================================================================
# ЛОГИКА «НУЖНЫ ЛИ ПРЕОДОЛЕНИЯ»
# =============================================================================
func _has_need_overcome(dirf: float) -> bool:
	if _is_wall_ahead(0.5, 0.9):
		return true
	if _is_imminent_gap_ahead(edge_jump_trigger_forward, max(gap_probe_down, 1.0)):
		return true
	var self_y: float = body.global_position.y
	var lip_v: Variant = _probe_lip_height_ahead(0.6, 0.9, 2.5)
	if lip_v != null:
		var lip_y: float = float(lip_v)
		var dy: float = lip_y - self_y
		if dy > 0.28 and _can_reach_y_with_jumps(self_y, lip_y, 1, 0.22):
			return true
	return false

func _has_chase_reason(dirf: float) -> bool:
	if _perc == null or not _perc.has_target:
		return false
	var p := _perc.get_player()
	if p == null:
		return false
	if p.has_method("is_on_floor"):
		var grounded: bool = bool(p.call("is_on_floor"))
		if not grounded:
			return false
	var ahead: bool = (dirf > 0.0 and p.global_position.x > body.global_position.x) \
		or (dirf < 0.0 and p.global_position.x < body.global_position.x)
	if not ahead:
		return false
	var dx: float = absf(p.global_position.x - body.global_position.x)
	var dy: float = p.global_position.y - body.global_position.y
	return dx <= chase_jump_max_dist_x and dy >= chase_jump_min_dy

func _can_reach_y_with_jumps(self_y: float, target_y: float, jumps_available: int = 1, extra_margin: float = 0.20) -> bool:
	var gap: float = absf(target_y - self_y)
	return gap <= (max_jump_height_estimate() + extra_margin)

# =============================================================================
# КОНФИГ-ГЕТТЕРЫ
# =============================================================================
func _cfg_walk_speed() -> float:
	if cfg != null:
		var v: Variant = cfg.get("walk_speed")
		return float(v) if v != null else 0.0
	return 0.0

func _cfg_run_speed() -> float:
	if cfg != null:
		var v: Variant = cfg.get("run_speed")
		return float(v) if v != null else 0.0
	return 0.0

func _cfg_accel() -> float:
	if cfg != null:
		var v: Variant = cfg.get("accel")
		return float(v) if v != null else 0.0
	return 0.0

func _cfg_decel() -> float:
	if cfg != null:
		var v: Variant = cfg.get("decel")
		return float(v) if v != null else 0.0
	return 0.0

func _cfg_approach_min() -> float:    return (cfg.approach_min if cfg != null else 1.0)
func _cfg_approach_max() -> float:    return (cfg.approach_max if cfg != null else 3.0)
func _cfg_gravity() -> float:         return (cfg.gravity if cfg != null else 25.0)
func _cfg_jump_speed() -> float:      return (cfg.jump_speed if cfg != null else 8.0)
func _cfg_max_fall_speed() -> float:  return (cfg.max_fall_speed if cfg != null else 30.0)

func _cfg_jump_horiz_mult() -> float:
	if cfg == null:
		return 1.0
	var v: Variant = cfg.get("jump_horiz_mult")
	return (float(v) if (v is float or v is int) else 1.0)

func _cfg_jump_cooldown() -> float:
	if cfg == null: return 1.0
	var v: Variant = cfg.get("jump_cooldown")
	return (float(v) if (v is float or v is int) else 1.0)

func _cfg_evade_cooldown() -> float:
	if cfg == null: return 1.0
	var v: Variant = cfg.get("evade_cooldown")
	return (float(v) if (v is float or v is int) else 1.0)

func _cfg_feint_cooldown() -> float:
	if cfg == null: return 2.0
	var v: Variant = cfg.get("feint_cooldown")
	return (float(v) if (v is float or v is int) else 2.0)

func _cfg_evade_back_speed() -> float:
	if cfg == null: return 2.4
	var v: Variant = cfg.get("evade_back_speed")
	return (float(v) if (v is float or v is int) else 2.4)

func _cfg_retreat_margin() -> float:
	if cfg == null:
		return 0.08
	var v: Variant = cfg.get("retreat_margin")
	return (float(v) if (v is float or v is int) else 0.08)


# =============================================================================
# БАЗОВЫЙ ШАГ ФИЗИКИ (для ensure_step=true)
# =============================================================================
func baseline_step() -> void:
	if body == null:
		return
	if _has_stepped_this_frame():
		return
	_apply_vertical()
	body.velocity.z = 0.0
	body.move_and_slide()
	_lock_to_plane()
	_mark_step_done()

# =============================================================================
# ПАТРУЛЬ
# =============================================================================
func _should_turn_around() -> bool:
	if actor == null or body == null:
		return false
	var world: World3D = actor.get_world_3d()
	if world == null:
		return false

	var interval: float = 0.05
	if not self.has_meta("_turn_acc"): self.set_meta("_turn_acc", 0.0)
	if not self.has_meta("_turn_cached"): self.set_meta("_turn_cached", false)
	if not self.has_meta("_turn_last_dir"): self.set_meta("_turn_last_dir", actor.facing_dir)

	var acc: float = float(self.get_meta("_turn_acc"))
	var cached: bool = bool(self.get_meta("_turn_cached"))
	var last_dir: int = int(self.get_meta("_turn_last_dir"))

	if last_dir != actor.facing_dir:
		last_dir = actor.facing_dir
		acc = interval

	var dt: float = 1.0 / float(Engine.get_physics_ticks_per_second())
	acc += dt

	if acc >= interval:
		acc = 0.0
		var space: PhysicsDirectSpaceState3D = world.direct_space_state
		var origin: Vector3 = body.global_transform.origin
		var dirx: float = float(actor.facing_dir)

		var start_floor: Vector3 = origin + Vector3(dirx * patrol_turn_forward, 0.2, 0.0)
		var end_floor:   Vector3 = origin + Vector3(dirx * patrol_turn_forward, -patrol_turn_down, 0.0)
		var qf := PhysicsRayQueryParameters3D.new()
		qf.from = start_floor
		qf.to = end_floor
		qf.collide_with_areas = true
		qf.collide_with_bodies = true
		qf.exclude = [body.get_rid()]
		var res_floor: Dictionary = space.intersect_ray(qf)
		var floor_ok: bool = not res_floor.is_empty()

		var start_wall: Vector3 = origin + Vector3(dirx * 0.6, 0.5, 0.0)
		var end_wall:   Vector3 = start_wall + Vector3(dirx * 0.5, 0.0, 0.0)
		var qw := PhysicsRayQueryParameters3D.new()
		qw.from = start_wall
		qw.to = end_wall
		qw.collide_with_areas = true
		qw.collide_with_bodies = true
		qw.exclude = [body.get_rid()]
		var res_wall: Dictionary = space.intersect_ray(qw)
		var wall_block: bool = not res_wall.is_empty()

		cached = (not floor_ok) or wall_block

	self.set_meta("_turn_acc", acc)
	self.set_meta("_turn_cached", cached)
	self.set_meta("_turn_last_dir", last_dir)
	return cached
