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
	elif "facing_dir" in owner:
		_face_dir_on_enter = int(owner.facing_dir)

	# КД эвэйда из конфига
	if owner != null and config != null:
		owner.EvadeCooldownLeft = maxf(owner.EvadeCooldownLeft, float(config.evade_cooldown))

	# Важно: если вход из атаки — отменить командную анимацию, чтобы она не перебила эвэйд
	if anim and anim.has_method("stop_command"):
		anim.stop_command()

	# Запуск клипа эвэйда + длина именно проигрываемого клипа
	if anim:
		if anim.has_method("play_evade"):
			anim.play_evade()
		elif anim.has_method("play_evasion"):
			anim.play_evasion()
		else:
			anim.play_idle()

		var clip_id: StringName = StringName("Cossack_01_Evade") # фоллбэк под твой архив
		if anim.has_method("get_evade_id"):
			clip_id = anim.get_evade_id()
		_clip_len = anim.get_clip_len(clip_id, _clip_len)

	# Задаём импульс назад сразу на входе
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
