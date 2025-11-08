extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_AttackState

# ============================================================================= # Константы (тайминги, поведение) # =============================================================================

# Длительности клипов (чтобы не зависеть от get_clip_len)
const ATTACK1_LEN: float = 0.60
const ATTACK2_LEN: float = 0.55
const MIN_CLIP_LEN: float = 0.10

# Движение во время удара
const ATTACK_MOVE_FACTOR: float = 0.5	# 0.5× от walk_speed
const FRONT_EPS: float = 0.05			# допуск на границе фронт/тыл

# КД и шанс эвейда
const COOLDOWN_MIN: float = 0.2
const COOLDOWN_MAX: float = 1.5
const EVADE_CHANCE: float = 0.35

# Окна урона в долях длительности клипа (0..1)
const HB1_FROM_N: float = 0.18
const HB1_TO_N:   float = 0.36
const HB2_FROM_N: float = 0.12
const HB2_TO_N:   float = 0.32

# Экспорт / ссылки на ноды

@export_node_path("AnimationPlayer") var evt_player_path: NodePath

# Кэш идентификаторов клипов (из EnemyAnimation)

var IDLE_ID: StringName
var WALK_ID: StringName
var ATK1_ID: StringName
var ATK2_ID: StringName

# Внутренние ссылки 

var _evt: AnimationPlayer = null
var _hb1: EnemyHitbox = null
var _hb2: EnemyHitbox = null

# Текущее состояние серии

var _attacks_left: int = 2
var _next_idx: int = 1
var _t: float = 0.0
var _clip_len: float = 0.6
var _in_cd: bool = false
var _cooldown_left: float = 0.0

# Прочее внутреннее состояние

var _attack_face_dir: int = 1
var _current_anim_name: StringName = &""
var _my_attack_token: int = -1

# Жизненный цикл состояния

func enter() -> void:
	# --- безопасно подтянуть ссылки (если базовый класс ещё не инициализировал) ---
	if anim == null:
		anim = owner.get_node_or_null(NodePath("Animation")) as EnemyAnimation
		if anim == null:
			var cand_anim := [NodePath("Body/Animation"), NodePath("Anim")]
			for p in cand_anim:
				var node := owner.get_node_or_null(p)
				if node is EnemyAnimation:
					anim = node as EnemyAnimation
					break

	if locomotion == null:
		locomotion = owner.get_node_or_null(NodePath("Locomotion")) as EnemyLocomotion

	if perception == null:
		perception = owner.get_node_or_null(NodePath("Perception")) as EnemyPerception

	if body == null:
		body = owner.get_node_or_null(NodePath("Body")) as CharacterBody3D
		if body == null and owner is CharacterBody3D:
			body = owner as CharacterBody3D

	# --- получить хитбоксы из сцены ---
	_hb1 = owner.get_node_or_null(NodePath("Body/Hitboxes/Attack1HB")) as EnemyHitbox
	_hb2 = owner.get_node_or_null(NodePath("Body/Hitboxes/Attack2HB")) as EnemyHitbox

	# --- получить AnimationPlayer для событий ---
	if _evt == null and evt_player_path != NodePath():
		_evt = owner.get_node_or_null(evt_player_path) as AnimationPlayer
	if _evt == null:
		_evt = owner.get_node_or_null(NodePath("AnimationPlayer")) as AnimationPlayer
	if _evt == null:
		_evt = owner.get_node_or_null(NodePath("Body/AnimationPlayer")) as AnimationPlayer

	# --- кэш ID анимаций (устойчиво к любым именам клипов) ---
	if anim != null:
		IDLE_ID = anim.get_idle_id()
		WALK_ID = anim.get_walk_id()
		ATK1_ID = anim.get_attack1_id()
		ATK2_ID = anim.get_attack2_id()
	else:
		# безопасные дефолты (если по какой-то причине анимации нет)
		IDLE_ID = &"Idle"
		WALK_ID = &"Walk"
		ATK1_ID = &"Attack1"
		ATK2_ID = &"Attack2"

	# --- снимаем ворота, чтобы дальше можно было снова входить в атаку ---
	if owner != null:
		var gate = owner.get("attack_gate")
		if typeof(gate) != TYPE_NIL and gate == true:
			owner.set("attack_gate", false)

	# --- глушим внешнее движение на входе ---
	if locomotion != null and locomotion.has_method("stop"):
		locomotion.stop()
	if body != null:
		var v := body.velocity
		v.x = 0.0
		body.velocity = v

	# --- единоразово выровняться на цель до серии (дальше — фейс залочен) ---
	var dir_i: int = 0
	if perception != null and perception.has_target and body != null:
		var pl := perception.get_player()
		if pl != null:
			dir_i = int(sign(pl.global_position.x - body.global_position.x))
	if dir_i == 0:
		var fd = owner.get("facing_dir")
		dir_i = int(fd) if typeof(fd) != TYPE_NIL else 1

	# синхронизируем и Actor, и Sprite
	if owner.has_method("set_facing_dir"):
		owner.call("set_facing_dir", dir_i)
	if anim != null:
		anim.set_facing(dir_i)

	_attack_face_dir = (dir_i if dir_i != 0 else 1)

	# --- закрыть окна урона (страховка) ---
	if _hb1: _hb1.cancel_window()
	if _hb2: _hb2.cancel_window()

	# --- токен серии (для отладки/сигналов) ---
	var tok := int(owner.get_meta("attack_token", 0)) + 1
	owner.set_meta("attack_token", tok)
	_my_attack_token = tok

	_play_current_clip()

func update(dt: float) -> void:
	# --- режим КД ---
	if _in_cd:
		_cooldown_left -= dt
		if _cooldown_left <= 0.0:
			if body != null:
				var v := body.velocity
				v.x = 0.0
				body.velocity = v
			owner._change_state(Cossack_01_ApproachState.new(owner))
		return

	# --- движение вперёд во время удара (без разворота) ---
	if body != null and config != null:
		var v2 := body.velocity
		v2.x = float(_attack_face_dir) * float(config.walk_speed) * ATTACK_MOVE_FACTOR
		body.velocity = v2

	# --- реаффирмация анимации (на случай, если кто-то сбил) ---
	if anim != null and _current_anim_name != StringName():
		if anim.current != _current_anim_name or (anim.sprite != null and not anim.sprite.is_playing()):
			anim.play(_current_anim_name)

	# --- таймер клипа ---
	_t += dt
	if _t >= _clip_len:
		if _attacks_left > 0:
			_play_current_clip()
		else:
			_post_combo()

func exit() -> void:
	# --- сброс скорости и ворот ---
	if body != null:
		var v := body.velocity
		v.x = 0.0
		body.velocity = v

	var gate = owner.get("attack_gate")
	if typeof(gate) != TYPE_NIL and gate == true:
		owner.set("attack_gate", false)

	# --- закрыть окна/остановить evt ---
	if _hb1: _hb1.cancel_window()
	if _hb2: _hb2.cancel_window()
	if _evt != null:
		_evt.stop()
	if _hb1 != null:
		_hb1.end_window()
	if _hb2 != null:
		_hb2.end_window()

# ============================================================================= # Внутренние методы # =============================================================================

func _play_current_clip() -> void:
	# 1) Выбор клипа и ожидаемой длительности
	_current_anim_name = ATK1_ID
	_clip_len = ATTACK1_LEN
	if _next_idx == 2:
		_current_anim_name = ATK2_ID
		_clip_len = ATTACK2_LEN
	if _clip_len < MIN_CLIP_LEN:
		_clip_len = MIN_CLIP_LEN

	# 2) Играем визуал удара
	var started := false
	if anim != null:
		if anim.has_method("play_attack"):
			anim.play_attack(_next_idx)
			started = true
		# подстраховка: явно выставляем текущий клип
		anim.play(_current_anim_name)
		started = true

	# 3) Синхронно запустить одноимённый клип событий в AnimationPlayer (если есть)
	if _evt != null:
		var evt_id: StringName = (ATK2_ID if _next_idx == 2 else ATK1_ID)
		var evt_name: String = String(evt_id)
		var an := _evt.get_animation(evt_name)
		if an != null:
			var L_evt := an.length
			if L_evt <= 0.0:
				L_evt = _clip_len
			# Godot 4: play(name, custom_blend, custom_speed, from_end)
			# хотим: фактическая длительность события = _clip_len
			_evt.play(evt_name, -1.0, L_evt / _clip_len, false)

	# 4) Если анимация не стартанула — небольшой КД и выход
	if not started:
		_in_cd = true
		_cooldown_left = 0.3
		return

	# 5) Подготовка к следующему удару
	_next_idx = (2 if _next_idx == 1 else 1)
	_attacks_left -= 1
	_t = 0.0

func _post_combo() -> void:
	# попытка эвейда: только если глобальный КД эвейда не активен
	var can_evade := true
	var ev_left = owner.get("EvadeCooldownLeft")
	if typeof(ev_left) != TYPE_NIL:
		can_evade = float(ev_left) <= 0.0

	# Эвейд только если игрок ПЕРЕД врагом (а не за спиной)
	var is_player_in_front := true
	if perception != null and perception.has_target and body != null:
		var pl := perception.get_player()
		if pl != null:
			var dx := float(pl.global_position.x - body.global_position.x)
			is_player_in_front = (dx * float(_attack_face_dir)) >= -FRONT_EPS

	var do_evade := can_evade and is_player_in_front and (randf() < EVADE_CHANCE)

	if do_evade:
		if body != null:
			var v := body.velocity
			v.x = 0.0
			body.velocity = v
		owner._change_state(Cossack_01_EvadeState.new(owner))
		return

	# обычный КД (если эвейд не сработал или на КД)
	_in_cd = true
	_cooldown_left = lerp(COOLDOWN_MIN, COOLDOWN_MAX, randf())
	if anim != null:
		anim.play_idle()
	if body != null:
		var v2 := body.velocity
		v2.x = 0.0
		body.velocity = v2

func _open_hitbox_window_for_current_clip() -> void:
	if _clip_len <= 0.0:
		return
	if _next_idx == 1 and _hb1 != null:
		_hb1.open_window_sec(HB1_FROM_N * _clip_len, HB1_TO_N * _clip_len, owner)
	elif _next_idx == 2 and _hb2 != null:
		_hb2.open_window_sec(HB2_FROM_N * _clip_len, HB2_TO_N * _clip_len, owner)
