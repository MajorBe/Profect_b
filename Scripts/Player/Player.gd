extends CharacterBody3D
class_name Player

# =============================== ПАРАМЕТРЫ / ЭКСПОРТЫ ===============================
@export var speed: float = 2.2
@export var jump_velocity: float = 2.5
@export var gravity: float = 9.0
@export var max_jump_hold_time: float = 0.2
@export var max_jumps: int = 2
@export var jump_buffer_time: float = 0.12   # окно буфера, сек
@export var max_air_jumps: int = 1              # сколько раз можно прыгнуть в воздухе
@export var air_jump_velocity: float = 0.0      # 0.0 → использовать jump_velocity
@export var coyote_like_time: float = 0.10      # окно, в котором прыжок считается "земляным" (для ресета air_jumps)

@export var sprint_speed_multiplier: float = 1.7  # во сколько раз быстрее бега
@export var slide_min_speed: float = 8.0        # минимум горизонтальной скорости для старта слайда

@export var air_attack_gravity_scale: float = 0.15  # во сколько раз слабее гравитация
@export var air_attack_fall_cap: float = 1.0        # максимум падения вниз (м/с) во время атаки

@export var attack_move_speed: float = 0.12

@export var slide_speed_multiplier: float = 1.5
@export var slide_duration: float = 0.35
@export var slide_invuln_time: float = 0.25
@export var slide_cooldown: float = 0.5

@export var min_fall_time_for_roll: float = 1.2
@export var roll_duration: float = 0.45

@export var heal_amount: int = 30
@export var heal_duration: float = 1.0
@export var max_heals: int = 3

@export var knockback_strength: float = 1.0
@export var hit_stun_duration: float = 0.2
@export var hurt_invuln_time: float = 0.25  # i-frames после получения урона

@export var coyote_time: float = 0.12

# One-way платформы
@export var platform_layer_mask: int = 1 << 3 

@export var max_fall_speed: float = 20.0

# Сабля с клипами (наш основной путь)
@export_node_path("Node3D") var saber_path: NodePath
@onready var saber: Saber = get_node_or_null(saber_path) as Saber

@export var max_floor_angle_deg: float = 46.0

@export var enemy_body_layer_bit: int = 3

# =============================== НОДЫ ===============================
@onready var input_node: PlayerInput = $Input
@onready var dropper: DropThrough = $DropThrough
@onready var health: PlayerHealth = $Health as PlayerHealth
@onready var stand_shape: CollisionShape3D = $StandShape
@onready var crouch_shape: CollisionShape3D = $CrouchShape
@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D
# =============================== FSM ===============================
var current_state: State = null

# =============================== СОСТОЯНИЕ / ТАЙМЕРЫ / ФЛАГИ ===============================
var facing_dir: int = 1
var lock_facing: bool = false
var is_sprinting: bool = false

# Прыжок
var jump_count: int = 0
var jump_time: float = 0.0
var jump_held_active: bool = false
var coyote_counter: float = 0.0
var jump_buffer: float = 0.0                 # сколько осталось буфера
var was_on_floor_prev: bool = false          # состояние пола на прошлый кадр
var air_jumps_left: int = 0                     # оставшиеся воздушные прыжки
var time_since_on_floor: float = 0.0            # сколько мы в воздухе с момента последнего касания пола

# Атаки / лечение
var is_attacking: bool = false

var is_healing: bool = false
var heal_timer: float = 0.0
var heals_left: int = 3

# Слайд / ролл
var slide_timer: float = 0.0
var slide_invuln_timer: float = 0.0
var slide_cooldown_timer: float = 0.05

var roll_timer: float = 0.0
var fall_time: float = 0.0

# i-frames флаги для PlayerHealth
var _slide_active: bool = false
var _roll_active: bool = false

# Присед
var is_crouching: bool = false

# Урон / хитстан / нокбэк / i-frames
var is_damaged: bool = false
var hit_stun_timer: float = 0.0
var knockback_dir: Vector3 = Vector3.ZERO
var hurt_invuln_timer: float = 0.0

# Прочее
var _z_lock: float = 0.0
var input: Dictionary = {}


# ---------- READY ----------
func _ready() -> void:
	apply_flip()
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(max_floor_angle_deg)

	if saber:
		saber.attach_to(self)
		saber.set_facing(facing_dir)          # стартовое направление
		saber.set_collider_profile(&"stand")  # стойка по умолчанию
		saber.set_move_mode(&"idle")          # режим по умолчанию

	# сигналы здоровья
	health.connect("died", Callable(self, "_on_player_died"))
	health.connect("damaged", Callable(self, "_on_health_damaged_signal"))
	health.connect("health_changed", Callable(self, "_on_health_changed"))
	HUD.set_health(health.current_health, health.max_health)

	heals_left = max_heals
	change_state(IdleState.new(self))
	_z_lock = global_transform.origin.z

	if health:
		_on_health_changed(health.current_health, health.max_health)

# ---------- FSM CORE ----------
func change_state(new_state: State) -> void:
	# защита от "залипания" падения при входе в наземные состояния
	if new_state.is_ground_state() and velocity.y > 0.0:
		velocity.y = 0.0

	if current_state:
		current_state.exit()

	# по умолчанию снимаем блок разворота в «спокойных» стейтах
	if (new_state is IdleState) or (new_state is RunState) or (new_state is FallState):
		lock_facing = false

	current_state = new_state
	current_state.enter()

func _physics_process(delta: float) -> void:
	_enforce_2d_plane()

	# 1) input — один раз за кадр через компонент
	input_node.update()
	input = input_node.snapshot
	update_jump_buffer(delta)

	# 2) обновляем состояние
	if current_state:
		current_state.update(delta)


	# 3) таймеры — ОДИН раз
	hurt_invuln_timer     = max(hurt_invuln_timer - delta, 0.0)
	slide_invuln_timer    = max(slide_invuln_timer - delta, 0.0)  
	slide_cooldown_timer  = max(slide_cooldown_timer - delta, 0.0)

	# 4) окно drop-through
	dropper.update(delta)

	velocity.z = 0.0
	global_transform.origin.z = 0.0

	# 5) койот-тайм
	if is_on_floor():
		coyote_counter = coyote_time
	else:
		coyote_counter = max(coyote_counter - delta, 0.0)


	# 6) движение
	move_and_slide()

	was_on_floor_prev = is_on_floor()

	if is_on_floor():
		time_since_on_floor = 0.0
	else:
		time_since_on_floor += delta

	_update_saber_move_mode()
	_enforce_2d_plane()

# ---------- АТАКИ: ПУБЛИЧНЫЕ МЕТОДЫ ДЛЯ СТЕЙТОВ ----------
# Зови эти методы из своих стейтов (enter):
#   GroundAttackState → do_ground_attack_start()
#   CrouchAttackState → do_crouch_attack_start()
#   JumpAttackState   → do_air_attack_start()

# Универсальный алиас: некоторые хиты вызывают именно take_damage у Player
func take_damage(amount: int, from: Vector3) -> void:
	_on_player_damaged(amount, from)

# ---------- ХЕЛПЕРЫ ----------
func apply_flip() -> void:
	if sprite:
		sprite.flip_h = facing_dir < 0
	if saber:
		saber.set_facing(facing_dir)

func update_facing(input_dir: float, force: bool = false) -> void:
	if input_dir == 0.0:
		return
	if lock_facing and not force:
		return
	facing_dir = -1 if input_dir < 0.0 else 1
	apply_flip()

func _enforce_2d_plane() -> void:
	# скорость строго в X/Y
	velocity.z = 0.0
	# позиция жёстко на зафиксированном Z
	var t := global_transform
	if absf(t.origin.z - _z_lock) > 0.00001:
		t.origin.z = _z_lock
		global_transform = t

func _update_saber_move_mode() -> void:
	if not saber:
		return
	if not is_on_floor():
		var m := "air_up" if velocity.y > 0.0 else "air_down"
		saber.set_move_mode(StringName(m))
	else:
		if abs(velocity.x) < 0.1:    
			saber.set_move_mode(&"idle")
		elif is_sprinting:           
			saber.set_move_mode(&"sprint")
		else:                        
			saber.set_move_mode(&"run")

# Универсально «уроняем» таймер к нулю. 
func cd(t: float, delta: float) -> float:
	return (t - delta) if t > delta else 0.0


func apply_gravity(delta: float, gravity_scale: float = 1.0) -> void:
	velocity.y -= gravity * gravity_scale * delta
	if velocity.y < -max_fall_speed:
		velocity.y = -max_fall_speed

func get_takeoff_speed(is_air_jump: bool) -> float:
	if is_air_jump and air_jump_velocity > 0.0:
		return air_jump_velocity
	return jump_velocity

func refresh_air_jumps_on_ground_like() -> void:
	air_jumps_left = max_air_jumps

func consume_air_jump() -> bool:
	if air_jumps_left > 0:
		air_jumps_left -= 1
		return true
	return false

func update_jump_buffer(delta: float) -> void:
	if bool(input.get("jump_pressed", false)):
		jump_buffer = jump_buffer_time
	else:
		jump_buffer = max(jump_buffer - delta, 0.0)

func consume_jump_buffer_on_ground() -> bool:
	if is_on_floor() and jump_buffer > 0.0:
		jump_buffer = 0.0
		return true
	return false

func _switch_to_crouch() -> void:
	stand_shape.disabled = true
	crouch_shape.disabled = false
	is_crouching = true

func _switch_to_stand() -> void:
	crouch_shape.disabled = true
	stand_shape.disabled = false
	is_crouching = false

func face(dir: int) -> void:
	if lock_facing:
		return
	facing_dir = (1 if dir >= 0 else -1)
	apply_flip()

func emit_saber_window(from_s: float, to_s: float) -> void:
	if saber:
		saber.command_attack_window(from_s, to_s, facing_dir)


# ---------- DAMAGE / HEALTH ----------

func _on_health_changed(current: int, maxv: int) -> void:
	# доступ к автолоаду HUD (оба варианта рабочие, выбери один)
	if typeof(HUD) != TYPE_NIL and HUD.has_method("set_health"):
		HUD.set_health(current, maxv)
		return
	var hud := get_tree().root.get_node_or_null("HUD")
	if hud and hud.has_method("set_health"):
		hud.call("set_health", current, maxv)


func _on_player_died() -> void:
	if typeof(HUD) != TYPE_NIL and HUD.has_method("show_death"):
		HUD.show_death()
	# Минимально: отключить управление и показать респаун/рестарт
	set_process(false)
	set_physics_process(false)
	# TODO: твоя логика респауна/рестарта сцены

func is_sliding() -> bool:
	return _slide_active

func is_rolling() -> bool:
	return _roll_active

func set_slide_active(v: bool) -> void:
	_slide_active = v

func set_roll_active(v: bool) -> void:
	_roll_active = v

func set_collide_with_enemies(enabled: bool) -> void:
	# Включаем/выключаем столкновения ИГРОКА с телами врагов
	set_collision_mask_value(enemy_body_layer_bit, enabled)

# Прямой вход от Area/ловушек/врагов
func _on_player_damaged(amount: int, source_pos: Vector3) -> void:
	if slide_invuln_timer > 0.0 or hurt_invuln_timer > 0.0:
		return
	if health and health.has_method("take_damage"):
		health.take_damage(amount, source_pos)

# сигнал из Health.gd
func _on_health_damaged_signal(_amount: int, source_pos: Vector3) -> void:
	var dx: float = global_transform.origin.x - source_pos.x

	var sign_x: int
	if dx > 0.001:
		sign_x = 1            # источник слева -> отбрасываем вправо
	elif dx < -0.001:
		sign_x = -1           # источник справа -> отбрасываем влево
	else:
		sign_x = -facing_dir  # почти по X — толкаем "назад" относительно взгляда

	knockback_dir = Vector3(sign_x, 0.0, 0.0)

	is_damaged = true
	hurt_invuln_timer = hurt_invuln_time

	lock_facing = true
	facing_dir = 1 if sign_x >= 0 else -1
	apply_flip()


func _respawn() -> void:
	health.reset_health()
	global_transform.origin = Vector3(0, 0, 0)
	velocity = Vector3.ZERO
	heals_left = max_heals
	is_damaged = false
	jump_count = 0
	fall_time = 0.0
	lock_facing = false
	change_state(IdleState.new(self))

# =============================== ТРИГГЕРЫ / ВЗАИМОДЕЙСТВИЯ ===============================
# (оставь как в твоей версии — тут твоё взаимодействие/подбор и т.п.)

# =============================== DEBUG STUB ===============================
