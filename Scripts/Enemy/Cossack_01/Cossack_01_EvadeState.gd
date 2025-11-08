extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_EvadeState  

const EVADE_SPEED_FACTOR: float = 1.5

var _t: float = 0.0
var _clip_len: float = 0.45
var _face_dir_on_enter: int = 1

func enter() -> void:
	# Всегда с нуля, чтобы не «схлопывался» моментально
	_t = 0.0

	# Направление лицом при входе
	_face_dir_on_enter = 1
	if anim and anim.sprite:
		_face_dir_on_enter = (1 if anim.sprite.flip_h else -1)
	elif owner != null:
		var fd = owner.get("facing_dir")
		if fd != null:
			_face_dir_on_enter = int(fd)

	# КД эвэйда из конфига
	if owner != null and config != null:
		owner.EvadeCooldownLeft = maxf(owner.EvadeCooldownLeft, float(config.evade_cooldown))

	# Важно: если вход из атаки — отменить командную анимацию, чтобы она не перебила эвэйд
	if anim and anim.has_method("stop_command"):
		anim.stop_command()

	# --- ЗАПУСК КЛИПА ЭВЕЙДА (ГАРАНТИРОВАННО) ---
	var clip_id: StringName = StringName("Cossack_01_Evasion") # правильный дефолт для твоей карты
	if owner != null and owner.has_method("get_anim_map"):
		var amap: Dictionary = owner.get_anim_map()
		if amap != null and amap.has("evade"):
			var ev_name: String = String(amap.get("evade"))
			if ev_name != "":
				clip_id = StringName(ev_name)

	if anim:
		# без магии методов-обёрток — просто play нужный клип
		if anim.has_method("play"):
			anim.play(clip_id, 0.0, 1.0, false)

		# длина именно этого клипа; подстраховка, если не найдёт — 0.35с
		var found_len: float = 0.0
		if anim.has_method("get_clip_len"):
			found_len = anim.get_clip_len(clip_id, 0.0)
		_clip_len = (found_len if found_len > 0.0 else 0.35)
	# -------------------------------------------

	# Задаём импульс назад сразу на входе (как у тебя было)
	_apply_back_velocity()


func update(dt: float) -> void:
	_t += dt

	# Поддерживаем откат назад весь клип
	_apply_back_velocity()

	# Защита от нулевой длины, если клип вдруг не найден
	if _clip_len <= 0.0:
		_clip_len = 0.45

	if _t >= _clip_len:
		if body:
			body.velocity.x = 0.0

		# Решение — сразу биться или вернуться в подход
		var ok: bool = can_attack_now()
		if ok:
			var atk := Cossack_01_AttackState.new(owner)
			owner._change_state(atk)
		else:
			var appr := Cossack_01_ApproachState.new(owner)
			owner._change_state(appr)
		return

func exit() -> void:
	if body:
		body.velocity.x = 0.0

func _apply_back_velocity() -> void:
	if body and config:
		body.velocity.x = -float(_face_dir_on_enter) * float(config.walk_speed) * EVADE_SPEED_FACTOR
