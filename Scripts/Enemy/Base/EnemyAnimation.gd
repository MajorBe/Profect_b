# Scripts/Scripts/Enemy/EnemyAnimation.gd
extends Node
class_name EnemyAnimation

# --- Refs / State ------------------------------------------------------------
var actor: Node3D
var sprite: AnimatedSprite3D

var current: StringName = &""
var _flip_locked: bool = false

# Флаг «идёт командный клип» (evade/attack/hurt/jump и т.п.)
var _command_active: bool = false
var _current_cmd: StringName = &""

# Кэш резолва для командных клипов
var _evade_resolved: StringName = &""

# --- Anim map ----------------------------------------------------------------
@export var anim_map: Dictionary = {
	"idle":   "Idle",
	"walk":   "Walk",
	"attack1":"Attack1",
	"attack2":"Attack2",
	"hurt":   "Hurt",
	"evade":  "Evade",
	"death":  "Death",
	"jump":   "Jump",
	"fall":   "Fall",
}

# Резолвнутые ключи клипов
var A_IDLE     : StringName
var A_WALK     : StringName
var A_ATTACK_1 : StringName
var A_ATTACK_2 : StringName
var A_HURT     : StringName
var A_EVADE    : StringName
var A_DEATH    : StringName
var A_JUMP     : StringName
var A_FALL     : StringName

func _apply_anim_map() -> void:
	A_IDLE      = StringName(str(anim_map.get("idle",   "Idle")))
	A_WALK      = StringName(str(anim_map.get("walk",   "Walk")))
	A_ATTACK_1  = StringName(str(anim_map.get("attack1","Attack1")))
	A_ATTACK_2  = StringName(str(anim_map.get("attack2","Attack2")))
	A_HURT      = StringName(str(anim_map.get("hurt",   "Hurt")))
	A_EVADE     = StringName(str(anim_map.get("evade",  "Evade")))
	A_DEATH     = StringName(str(anim_map.get("death",  "Death")))
	A_JUMP      = StringName(str(anim_map.get("jump",   "Jump")))
	A_FALL      = StringName(str(anim_map.get("fall",   "Fall")))

# --- Ready -------------------------------------------------------------------
func _ready() -> void:
	actor = get_parent() as Node3D
	if actor == null:
		push_warning("EnemyAnimation: parent is not Node3D")
		return

	# Мерж карты клипов владельца (строго типизировано)
	if actor.has_method("get_anim_map"):
		var ext: Dictionary = actor.call("get_anim_map") as Dictionary
		if ext and not ext.is_empty():
			for k in ext.keys():
				anim_map[k] = ext[k]

	_apply_anim_map()

	# Поиск AnimatedSprite3D на известных путях
	sprite = actor.get_node_or_null(NodePath("AnimatedSprite3D")) as AnimatedSprite3D
	if sprite == null:
		var cand: Array[NodePath] = [
			NodePath("Body/AnimatedSprite3D"),
			NodePath("Body/Sprite"),
			NodePath("Sprite"),
		]
		for p in cand:
			var s: Node = actor.get_node_or_null(p)
			if s is AnimatedSprite3D:
				sprite = s as AnimatedSprite3D
				break
	if sprite == null:
		push_warning("EnemyAnimation: AnimatedSprite3D not found on actor")
		return

	# Базовая инициализация
	if sprite.is_playing():
		sprite.stop()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(String(A_IDLE)):
		sprite.animation = String(A_IDLE)
		sprite.sprite_frames.set_animation_loop(String(A_IDLE), true)

	# Сигнал окончания клипа (AnimatedSprite3D — без аргументов)
	if not sprite.animation_finished.is_connected(_on_anim_finished):
		sprite.animation_finished.connect(_on_anim_finished)

	# Сервисные флаги
	_command_active = false
	_current_cmd = &""
	_flip_locked = false

# Сбрасываем «командный» статус только когда закончился именно активный командный клип
func _on_anim_finished() -> void:
	if sprite == null:
		return

	# Имя только что завершившегося клипа
	var finished_name: StringName = StringName(sprite.animation)

	# Если завершился активный КОМАНДНЫЙ клип — разблокируем и уходим в idle
	if _command_active and finished_name == _current_cmd:
		_command_active = false
		_current_cmd = &""
		_flip_locked = false

		# Авто-фоллбэк: сразу включаем idle (чтобы не зависать на последнем кадре)
		# Если внешний код захочет другой клип — он его перезапустит в тот же/следующий кадр.
		_play(A_IDLE, true, 1.0)
		current = A_IDLE
		
# --- Facing / mirroring ------------------------------------------------------
func is_flip_locked() -> bool:
	return _flip_locked

func set_facing(dir: int) -> void:
	# dir: -1 (влево), +1 (вправо). Базовый спрайт смотрит влево — flip_h для вправо.
	if _flip_locked:
		return
	if sprite != null:
		sprite.flip_h = (dir > 0)

	# Зеркалим связанные узлы без накопления
	var dir_sign: float = (1.0 if dir > 0 else -1.0)
	if actor != null:
		var hb: Node = actor.get_node_or_null("Hitbox")
		if hb is Node3D:
			var hb3: Node3D = hb as Node3D
			var p: Vector3 = hb3.position
			p.x = abs(p.x) * dir_sign
			hb3.position = p
		var pivot: Node = actor.get_node_or_null("WeaponPivot")
		if pivot is Node3D:
			var pv: Node3D = pivot as Node3D
			var sc: Vector3 = pv.scale
			sc.x = abs(sc.x) * dir_sign
			pv.scale = sc

# --- Low-level play ----------------------------------------------------------
func _has(anim: StringName) -> bool:
	if sprite == null or sprite.sprite_frames == null:
		return false
	return sprite.sprite_frames.has_animation(String(anim))

func _set_loop(anim: StringName, on: bool) -> void:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames != null and frames.has_animation(String(anim)):
		frames.set_animation_loop(String(anim), on)

func _play(anim: StringName, loop_default: bool, speed: float = 1.0) -> void:
	if sprite == null or sprite.sprite_frames == null:
		current = anim
		return

	var anim_key: String = String(anim)
	if not sprite.sprite_frames.has_animation(anim_key):
		push_warning("EnemyAnimation: missing AnimatedSprite3D animation '%s'" % anim_key)
		return

	_set_loop(anim, loop_default)

	# Если уже выбран тот же клип
	if sprite.animation == anim_key:
		if not is_equal_approx(sprite.speed_scale, speed):
			sprite.speed_scale = speed
		if sprite.is_playing():
			current = anim
			return
		sprite.play()
		current = anim
		return

	# Переключение на новый клип
	sprite.animation = anim_key
	sprite.speed_scale = speed
	sprite.play()
	current = anim

# --- Resolvers ---------------------------------------------------------------
func _resolve_evade_id() -> StringName:
	# 1) Пробуем строго по карте
	if _has(A_EVADE):
		return A_EVADE

	# 2) Универсальные кандидаты без привязки к конкретному врагу
	var candidates: Array[StringName] = [
		StringName("Evasion"),
		StringName("Evade"),
		StringName("EvadeShort"),
		StringName("Dodge"),
		StringName("Roll")
	]
	for c in candidates:
		if _has(c):
			return c

	# 3) Мягкий поиск по всем клипам AnimatedSprite3D
	if sprite != null and sprite.sprite_frames != null:
		var names: Array = sprite.sprite_frames.get_animation_names()
		for n in names:
			var lower := String(n).to_lower()
			if lower.findn("evad") != -1 or lower.findn("evas") != -1 or lower.findn("dodge") != -1 or lower.findn("roll") != -1:
				return StringName(n)

	# 4) Фоллбэк — как и в текущей логике проекта: хотя бы Idle
	return A_IDLE

# --- Public API --------------------------------------------------------------
# Любой внешний play трактуем как «фон»: idle/walk и т.п.
# Пока идёт командный клип — фон НЕ перебивает.
func play(anim_name: StringName, _blend: float = 0.0, speed: float = 1.0, _from_end: bool = false) -> void:
	var is_bg: bool = (anim_name == A_IDLE or anim_name == A_WALK or anim_name == A_FALL)
	if _command_active and is_bg:
		return
	# Командные клипы лочат флип; фон — отпускает
	_flip_locked = (not is_bg)
	_play(anim_name, (anim_name == A_IDLE or anim_name == A_WALK), speed)
	current = anim_name
	# Если это не фон — помним как команду
	if not is_bg:
		_command_active = true
		_current_cmd = anim_name

func stop(reset: bool = false) -> void:
	if sprite != null:
		sprite.stop()
	if reset:
		current = &""
	_command_active = false
	_current_cmd = &""
	_flip_locked = false

func is_playing(anim_name: StringName = &"") -> bool:
	if sprite == null:
		return false
	if String(anim_name) == "":
		return sprite.is_playing()
	return sprite.is_playing() and StringName(sprite.animation) == anim_name

# Врапперы
func play_idle() -> void:
	if _command_active:
		return
	_flip_locked = false
	_play(A_IDLE, true, 1.0)
	current = A_IDLE

func play_walk() -> void:
	if _command_active:
		return
	_flip_locked = false
	_play(A_WALK, true, 1.0)
	current = A_WALK

func play_attack(idx: int) -> void:
	var id: StringName = (A_ATTACK_2 if idx == 2 else A_ATTACK_1)
	_flip_locked = true
	_play(id, false, 1.0)
	current = id
	_command_active = true
	_current_cmd = id

func force_facing_for_hurt(dir: int) -> void:
	# Разовый принудительный флип перед Hurt
	_flip_locked = false
	set_facing(dir)
	_flip_locked = true

func play_hurt() -> void:
	var id: StringName = (A_HURT if _has(A_HURT) else A_IDLE)
	_flip_locked = true
	_play(id, false, 1.0)
	current = id
	_command_active = true
	_current_cmd = id

func play_evade() -> void:
	var id: StringName = get_evade_id()
	_flip_locked = true
	_play(id, false, 1.0)
	current = id
	_command_active = true
	_current_cmd = id

func play_death() -> void:
	# смерть должна перебить всё
	_flip_locked = true
	_play(A_DEATH, false, 1.0)
	current = A_DEATH
	_command_active = true
	_current_cmd = A_DEATH

func play_jump() -> void:
	_flip_locked = true
	_play(A_JUMP, false, 1.0)
	current = A_JUMP
	_command_active = true
	_current_cmd = A_JUMP

func play_fall() -> void:
	# падение считаем фоновым (не лочит флип)
	if _command_active:
		return
	_flip_locked = false
	_play(A_FALL, true, 1.0)
	current = A_FALL

# Длина клипа
func get_clip_len(anim_name: StringName, fallback: float) -> float:
	if sprite != null and sprite.sprite_frames != null and _has(anim_name):
		var frames: SpriteFrames = sprite.sprite_frames
		var anim_key: String = String(anim_name)
		var fps: float = max(1.0, float(frames.get_animation_speed(anim_key)))
		var count: int = max(1, int(frames.get_frame_count(anim_key)))
		return float(count) / fps
	return fallback

# Getters
func get_idle_id() -> StringName:
		return A_IDLE
func get_walk_id() -> StringName:
		return A_WALK
func get_attack1_id() -> StringName:
		return A_ATTACK_1
func get_attack2_id() -> StringName:
		return A_ATTACK_2
func get_hurt_id() -> StringName:
		return A_HURT
func get_evade_id() -> StringName:
	# Lazy-resolve: первый вызов — вычисляем и запоминаем, далее — из кэша
	if String(_evade_resolved) != "":
		return _evade_resolved
	_evade_resolved = _resolve_evade_id()
	return _evade_resolved
func get_death_id() -> StringName:
		return A_DEATH
func get_jump_id() -> StringName:
		return A_JUMP
func get_fall_id() -> StringName:
		return A_FALL
