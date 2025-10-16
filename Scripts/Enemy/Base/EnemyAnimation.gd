# Scripts/Scripts/Enemy/EnemyAnimation.gd
extends Node
class_name EnemyAnimation

var actor: Node3D
var sprite: AnimatedSprite3D

var current: StringName = &""
var _flip_locked: bool = false

# Универсальная карта имён клипов (может быть переопределена владельцем через get_anim_map()).
@export var anim_map := {
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

# Резолвнутые ключи клипов (StringName):
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

func _ready() -> void:
	actor = get_parent() as Node3D
	if actor == null:
		push_warning("EnemyAnimation: parent is not Node3D")
		return

	# Если владелец предоставляет карту клипов — мержим поверх export-а.
	if actor.has_method("get_anim_map"):
		var ext = actor.call("get_anim_map")
		if typeof(ext) == TYPE_DICTIONARY:
			for k in ext.keys():
				anim_map[k] = ext[k]

	_apply_anim_map()

	# Ищем AnimatedSprite3D
	sprite = actor.get_node_or_null(NodePath("AnimatedSprite3D")) as AnimatedSprite3D
	if sprite == null:
		var cand := [
			NodePath("Body/AnimatedSprite3D"),
			NodePath("Body/Sprite"),
			NodePath("Sprite"),
		]
		for p in cand:
			var s := actor.get_node_or_null(p)
			if s is AnimatedSprite3D:
				sprite = s as AnimatedSprite3D
				break
	if sprite == null:
		push_warning("EnemyAnimation: AnimatedSprite3D not found on actor")
		return

	if sprite.is_playing():
		sprite.stop()
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(String(A_IDLE)):
		sprite.animation = String(A_IDLE) # выбрать клип как базовый (без старта)
		sprite.sprite_frames.set_animation_loop(String(A_IDLE), true)

	# Ничего не запускаем здесь — старт делает IdleState.enter() конкретного врага.

func is_flip_locked() -> bool:
	return _flip_locked

func set_facing(dir: int) -> void:
	# dir: -1 (влево), +1 (вправо). Базовый спрайт смотрит влево — flip_h для вправо.
	# Во время атаки/хита — флип заблокирован.
	if _flip_locked:
		return

	if sprite != null:
		sprite.flip_h = (dir > 0)

	# --- зеркалим привязанные боковые ноды только когда не залочено ---
	var dir_sign := (1 if dir > 0 else -1)
	if actor != null:
		var hb := actor.get_node_or_null("Hitbox")
		if hb is Node3D:
			var hb3 := hb as Node3D
			var p := hb3.position
			p.x = abs(p.x) * float(dir_sign)  # не накапливаем
			hb3.position = p

		var pivot := actor.get_node_or_null("WeaponPivot")
		if pivot is Node3D:
			var pv := (pivot as Node3D)
			var sc := pv.scale
			sc.x = abs(sc.x) * float(dir_sign)
			pv.scale = sc

# --- ВНУТРЕННЕЕ --------------------------------------------------------------

func _has(anim: StringName) -> bool:
	if sprite == null or sprite.sprite_frames == null:
		return false
	return sprite.sprite_frames.has_animation(String(anim))

func _set_loop(anim: StringName, on: bool) -> void:
	var frames := sprite.sprite_frames
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

	# Обновляем loop без рестарта
	_set_loop(anim, loop_default)

	# Если уже выбран тот же клип
	if sprite.animation == anim_key:
		# Обновим скорость, если поменялась, но без рестарта
		if not is_equal_approx(sprite.speed_scale, speed):
			sprite.speed_scale = speed

		# Если уже играет — ничего не делаем (не сбрасываем на кадр 0)
		if sprite.is_playing():
			current = anim
			return

		# Если был на паузе/остановлен — просто продолжим тот же клип
		sprite.play()
		current = anim
		return

	# Переключение на НОВЫЙ клип: назначаем, выставляем скорость и запускаем
	sprite.animation = anim_key
	sprite.speed_scale = speed
	sprite.play()
	current = anim

# --- ПУБЛИЧНОЕ API ДЛЯ СОСТОЯНИЙ --------------------------------------------

# Совместимость со старыми вызовами (blend/from_end игнорируются для AnimatedSprite3D)
func play(anim_name: StringName, _blend: float = 0.0, speed: float = 1.0, _from_end: bool = false) -> void:
	var loop := (anim_name == A_IDLE or anim_name == A_WALK)
	_flip_locked = not loop
	_play(anim_name, loop, speed)
	current = anim_name

func play_idle() -> void:
	_flip_locked = false
	_play(A_IDLE, true)

func play_walk() -> void:
	_flip_locked = false
	_play(A_WALK, true)

func play_attack(idx: int) -> void:
	# Во время атаки флип фиксируется
	_flip_locked = true
	if idx == 2:
		_play(A_ATTACK_2, false)
	else:
		_play(A_ATTACK_1, false)

func force_facing_for_hurt(dir: int) -> void:
	# Разрешаем один принудительный флип перед стартом Hurt
	# (даже если уже был _flip_locked от предыдущего клипа)
	_flip_locked = false
	set_facing(dir)
	_flip_locked = true

func play_hurt() -> void:
	# Хитстън: фиксируем флип, не лупаем
	_flip_locked = true

	# Безопасный запуск: если клипа "Hurt" вдруг нет — фоллбэк
	if _has(A_HURT):
		_play(A_HURT, false)
	else:
		# Фоллбэк — хотя бы заметная реакция вместо «тишины»
		_play(A_IDLE, true)

func play_evade() -> void:
	_flip_locked = true
	_play(A_EVADE, false)

func play_death() -> void:
	_flip_locked = true
	_play(A_DEATH, false)

func play_jump() -> void:
	_flip_locked = true
	_play(A_JUMP, false)

func play_fall() -> void:
	_flip_locked = true
	_play(A_FALL, true)

func get_clip_len(anim_name: StringName, fallback: float) -> float:
	if sprite != null and sprite.sprite_frames != null and _has(anim_name):
		var frames: SpriteFrames = sprite.sprite_frames
		var anim_key: String = String(anim_name)
		var fps: float = max(1.0, float(frames.get_animation_speed(anim_key)))
		var count: int = max(1, int(frames.get_frame_count(anim_key)))
		return float(count) / fps
	return fallback

# --- PUBLIC GETTERS FOR CLIP IDS (for external modules) ---
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
	return A_EVADE
func get_death_id() -> StringName:
	return A_DEATH
func get_jump_id() -> StringName:
	return A_JUMP
func get_fall_id() -> StringName:
	return A_FALL
