extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_ApproachState

# --- Параметры сближения (для движения) ---
var _desired: float = 0.30
const FAR_SPEED_FACTOR: float = 1.00
const NEAR_SPEED_FACTOR: float = 0.60
const NEAR_MARGIN: float = 0.10

@export var jump_delay_min: float = 2.0
@export var jump_delay_max: float = 3.0
@export var near_x_for_jump: float = 2.0

var _jump_arm: bool = false
var _jump_delay_t: float = 0.0
var _air_anim_state: int = 0 # 0=ground, 1=jump, 2=fall

var _stuck_timer: float = 0.0
var _last_dx: float = INF
const STUCK_TIME: float = 0.5
const STUCK_EPS: float = 0.01
const STUCK_BOOST: float = 1.25

# --- ТРИГГЕР РЕШЕНИЯ АТАКИ (ОТДЕЛЬНО ОТ БОЕВОГО ОКНА) ---
@export var attack_trigger_hb_path: NodePath
var _attack_trigger_area: Area3D = null
var _player_in_trigger: bool = false
var _player_cached_body: CharacterBody3D = null

# --- Геометрические гейты к триггеру ---
@export var attack_max_y_diff: float = 0.45   # макс разница по высоте для разрешения атаки
@export var attack_max_z_diff: float = 0.35   # допуск по Z
@export var require_front_facing: bool = true # атаковать только вперёд по facing_dir
@export var min_front_x_dot: float = 0.02     # минимальное "вперёд по X"

# --- Порог для допуска к атаке, если почти нет вертикальной скорости ---
@export var airborne_vy_hysteresis: float = 0.10

# --- Периодический рефреш поиска/подписок триггера ---
var _trigger_refresh_accum: float = 0.0
const TRIGGER_REFRESH_INTERVAL: float = 0.5

# ---------- ПОИСК/ПОДПИСКИ НА ТРИГГЕР ----------

func _find_attack_trigger_area() -> Area3D:
	if owner != null and String(attack_trigger_hb_path) != "":
		var n: Node = owner.get_node_or_null(attack_trigger_hb_path)
		if n is Area3D:
			return n as Area3D
	if owner != null:
		var q: Array[Node] = [owner]
		while not q.is_empty():
			var cur: Node = q.pop_front()
			if cur is Area3D and cur.name == "AttackTriggerHB":
				return cur as Area3D
			for c in cur.get_children():
				if c != null:
					q.append(c)
	return null

func _get_player_body() -> CharacterBody3D:
	if _player_cached_body != null and is_instance_valid(_player_cached_body):
		return _player_cached_body
	if perception == null or not perception.has_target:
		return null
	var pl: Node = perception.get_player()
	if pl == null:
		return null
	if pl.has_method("get"):
		var pl_body: CharacterBody3D = pl.get("body") as CharacterBody3D
		if pl_body != null:
			_player_cached_body = pl_body
			return pl_body
	_player_cached_body = pl as CharacterBody3D
	return _player_cached_body

func _bind_trigger_signals(a: Area3D) -> void:
	if a == null:
		return
	a.monitoring = true
	a.monitorable = true
	if not a.body_entered.is_connected(_on_trigger_body_enter):
		a.body_entered.connect(_on_trigger_body_enter)
	if not a.body_exited.is_connected(_on_trigger_body_exit):
		a.body_exited.connect(_on_trigger_body_exit)
	if not a.area_entered.is_connected(_on_trigger_area_enter):
		a.area_entered.connect(_on_trigger_area_enter)
	if not a.area_exited.is_connected(_on_trigger_area_exit):
		a.area_exited.connect(_on_trigger_area_exit)

func _ensure_trigger_ready() -> void:
	if _attack_trigger_area == null or not is_instance_valid(_attack_trigger_area):
		_attack_trigger_area = _find_attack_trigger_area()
	if _attack_trigger_area != null:
		_bind_trigger_signals(_attack_trigger_area)
		# первичный опрос (если игрок уже внутри)
		var pb: CharacterBody3D = _get_player_body()
		_player_in_trigger = false
		if pb != null:
			var bodies: Array[Node3D] = _attack_trigger_area.get_overlapping_bodies()
			for b in bodies:
				if b == pb:
					_player_in_trigger = true
					break
			if not _player_in_trigger:
				var pnode: Node = perception.get_player() if perception != null else null
				var areas: Array[Area3D] = _attack_trigger_area.get_overlapping_areas()
				for ar in areas:
					if pnode != null and ar == pnode:
						_player_in_trigger = true
						break
	else:
		_player_in_trigger = false

func _on_trigger_body_enter(other_body: Node) -> void:
	var pb: CharacterBody3D = _get_player_body()
	if pb != null and other_body == pb:
		_player_in_trigger = true

func _on_trigger_body_exit(other_body: Node) -> void:
	var pb: CharacterBody3D = _get_player_body()
	if pb != null and other_body == pb:
		_player_in_trigger = false

func _on_trigger_area_enter(area: Area3D) -> void:
	var pn: Node = perception.get_player() if perception != null else null
	if pn != null and area == pn:
		_player_in_trigger = true

func _on_trigger_area_exit(area: Area3D) -> void:
	var pn: Node = perception.get_player() if perception != null else null
	if pn != null and area == pn:
		_player_in_trigger = false

# ---------- ГЕОМЕТРИЯ / ЮТИЛЫ ----------

func _first_half_width_under(root: Node) -> float:
	var q: Array[Node] = [root]
	while not q.is_empty():
		var n: Node = q.pop_front()
		if n is CollisionShape3D:
			var cs: CollisionShape3D = n
			if cs.shape != null:
				if cs.shape is BoxShape3D:
					var box: BoxShape3D = cs.shape
					return max(0.0, float(box.size.x) * 0.5)
				elif cs.shape is CapsuleShape3D:
					var cap: CapsuleShape3D = cs.shape
					return max(0.0, float(cap.radius))
				elif cs.shape is CylinderShape3D:
					var cyl: CylinderShape3D = cs.shape
					return max(0.0, float(cyl.radius))
				elif cs.shape is SphereShape3D:
					var sph: SphereShape3D = cs.shape
					return max(0.0, float(sph.radius))
		for c in n.get_children():
			var cn: Node = c
			if cn != null:
				q.append(cn)
	return 0.0

func _edge_dx_along_x(self_body: CharacterBody3D, other_node: Node3D) -> float:
	if self_body == null or other_node == null:
		return INF
	var ex: float = self_body.global_transform.origin.x
	var ox: float = other_node.global_transform.origin.x
	var half_self: float = _first_half_width_under(self_body)
	var half_other: float = _first_half_width_under(other_node)
	var raw: float = absf(ox - ex) - half_self - half_other
	return maxf(0.0, raw)

# ---------- ГЕЙТЫ К ТРИГГЕРУ ----------

func _same_height_ok(self_pos: Vector3, player_pos: Vector3) -> bool:
	return absf(player_pos.y - self_pos.y) <= attack_max_y_diff

func _z_alignment_ok(self_pos: Vector3, player_pos: Vector3) -> bool:
	return absf(player_pos.z - self_pos.z) <= attack_max_z_diff

func _in_front_ok(self_pos: Vector3, player_pos: Vector3) -> bool:
	if not require_front_facing or owner == null:
		return true
	var f: int = 1
	if owner != null and owner.has_method("get"):
		var v = owner.get("facing_dir")
		if v != null:
			f = int(v)
	var to_player_x: float = player_pos.x - self_pos.x
	return (to_player_x * float(f)) > min_front_x_dot

# ---------- FSM HOOKS ----------

func enter() -> void:
	if config != null:
		_desired = maxf(0.0, float(config.approach_min) - float(config.approach_side_offset))
	else:
		_desired = 0.30
	_stuck_timer = 0.0
	_last_dx = INF
	_air_anim_state = 0
	_trigger_refresh_accum = 0.0

	if body:
		body.velocity.x = 0.0

	_ensure_trigger_ready()

	if anim != null:
		anim.play_walk()

func update(dt: float) -> void:
	# Периодически освежаем триггер
	_trigger_refresh_accum += dt
	if _trigger_refresh_accum >= TRIGGER_REFRESH_INTERVAL:
		_trigger_refresh_accum = 0.0
		_ensure_trigger_ready()

	# Хендовер-лок
	if owner != null and owner.has_method("get") and owner.get("handover_lock") == true:
		return

	if perception == null or not perception.has_target:
		owner._change_state(Cossack_01_IdleState.new(owner))
		return

	var pl: Node3D = perception.get_player()
	if pl == null or body == null:
		owner._change_state(Cossack_01_IdleState.new(owner))
		return

	# Ленивая инициализация locomotion
	if locomotion == null and owner.has_method("get"):
		var loco: EnemyLocomotion = owner.get("locomotion") as EnemyLocomotion
		if loco != null:
			locomotion = loco

	# Попытка хопа через стену
	if locomotion != null and locomotion.has_method("try_wall_hop_over_wall") and locomotion.try_wall_hop_over_wall():
		if anim != null:
			anim.play_jump()
			_air_anim_state = 1
		return

	# Позиции
	var self_pos: Vector3 = body.global_position
	var player_pos: Vector3 = pl.global_position
	if pl.has_method("get"):
		var pl_body: CharacterBody3D = pl.get("body") as CharacterBody3D
		if pl_body != null:
			player_pos = pl_body.global_position
	var to_vec: Vector3 = player_pos - self_pos

	# Вертикальная логика/прыжок
	if locomotion != null and body != null:
		var dx_h: float = absf(player_pos.x - self_pos.x)
		var player_above: bool = locomotion.has_method("is_above") and locomotion.is_above(self_pos.y, player_pos.y, 0.10)
		var player_below: bool = locomotion.has_method("is_below") and locomotion.is_below(self_pos.y, player_pos.y, 0.20)
		var can_reach:  bool = locomotion.has_method("can_reach_y") and locomotion.can_reach_y(self_pos.y, player_pos.y, 0.20)

		var can_jump_now: bool = player_above and can_reach and (dx_h <= near_x_for_jump)
		if can_jump_now:
			if not _jump_arm:
				_jump_arm = true
				_jump_delay_t = randf_range(jump_delay_min, jump_delay_max)
			else:
				_jump_delay_t = maxf(0.0, _jump_delay_t - dt)
				if _jump_delay_t <= 0.0 and locomotion.has_method("perform_jump"):
					var dir_sign: float = signf(player_pos.x - self_pos.x)
					var x_thresh: float = 0.20
					var hx: float = 0.0
					if dx_h > x_thresh:
						var base_speed: float = (config.walk_speed if config != null else 1.5)
						hx = dir_sign * base_speed
					locomotion.perform_jump(hx)
					_jump_arm = false
					if anim != null:
						anim.play_jump()
						_air_anim_state = 1
		else:
			_jump_arm = false
			_jump_delay_t = 0.0

		if locomotion.has_method("is_on_ground") and locomotion.is_on_ground() and player_below and dx_h <= near_x_for_jump and locomotion.has_method("start_drop_through"):
			locomotion.start_drop_through()

		# Синхронизация воздух/земля
		var on_ground_now: bool = (locomotion.has_method("is_on_ground") and locomotion.is_on_ground())
		if not on_ground_now:
			var up_pos: bool = true
			if locomotion.has_method("uses_positive_up"):
				up_pos = locomotion.uses_positive_up()
			var vy: float = body.velocity.y
			var going_up: bool = (vy > 0.1) if up_pos else (vy < -0.1)
			if going_up:
				if _air_anim_state != 1 and anim != null:
					anim.play_jump()
					_air_anim_state = 1
			else:
				if _air_anim_state != 2 and anim != null:
					anim.play_fall()
					_air_anim_state = 2
		else:
			if _air_anim_state != 0 and anim != null:
				var speed_x: float = absf(body.velocity.x)
				var IDLE_THR: float = 0.03
				var WALK_THR: float = 0.06
				if speed_x >= WALK_THR:
					anim.play_walk()
				elif speed_x <= IDLE_THR:
					anim.play_idle()
				else:
					anim.play_walk()
			_air_anim_state = 0

	# Цель подводки
	var target: Vector3 = _compute_desired_stop_pos(dt)

	# Фейс к игроку
	if owner != null and owner.has_method("set_facing_dir"):
		var dir_face: float = signf(to_vec.x)
		owner.set_facing_dir(int(dir_face))

	# Геометрия
	var dx_edge_to_player: float = _edge_dx_along_x(body, pl)
	var dx_to_target: float = absf(target.x - self_pos.x)
	var dir_to_target: float = signf(target.x - self_pos.x)

	# Скорости/окна
	var base_speed_move: float = (config.walk_speed if config != null else 1.5)
	var x_window_cfg: float = _cfg_approach_x_window()
	var x_window: float = maxf(0.10, x_window_cfg)
	var speed_factor: float = (NEAR_SPEED_FACTOR if dx_to_target <= NEAR_MARGIN else FAR_SPEED_FACTOR)

	# Анти-залип
	_stuck_timer += dt
	if absf(dx_to_target - _last_dx) < STUCK_EPS:
		if _stuck_timer >= STUCK_TIME:
			speed_factor *= STUCK_BOOST
	else:
		_stuck_timer = 0.0
	_last_dx = dx_to_target

	# --- РЕШЕНИЕ ОБ АТАКЕ ---
	var can_attack_pose: bool = true
	if locomotion != null and body != null and locomotion.has_method("is_on_ground"):
		can_attack_pose = locomotion.is_on_ground() or absf(body.velocity.y) < airborne_vy_hysteresis

	var should_attack: bool = false
	if _attack_trigger_area != null:
		# триггер + гейты по высоте/фронту/оси Z
		should_attack = _player_in_trigger
		should_attack = should_attack and _same_height_ok(self_pos, player_pos)
		should_attack = should_attack and _z_alignment_ok(self_pos, player_pos)
		should_attack = should_attack and _in_front_ok(self_pos, player_pos)
	else:
		# Фолбэк (если триггера нет): окно дистанций + те же гейты
		var x_win: float = (config.attack_x_window if config != null else 0.18)
		var z_win: float = (config.attack_z_window if config != null else attack_max_z_diff)
		var dz: float = absf(player_pos.z - self_pos.z)
		should_attack = (absf(dx_edge_to_player) <= x_win and dz <= z_win)
		should_attack = should_attack and _same_height_ok(self_pos, player_pos)
		should_attack = should_attack and _in_front_ok(self_pos, player_pos)

	if can_attack_pose and should_attack:
		body.velocity.x = 0.0
		if not (owner.state is Cossack_01_AttackState):
			owner._change_state(Cossack_01_AttackState.new(owner))
		return

	# --- ИНАЧЕ: обычное сближение ---
	if locomotion != null and locomotion.has_method("is_on_ground") and locomotion.is_on_ground() and dx_to_target > (x_window + 0.02):
		body.velocity.x = dir_to_target * base_speed_move * speed_factor
		if anim != null:
			anim.play_walk()
	elif locomotion != null and locomotion.has_method("is_on_ground") and locomotion.is_on_ground() and dx_to_target <= x_window:
		body.velocity.x = 0.0
		if anim != null:
			anim.play_idle()
	else:
		# в воздухе — не трогаем импульс
		pass

	# Подстройка желаемой дистанции
	if config != null and dx_edge_to_player > float(config.approach_max):
		_desired = maxf(0.0, float(config.approach_min) - float(config.approach_side_offset))
	elif config != null and dx_edge_to_player < float(config.approach_min) * 0.85:
		_desired = maxf(0.0, float(config.approach_min) - float(config.approach_side_offset))

func exit() -> void:
	if body:
		body.velocity.x = 0.0

# ---------- Хелперы owner-конфига ----------

func _owner_bool(o: Node, name: String) -> bool:
	if o != null and o.has_method("get"):
		var v = o.get(name)
		return v == true
	return false

func _owner_float(o: Node, name: String, fallback: float) -> float:
	if o != null and o.has_method("get"):
		var v = o.get(name)
		if v != null:
			return float(v)
	return fallback

func _cfg_approach_stop_x() -> float:
	var o := owner as EnemyCossack
	var from_cfg: float = (config.approach_stop_x if config != null else 0.35)
	if _owner_bool(o, "use_distance_overrides"):
		return _owner_float(o, "approach_stop_x_override", from_cfg)
	return from_cfg

func _cfg_approach_x_window() -> float:
	var o := owner as EnemyCossack
	var from_cfg: float = (config.approach_x_window if config != null else 0.10)
	if _owner_bool(o, "use_distance_overrides"):
		return _owner_float(o, "approach_x_window_override", from_cfg)
	return from_cfg

func _compute_desired_stop_pos(dt: float) -> Vector3:
	var o := owner as EnemyCossack
	if o == null:
		return Vector3.ZERO

	var player_pos: Vector3 = Vector3.ZERO
	if o.Perception != null and o.Perception.has_method("get_player"):
		var p: Node3D = o.Perception.get_player()
		if p != null and is_instance_valid(p):
			player_pos = p.global_position

	var default_stop_pos: Vector3 = (o.Body.global_position if o.Body != null else o.global_position)
	var stop_x_local: float = _cfg_approach_stop_x()
	var dir: int = (o.facing_dir if o.facing_dir != 0 else -1)
	default_stop_pos.x = player_pos.x - float(dir) * stop_x_local
	default_stop_pos.z = (o.Body.global_position.z if o.Body != null else default_stop_pos.z)
	default_stop_pos.y = (o.Body.global_position.y if o.Body != null else default_stop_pos.y)

	if o != null and o.has_method("get_chaotic_approach_target"):
		return o.get_chaotic_approach_target(player_pos, default_stop_pos, dt)
	return default_stop_pos
