extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_ApproachState

var _desired: float = 0.30

const FAR_SPEED_FACTOR: float = 1.00
const NEAR_SPEED_FACTOR: float = 0.60
const NEAR_MARGIN: float = 0.10

@export var jump_delay_min: float = 2.0      # мин задержки перед прыжком (сек)
@export var jump_delay_max: float = 3.0      # макс задержки перед прыжком (сек)
@export var near_x_for_jump: float = 2.0     # допуск по X, на котором допускается прыжок/спрыгивание

var _jump_arm: bool = false
var _jump_delay_t: float = 0.0

var _air_anim_state: int = 0  # 0=ground, 1=jump, 2=fall

var _stuck_timer: float = 0.0
var _last_dx: float = INF
const STUCK_TIME: float = 0.5
const STUCK_EPS: float = 0.01
const STUCK_BOOST: float = 1.25


func _first_half_width_under(root: Node) -> float:
	var q: Array[Node] = [root]
	while not q.is_empty():
		var n: Node = q.pop_front()
		if n is CollisionShape3D:
			var cs: CollisionShape3D = n
			if cs.shape != null:
				if cs.shape is BoxShape3D:
					var box: BoxShape3D = cs.shape
					return max(0.0, float(box.size.x) * 0.5) # Godot 4: size, не extents
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


func enter() -> void:
	if config != null:
		_desired = maxf(0.0, float(config.approach_min) - float(config.approach_side_offset))
	else:
		_desired = 0.30
	_stuck_timer = 0.0
	_last_dx = INF
	_air_anim_state = 0
	if body:
		body.velocity.x = 0.0
	if anim:
		anim.play_walk()


func update(dt: float) -> void:
	# Хендовер-лок
	if owner and owner.has_method("get") and owner.get("handover_lock") == true:
		return

	if perception == null or not perception.has_target:
		owner._change_state(Cossack_01_IdleState.new(owner))
		return

	var pl := perception.get_player()
	if pl == null or body == null:
		owner._change_state(Cossack_01_IdleState.new(owner))
		return

	# Ленивая инициализация locomotion (строгая типизация)
	if locomotion == null and owner.has_method("get"):
		var loco: EnemyLocomotion = owner.get("locomotion") as EnemyLocomotion
		if loco != null:
			locomotion = loco

	# Хоп через стену (если реально упёрлись) — ранний выход, чтобы не перезатереть скорости прыжка
	if locomotion != null and locomotion.try_wall_hop_over_wall():
		if anim != null:
			anim.play_jump()
			_air_anim_state = 1
		return

	# --- позиции ТЕЛ ---
	var self_pos: Vector3 = body.global_position
	var player_pos: Vector3 = pl.global_position
	if pl.has_method("get"):
		var pl_body: CharacterBody3D = pl.get("body") as CharacterBody3D
		if pl_body != null:
			player_pos = pl_body.global_position

	var to_vec: Vector3 = player_pos - self_pos

	# --- Решения AI (вертикальные предикаты — через locomotion) ---
	if locomotion != null and body != null:
		var dx_h: float = absf(player_pos.x - self_pos.x)

		var player_above: bool = locomotion.is_above(self_pos.y, player_pos.y, 0.10)
		var player_below: bool = locomotion.is_below(self_pos.y, player_pos.y, 0.20)
		var can_reach:  bool = locomotion.can_reach_y(self_pos.y, player_pos.y, 0.20)

		# Задержка перед прыжком (случайно 2–3 сек)
		var can_jump_now: bool = player_above and can_reach and (dx_h <= near_x_for_jump)
		if can_jump_now:
			if not _jump_arm:
				_jump_arm = true
				_jump_delay_t = randf_range(jump_delay_min, jump_delay_max)
			else:
				_jump_delay_t = maxf(0.0, _jump_delay_t - dt)
				if _jump_delay_t <= 0.0:
					# === Горизонтальная добавка из базовой скорости ===
					var dir_sign: float = signf(player_pos.x - self_pos.x)
					var x_thresh: float = 0.20  # если совсем «над головой» — прыгаем вертикально
					var hx: float = 0.0
					if dx_h > x_thresh:
						var base_speed: float = (config.walk_speed if config != null else 1.5)
						hx = dir_sign * base_speed

					# старт прыжка (вверх + при необходимости вперёд с базовой скоростью)
					locomotion.perform_jump(hx)
					_jump_arm = false

					# --- Анимация прыжка (однократно при старте) ---
					if anim != null:
						anim.play_jump()
						_air_anim_state = 1
		else:
			_jump_arm = false
			_jump_delay_t = 0.0

		# Спрыгивание (кулдаун и безопасность — внутри locomotion)
		if locomotion.is_on_ground() and player_below and dx_h <= near_x_for_jump:
			locomotion.start_drop_through()

		# --- СИНХРОНИЗАЦИЯ ВОЗДУХ/ЗЕМЛЯ (фикс "залипа" Jump/Fall) ---
		var on_ground_now: bool = locomotion.is_on_ground()
		if not on_ground_now:
			# В воздухе — выбираем Jump/Fall по знаку VY, но не спамим
			var up_pos: bool = true
			if "uses_positive_up" in locomotion:
				up_pos = locomotion.uses_positive_up()
			var vy: float = body.velocity.y
			var going_up: bool = (vy > 0.1) if up_pos else (vy < -0.1)

			if going_up:
				if _air_anim_state != 1 and anim != null:
					anim.play_jump()   # единоразово
					_air_anim_state = 1
			else:
				if _air_anim_state != 2 and anim != null:
					anim.play_fall()   # единоразово
					_air_anim_state = 2
		else:
			# === Только что приземлились? Был воздух (1/2) → теперь земля (0)
			if _air_anim_state != 0 and anim != null:
				var speed_x: float = absf(body.velocity.x)
				# Локальные пороги для земли (гистерезис)
				var IDLE_THR: float = 0.03
				var WALK_THR: float = 0.06

				if speed_x >= WALK_THR:
					anim.play_walk()
				elif speed_x <= IDLE_THR:
					anim.play_idle()
				else:
					# «Мёртвая зона»: по умолчанию включим walk
					anim.play_walk()

			_air_anim_state = 0  # СБРОС — больше не в воздухе

	# === ЦЕЛЬ ПОДВЕДЕНИЯ С УЧЁТОМ «ХАОСА» ===
	var target: Vector3 = _compute_desired_stop_pos(dt)

	# Для фейса — смотрим на игрока (как было); для движения — тянемся к target
	var dir_face: float = signf(to_vec.x)
	if "set_facing_dir" in owner:
		owner.set_facing_dir(int(dir_face))

	# «Эдж»-дистанция до игрока (нужна для логики атаки/перенастройки desired)
	var dx_edge_to_player: float = _edge_dx_along_x(body, pl)

	# Дистанция до целевой X-точки (куда хотим прийти)
	var dx_to_target: float = absf(target.x - self_pos.x)
	var dir_to_target: float = signf(target.x - self_pos.x)

	# Базовая скорость + x-window по конфигу
	var base_speed_move: float = (config.walk_speed if config != null else 1.5)
	var x_window_cfg: float = _cfg_approach_x_window()
	var x_window: float = maxf(0.10, x_window_cfg)

	# Плавное замедление около цели
	var speed_factor: float = FAR_SPEED_FACTOR
	if dx_to_target <= NEAR_MARGIN:
		speed_factor = NEAR_SPEED_FACTOR

	# Анти-залипание относительно ЦЕЛЕВОЙ точки
	_stuck_timer += dt
	if absf(dx_to_target - _last_dx) < STUCK_EPS:
		if _stuck_timer >= STUCK_TIME:
			speed_factor *= STUCK_BOOST
	else:
		_stuck_timer = 0.0
	_last_dx = dx_to_target

	# --- ДВИЖЕНИЕ ПО Х ---
	# ВАЖНО: пока в воздухе — не трогаем горизонтальную скорость,
	# чтобы не перезатирать импульс прыжка.
	var can_ground_move: bool = (locomotion != null and locomotion.is_on_ground())

	if can_ground_move and dx_to_target > (x_window + 0.02):
		body.velocity.x = dir_to_target * base_speed_move * speed_factor
	elif can_ground_move and dx_to_target <= x_window:
		# в окне — тормозим и пробуем атаковать
		body.velocity.x = 0.0
		var ok: bool = can_attack_now()
		if ok:
			if owner.state is Cossack_01_AttackState:
				return
			owner._change_state(Cossack_01_AttackState.new(owner))
			return
	elif can_ground_move:
		# «мёртвая зона» гистерезиса — мягко гасим скорость
		body.velocity.x = lerpf(body.velocity.x, 0.0, 0.5)
	# else: в воздухе — ничего не делаем, сохраняем текущий импульс

	# --- Подстройка желаемой дистанции по исходной логике (относительно игрока) ---
	if config != null and dx_edge_to_player > float(config.approach_max):
		_desired = maxf(0.0, float(config.approach_min) - float(config.approach_side_offset))
	elif config != null and dx_edge_to_player < float(config.approach_min) * 0.85:
		_desired = maxf(0.0, float(config.approach_min) - float(config.approach_side_offset))

func exit() -> void:
	if body:
		body.velocity.x = 0.0


# --- безопасные геттеры свойств owner-а ---
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

func _cfg_attack_x_win() -> float:
	var o := owner as EnemyCossack
	var from_cfg: float = (config.attack_x_window if config != null else 0.18)
	if _owner_bool(o, "use_distance_overrides"):
		return _owner_float(o, "attack_x_window_override", from_cfg)
	return from_cfg

func _cfg_attack_z_win() -> float:
	var o := owner as EnemyCossack
	var from_cfg: float = (config.attack_z_window if config != null else 0.30)
	if _owner_bool(o, "use_distance_overrides"):
		return _owner_float(o, "attack_z_window_override", from_cfg)
	return from_cfg

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

	# позиция игрока
	var player_pos := Vector3.ZERO
	if o.Perception != null and o.Perception.has_method("get_player"):
		var p = o.Perception.get_player()
		if p != null and is_instance_valid(p):
			player_pos = p.global_position

	# базовая точка остановки без хаоса
	var default_stop_pos := (o.Body.global_position if o.Body != null else o.global_position)
	var stop_x_local := _cfg_approach_stop_x()  # ваш существующий хелпер в стейте
	var dir := (o.facing_dir if o.facing_dir != 0 else -1)
	default_stop_pos.x = player_pos.x - float(dir) * stop_x_local
	default_stop_pos.z = (o.Body.global_position.z if o.Body != null else default_stop_pos.z)
	default_stop_pos.y = (o.Body.global_position.y if o.Body != null else default_stop_pos.y)

	# применяем «хаос» врага (тумблер и оверрайды внутри EnemyCossack)
	return o.get_chaotic_approach_target(player_pos, default_stop_pos, dt)
