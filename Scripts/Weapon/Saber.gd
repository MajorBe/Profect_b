extends Node3D
class_name Saber

signal attack_started(clip: StringName, length: float)
signal attack_finished(clip: StringName)

@export var end_buffer_sec: float = 0.3
var _queued_next: bool = false

@export var sword_id: StringName = &"magic_sword_01"

# --- Положение «в руке»: Z < 0 — за спиной (для камеры, смотрящей вдоль -Z)
@export var hold_offset_right: Vector3 = Vector3(0.4, 0.15, -0.06)
@export var hold_offset_left:  Vector3 = Vector3(0.0, 0.15, -0.06)

# Базовый хват (градусы)
@export var grip_rot_deg: Vector3 = Vector3(0.0, 90.0, 0.0)

# Разворот по Y при взгляде влево (обычно 180°)
@export var rotate_y_when_left: float = PI

# Плавность следования
@export var follow_pos_time: float = 0.25
@export var follow_rot_time: float = 0.20

# Idle-качание
@export var idle_sway_amp_rot: Vector3 = Vector3(0.06, 0.12, 0.06)
@export var idle_sway_amp_pos: Vector3 = Vector3(0.0, 0.01, 0.0)
@export var idle_sway_speed: float = 1.8
@export var idle_blend_speed: float = 6.0

# Урон / окно хита (дефолт для fallback)
@export var default_hit_from: float = 0.05
@export var default_hit_to: float = 0.25
@export var base_damage: int = 10

# Инверсия направления (если в Player знак другой)
@export var invert_facing: bool = false

# Профили стойки (stand/crouch)
@export var crouch_offset_delta: Vector3 = Vector3(0.0, -0.12, 0.0)
@export var crouch_grip_add_deg: Vector3 = Vector3(8.0, 0.0, -12.0)
@export var idle_amp_mul_stand: float = 1.0
@export var idle_amp_mul_crouch: float = 0.6
@export var crouch_pos_time_mul: float = 1.20
@export var crouch_rot_time_mul: float = 1.20

# Мультипликаторы инерции
@export var run_pos_time_mul: float = 1.6
@export var run_rot_time_mul: float = 1.4
@export var sprint_pos_time_mul: float = 2.1
@export var sprint_rot_time_mul: float = 1.7
@export var air_up_pos_time_mul: float = 1.8
@export var air_up_rot_time_mul: float = 1.5
@export var air_down_pos_time_mul: float = 2.0
@export var air_down_rot_time_mul: float = 1.6

# «Векторный» лаг
@export var vel_lag_x_per_speed: float = 0.015
@export var vel_lag_y_per_speed: float = 0.020
@export var max_vel_lag_x: float = 0.18
@export var max_vel_lag_y: float = 0.18
@export var vel_deadzone_x: float = 0.05
@export var vel_deadzone_y: float = 0.05

# Доп. наклон клинка в воздухе
@export var air_pitch_up_deg: float = 0.0
@export var air_pitch_down_deg: float = 0.0

# Камера-зависимая глубина
@export var use_camera_depth: bool = false
@export var camera_depth_abs_limit: float = 0.50
@export var cam_refresh_interval: float = 0.25

# Swing поведение
@export var auto_open_window_on_swing: bool = true
@export var allow_interrupt_swing: bool = false

# --- КЛИПЫ / АНИМАТОР / КОМБО ---
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
@export var CLIP_ATTACK1: StringName = &"Attack1"
@export var CLIP_ATTACK2: StringName = &"Attack2"
@export var CLIP_ATTACK3: StringName = &"Attack3"
@export_range(1, 3, 1) var max_combo_steps: int = 3
@export var allow_interrupt_clip: bool = false
@export_range(0.1, 3.0, 0.05) var attack_clip_speed: float = 1.0
@export_range(0.1, 3.0, 0.05) var saber_reset_sec: float = 1.0  # «правило 1 секунды»

# Узлы сцены
@export_node_path("Node3D") var pivot_path: NodePath
@export_node_path("Area3D") var hitbox_path: NodePath
@onready var pivot: Node3D = get_node_or_null(pivot_path) as Node3D
@onready var hitbox: Area3D = get_node_or_null(hitbox_path) as Area3D
@onready var anim: AnimationPlayer = get_node_or_null(animation_player_path) as AnimationPlayer

# Режимы/стойки
const STANCE_STAND: StringName = &"stand"
const STANCE_CROUCH: StringName = &"crouch"
const MODE_IDLE:   StringName = &"idle"
const MODE_RUN:    StringName = &"run"
const MODE_SPRINT: StringName = &"sprint"
const MODE_AIR_UP: StringName = &"air_up"
const MODE_AIR_DN: StringName = &"air_down"

# === ОТДЕЛЬНЫЕ КАНАЛЫ (crouch/jump) ===
const CROUCH_PREF := [&"SaberCrouch1", &"CrouchAttack", &"Crouch1", &"Attack1"]
const JUMP_PREF   := [&"SaberAir1",   &"AirAttack",   &"JumpAttack", &"Air1", &"Attack1"]
var _queued_exact_clip: StringName = &""

# Внутреннее состояние
var _owner_player: Node3D = null
var _target_basis: Basis = Basis.IDENTITY
var _target_pos: Vector3 = Vector3.ZERO
var _facing: int = 1

var _attack_window_task: SceneTreeTimer = null
var _hit_ids: PackedInt64Array = PackedInt64Array() # дедуп по instance_id Health в текущем окне
var _window_token: int = 0

var _stance: StringName = STANCE_STAND
var _move: StringName = MODE_IDLE

# Idle / swing
var _idle_phase: float = 0.0
var _pivot_rest_pos: Vector3 = Vector3.ZERO

var _swing_time: float = 0.0
var _swing_dur: float = 0.0
var _swing_active: bool = false
var _swing_start_basis: Basis = Basis.IDENTITY
var _swing_end_basis: Basis = Basis.IDENTITY

# Камера
var _cam: Camera3D = null
var _cam_refresh_accum: float = 0.0

# Комбо сабли (наземное)
var _current_combo_index: int = 0
var _last_saber_attack_time: float = -1.0


# --------------------------------------------------------------
func _ready() -> void:
	if not pivot:
		push_error("Saber: Pivot not found. Assign pivot_path in Inspector.")
		return
	if not hitbox:
		push_error("Saber: Hitbox not found. Assign hitbox_path in Inspector.")
		return

	# Стартовые значения позы/базиса
	hitbox.monitoring = false
	_target_basis = global_transform.basis.orthonormalized()
	_target_pos = global_transform.origin
	_pivot_rest_pos = pivot.position

	# Подключаемся ОДИН раз
	if not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	if not hitbox.area_entered.is_connected(_on_hitbox_area_entered):
		hitbox.area_entered.connect(_on_hitbox_area_entered)
	if anim and not anim.animation_finished.is_connected(_on_anim_finished):
		anim.animation_finished.connect(_on_anim_finished)


# ====================== ПУБЛИЧНЫЙ API ======================

func is_attacking() -> bool:
	return _is_attacking_clip_playing()

func queue_next_if_within(sec: float = 0.3) -> void:
	if not _is_attacking_clip_playing():
		return
	var cur: StringName = StringName(anim.current_animation)
	var a: Animation = anim.get_animation(cur)
	if a == null:
		return
	var length: float = a.length / max(0.001, attack_clip_speed)
	var pos: float = anim.current_animation_position / max(0.001, attack_clip_speed)
	var remaining: float = max(0.0, length - pos)
	if remaining <= sec:
		_queued_next = true

func attach_to(player: Node3D) -> void:
	_owner_player = player

func set_facing(dir: int) -> void:
	var d: int = -1 if dir < 0 else 1
	if invert_facing:
		d = -d
	_facing = d

func set_collider_profile(profile_name: StringName) -> void:
	_stance = STANCE_CROUCH if String(profile_name) == "crouch" else STANCE_STAND

func set_move_mode(mode: StringName) -> void:
	match String(mode):
		"idle":     _move = MODE_IDLE
		"run":      _move = MODE_RUN
		"sprint":   _move = MODE_SPRINT
		"air_up":   _move = MODE_AIR_UP
		"air_down": _move = MODE_AIR_DN

# === Канальные атаки с фоллбэком на Attack1 ===
func start_attack_for(channel: StringName) -> void:
	if not anim:
		return
	_queued_exact_clip = &""
	_queued_next = false
	var clip: StringName = _pick_clip_for_channel(channel)
	anim.play(clip, 0.0, attack_clip_speed, false)
	var a: Animation = anim.get_animation(clip)
	var length: float = (a.length if a else 0.0) / max(0.001, attack_clip_speed)
	attack_started.emit(clip, length)
	_last_saber_attack_time = float(Time.get_ticks_msec()) * 0.001

func queue_attack_for_if_within(channel: StringName, sec: float) -> void:
	if not is_attacking():
		start_attack_for(channel)
		return
	var cur: StringName = StringName(anim.current_animation)
	var a: Animation = anim.get_animation(cur)
	if a == null:
		return
	var length: float = a.length / max(0.001, attack_clip_speed)
	var pos: float = anim.current_animation_position / max(0.001, attack_clip_speed)
	var remaining: float = max(0.0, length - pos)
	if remaining <= sec:
		_queued_exact_clip = _pick_clip_for_channel(channel)
		_queued_next = true

# === Наземное комбо ===
func try_attack_next_in_cycle() -> bool:
	if not anim:
		return false
	if _is_attacking_clip_playing():
		return false

	var now: float = float(Time.get_ticks_msec()) * 0.001
	if _last_saber_attack_time < 0.0 or (now - _last_saber_attack_time) >= saber_reset_sec:
		_current_combo_index = 0

	_current_combo_index = (_current_combo_index % max_combo_steps) + 1
	var clip: StringName = _clip_for_step(_current_combo_index)

	_last_saber_attack_time = now
	_queued_next = false
	_queued_exact_clip = &""

	anim.play(clip, 0.0, attack_clip_speed, false)

	var a: Animation = anim.get_animation(clip)
	var length: float = (a.length if a else 0.0) / max(0.001, attack_clip_speed)
	attack_started.emit(clip, length)
	return true

func get_last_attack_clip_length() -> float:
	if not anim:
		return 0.0
	var cur: StringName = StringName(anim.current_animation)
	var a: Animation = anim.get_animation(cur)
	if a:
		return a.length / max(0.001, attack_clip_speed)
	return 0.0

# ====================== ВНУТРЕННЕЕ ======================

# ★ helper: клип из каналов crouch/jump?
func _is_channel_clip(clip: StringName) -> bool:
	for c in CROUCH_PREF:
		if clip == c:
			return true
	for j in JUMP_PREF:
		if clip == j:
			return true
	return false

func _on_anim_finished(anim_name: StringName) -> void:
	if not _is_clip_attack(anim_name):
		return

	if _queued_next:
		# ★ не продолжаем наземное комбо после спец-клипа,
		# если явно не поставлен точный следующий клип
		if _queued_exact_clip == &"" and _is_channel_clip(anim_name):
			_queued_next = false
			attack_finished.emit(anim_name)
			return

		_queued_next = false
		if _queued_exact_clip != &"":
			var next_clip: StringName = _queued_exact_clip
			_queued_exact_clip = &""

			anim.play(next_clip, 0.0, attack_clip_speed, false)
			var a: Animation = anim.get_animation(next_clip)
			var length: float = (a.length if a else 0.0) / max(0.001, attack_clip_speed)
			attack_started.emit(next_clip, length)
			_last_saber_attack_time = float(Time.get_ticks_msec()) * 0.001
			return

		_current_combo_index = (_current_combo_index % max_combo_steps) + 1
		var next_combo_clip: StringName = _clip_for_step(_current_combo_index)

		anim.play(next_combo_clip, 0.0, attack_clip_speed, false)
		var a2: Animation = anim.get_animation(next_combo_clip)
		var length2: float = (a2.length if a2 else 0.0) / max(0.001, attack_clip_speed)
		attack_started.emit(next_combo_clip, length2)
		_last_saber_attack_time = float(Time.get_ticks_msec()) * 0.001
		return

	attack_finished.emit(anim_name)

func _clip_for_step(step: int) -> StringName:
	var s: int = clamp(step, 1, max_combo_steps)
	if s == 1:
		return CLIP_ATTACK1
	elif s == 2:
		return CLIP_ATTACK2
	else:
		return CLIP_ATTACK3

func _is_attacking_clip_playing() -> bool:
	if not anim or not anim.is_playing():
		return false
	var cur: StringName = StringName(anim.current_animation)
	return _is_clip_attack(cur)

func _is_clip_attack(clip: StringName) -> bool:
	if clip == CLIP_ATTACK1 or clip == CLIP_ATTACK2 or clip == CLIP_ATTACK3:
		return true
	for c in CROUCH_PREF:
		if clip == c:
			return true
	for j in JUMP_PREF:
		if clip == j:
			return true
	return false

func _pick_clip_for_channel(channel: StringName) -> StringName:
	var list: Array = []
	if channel == &"crouch":
		list = CROUCH_PREF
	elif channel == &"jump":
		list = JUMP_PREF
	else:
		return CLIP_ATTACK1
	for c in list:
		if anim and anim.has_animation(c):
			return c
	return CLIP_ATTACK1

# ----- ОКНО УРОНА / ХИТБОКС -----
func command_attack_window(from_s: float, to_s: float, _facing_dir_unused: int = 0) -> void:

	_window_token += 1
	var my: int = _window_token
	_hit_ids = PackedInt64Array()

	if hitbox == null:
		return

	# Закрыть предыдущее окно
	hitbox.monitoring = false
	_attack_window_task = null

	# Тайминги с фолбэком
	var open_from: float = max(0.0, (from_s if from_s > 0.0 else default_hit_from))
	var open_to: float   = (to_s   if to_s   > 0.0 else default_hit_to)
	if open_to <= open_from:
		open_to = open_from + 0.02  # >= 20 мс
	var window: float = open_to - open_from

	# Ждём до начала окна (по physics кадрам)
	if open_from > 0.0:
		var step_wait: float = 1.0 / float(Engine.get_physics_ticks_per_second())
		var acc: float = 0.0
		while acc + 0.0001 < open_from:
			await get_tree().physics_frame
			if my != _window_token:
				return
			acc += step_wait

	# --- ОТКРЫВАЕМ ОКНО ---
	# Через deferred — чтобы точно применилось к следующему physics шагу
	hitbox.set_deferred("monitoring", true)

	# ДАДИМ ДВА PHYSICS-ТИКА на прогрев broadphase, прежде чем «промывать»
	await get_tree().physics_frame
	if my != _window_token:
		hitbox.monitoring = false
		return
	await get_tree().physics_frame
	if my != _window_token:
		hitbox.monitoring = false
		return

	# Гарантируем минимум 3 physics-тиков окна, даже если оно меньше
	var step: float = 1.0 / float(Engine.get_physics_ticks_per_second())
	var target_time: float = max(window, step * 3.0)

	var elapsed: float = 0.0
	var _hits_seen_bodies: int = 0
	var _hits_seen_areas: int = 0

	while elapsed + 0.0001 < target_time:
		# Активная промывка пересечений
		var bodies: Array[Node3D] = hitbox.get_overlapping_bodies()
		for b in bodies:
			if b != null:
				_on_hitbox_body_entered(b)
				_hits_seen_bodies += 1

		var areas: Array[Area3D] = hitbox.get_overlapping_areas()
		for a in areas:
			if a != null:
				_on_hitbox_area_entered(a)
				_hits_seen_areas += 1

		await get_tree().physics_frame
		if my != _window_token:
			hitbox.monitoring = false
			return
		elapsed += step

	# Закрываем окно
	hitbox.monitoring = false
	_attack_window_task = null


# Универсальное применение урона (через Health/HpBase) + лог
func _apply_damage_debug(sink: Node, instigator: Node, origin: Vector3, dir: Vector3, amount: int, hit_id: int) -> void:
	var dmg := DamageEvent.new()
	dmg.amount = amount
	dmg.type = &"slash"
	dmg.tags = [&"saber"]
	dmg.source = self
	dmg.instigator = instigator
	dmg.origin = origin
	dmg.direction = dir.normalized()
	dmg.impulse = 7.0
	dmg.hit_id = hit_id

	# если по какой-то причине сюда всё равно пришёл HpBase — поднимем его до Health
	if sink != null and String(sink.name) == "HpBase":
		var p := sink.get_parent()
		if p != null and (String(p.name) == "Health" or p.has_method("apply_damage")):
			sink = p

	if sink != null and sink.has_method("apply_damage"):
		sink.apply_damage(dmg)
	elif sink != null and sink.has_method("damage"):
		sink.damage(dmg.amount, dmg.origin)
	elif sink != null and sink.has_method("take_damage"):
		sink.take_damage(dmg.amount, dmg.origin)

# Найти реального приёмника урона (предпочтительно Health у цели)
func _resolve_health_receiver(target: Node) -> Node:
	if target == null:
		return null
	var cur := target
	var depth := 0
	while cur != null and depth < 6:
		if cur.has_node("Health"):
			return cur.get_node("Health")
		if String(cur.name) == "HpBase":
			var p := cur.get_parent()
			if p != null and (String(p.name) == "Health" or p.has_method("apply_damage")):
				return p
		cur = cur.get_parent()
		depth += 1
	return target

# === Обработчики хитбокса ===
func _on_hitbox_body_entered(body: Node) -> void:
	if not hitbox or not hitbox.monitoring or body == null:
		return

	var sink := _resolve_health_receiver(body)
	var dedup_node := sink if sink != null else body
	var iid := dedup_node.get_instance_id()
	if _hit_ids.has(iid):
		return
	_hit_ids.append(iid)

	var instigator := _resolve_instigator()
	var body_pos := (body as Node3D).global_transform.origin if body is Node3D else global_transform.origin
	var dir: Vector3 = body_pos - global_transform.origin

	print("[SABER] HIT body=", body, " sink(Health)=", sink, " base_damage=", base_damage)
	_apply_damage_debug(sink if sink != null else body, instigator, global_transform.origin, dir, base_damage, _window_token)

func _on_hitbox_area_entered(area: Area3D) -> void:
	if area == null or not hitbox or not hitbox.monitoring:
		return
	var likely_host: Node = area.get_parent()
	_on_hitbox_body_entered(likely_host if likely_host != null else area)

# Кто считается инициатором удара
func _resolve_instigator() -> Node:
	var p: Node = self
	var step := 0
	while p != null and step < 6:
		if p.has_node("Health"):
			return p
		p = p.get_parent()
		step += 1
	# фолбэк — родитель сабли (обычно Player)
	return get_parent()

# ====================== SWING (процедурно) ======================
func play_swing(kind: StringName) -> void:
	var SWINGS := {
		"stand_1": { "start": Vector3(0.0, -0.6,  0.35), "end": Vector3(0.0, 0.35, -0.25), "dur": 0.24, "win": Vector2(0.05, 0.22) },
		"stand_2": { "start": Vector3(0.0,  0.7, -0.30), "end": Vector3(0.0,-0.30, 0.20), "dur": 0.26, "win": Vector2(0.06, 0.24) },
		"stand_3": { "start": Vector3(0.0, -0.8,  0.00), "end": Vector3(0.0, 0.80,  0.00), "dur": 0.30, "win": Vector2(0.08, 0.30) },
		"crouch":  { "start": Vector3(0.2, -0.5,  0.15), "end": Vector3(0.2, 0.30, -0.10), "dur": 0.22, "win": Vector2(0.05, 0.20) },
		"air":     { "start": Vector3(-0.2,-0.6, -0.10), "end": Vector3(-0.2,0.45,  0.10), "dur": 0.24, "win": Vector2(0.05, 0.22) }
	}
	if not SWINGS.has(String(kind)):
		return
	if _swing_active and not allow_interrupt_swing:
		return

	var def: Dictionary = SWINGS[String(kind)]
	_swing_start_basis = Basis.from_euler(def["start"]).orthonormalized()
	_swing_end_basis   = Basis.from_euler(def["end"]).orthonormalized()
	_swing_dur   = float(def["dur"])
	_swing_time  = 0.0
	_swing_active = true

	var s_scale: Vector3 = pivot.basis.get_scale()
	pivot.basis = _swing_start_basis.scaled(s_scale)

	if auto_open_window_on_swing:
		var win: Vector2 = def["win"]
		command_attack_window(win.x, win.y, _facing)

func _update_swing(delta: float) -> void:
	_swing_time = min(_swing_dur, _swing_time + delta)
	var a: float = _swing_time / _swing_dur
	var eased: float = a * a * (3.0 - 2.0 * a)

	var cur_scale: Vector3 = pivot.basis.get_scale()
	var cur_basis: Basis = _swing_start_basis.slerp(_swing_end_basis, eased).orthonormalized()
	pivot.basis = cur_basis.scaled(cur_scale)

	if _swing_time >= _swing_dur:
		_swing_active = false

# ====================== ФИЗИКА / ПОЗА ======================
func _physics_process(delta: float) -> void:
	if not pivot:
		return

	if use_camera_depth:
		_cam_refresh_accum += delta
		if _cam_refresh_accum >= cam_refresh_interval:
			_cam = get_viewport().get_camera_3d()
			_cam_refresh_accum = 0.0

	var idle_amp_cur: float = 1.0

	if _owner_player:
		var face: int = _facing
		var base_offset: Vector3 = hold_offset_right if face >= 0 else hold_offset_left

		var stance_offset: Vector3 = base_offset
		var grip_deg: Vector3 = grip_rot_deg
		var idle_amp_mul: float = idle_amp_mul_stand
		var pos_mul: float = 1.0
		var rot_mul: float = 1.0

		if _stance == STANCE_CROUCH:
			stance_offset += crouch_offset_delta
			grip_deg += crouch_grip_add_deg
			idle_amp_mul = idle_amp_mul_crouch
			pos_mul *= crouch_pos_time_mul
			rot_mul *= crouch_rot_time_mul

		match _move:
			MODE_RUN:
				pos_mul *= run_pos_time_mul;    rot_mul *= run_rot_time_mul
			MODE_SPRINT:
				pos_mul *= sprint_pos_time_mul; rot_mul *= sprint_rot_time_mul
			MODE_AIR_UP:
				pos_mul *= air_up_pos_time_mul; rot_mul *= air_up_rot_time_mul
				grip_deg.x += air_pitch_up_deg
			MODE_AIR_DN:
				pos_mul *= air_down_pos_time_mul; rot_mul *= air_down_rot_time_mul
				grip_deg.x += air_pitch_down_deg

		var cb: CharacterBody3D = _owner_player as CharacterBody3D
		if cb:
			var v: Vector3 = cb.velocity
			var vx: float = v.x
			var vy: float = v.y
			if abs(vx) < vel_deadzone_x: vx = 0.0
			if abs(vy) < vel_deadzone_y: vy = 0.0

			var lag_x: float = clamp(abs(vx) * vel_lag_x_per_speed, 0.0, max_vel_lag_x)
			if lag_x > 0.0:
				stance_offset.x += -sign(vx) * lag_x

			var lag_y: float = clamp(vy * vel_lag_y_per_speed, -max_vel_lag_y, max_vel_lag_y)
			stance_offset.y += -lag_y

		var player_xform: Transform3D = _owner_player.global_transform
		_target_pos = player_xform.origin + stance_offset

		var y_rot: float = 0.0 if face >= 0 else rotate_y_when_left
		var grip_rad: Vector3 = _deg2rad3(grip_deg)
		var target_basis: Basis = (Basis(Vector3.UP, y_rot) * Basis.from_euler(grip_rad)).orthonormalized()
		_target_basis = target_basis

		var alpha_pos: float = _tc_alpha(follow_pos_time * pos_mul, delta)
		var alpha_rot: float = _tc_alpha(follow_rot_time * rot_mul, delta)

		var t: Transform3D = global_transform
		var cur_scale: Vector3 = t.basis.get_scale()
		var cur_rot: Basis = t.basis.orthonormalized()
		var new_rot: Basis = cur_rot.slerp(_target_basis, alpha_rot)
		t.basis = new_rot.scaled(cur_scale)
		t.origin = t.origin.lerp(_target_pos, alpha_pos)
		global_transform = t

		idle_amp_cur = idle_amp_mul

	if _swing_active and _swing_dur > 0.0:
		_update_swing(delta)
	else:
		_update_idle_with_mul(delta, idle_amp_cur)

# ----- IDLE (локальный Basis) -----
func _update_idle_with_mul(delta: float, amp_mul: float) -> void:
	_idle_phase += idle_sway_speed * delta

	var euler: Vector3 = Vector3(
		sin(_idle_phase) * idle_sway_amp_rot.x * amp_mul,
		sin(_idle_phase * 0.8) * idle_sway_amp_rot.y * amp_mul,
		cos(_idle_phase * 1.3) * idle_sway_amp_rot.z * amp_mul
	)
	var target_basis: Basis = Basis.from_euler(euler).orthonormalized()

	var blend: float = clamp(idle_blend_speed * delta, 0.0, 1.0)
	var cur_basis: Basis = pivot.basis.orthonormalized()
	var cur_scale: Vector3 = pivot.basis.get_scale()
	var new_basis: Basis = cur_basis.slerp(target_basis, blend)
	pivot.basis = new_basis.scaled(cur_scale)

	var bob_y: float = sin(_idle_phase * 1.2) * idle_sway_amp_pos.y * amp_mul
	var target_pos: Vector3 = _pivot_rest_pos + Vector3(0.0, bob_y, 0.0)
	pivot.position = pivot.position.lerp(target_pos, blend)

# ----- Helpers -----
static func _deg2rad3(v: Vector3) -> Vector3:
	return Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))

static func _tc_alpha(time_const: float, delta: float) -> float:
	if time_const <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / time_const)
