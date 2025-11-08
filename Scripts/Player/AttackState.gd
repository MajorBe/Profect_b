class_name AttackState
extends State

# Оставляю твои константы (не используются для локального буфера — логика комбо в сабле)
const RESET_SEC: float = 1.0
const MAX_CMD_STEPS: int = 2

# Флаги «идёт ли персонажная анимация приказа»
var _cmd_playing: bool = false
# Старая очередь больше не используется, но оставляю поле, если где-то снаружи к нему обращаются
var _press_times: PackedFloat64Array = PackedFloat64Array()

func enter() -> void:
	owner.is_attacking = true
	owner.is_crouching = false

	# Подписка на завершение персонажной анимации (клипы Attack* НЕ должны лупиться)
	if spr and not spr.animation_finished.is_connected(_on_spr_animation_finished):
		spr.animation_finished.connect(_on_spr_animation_finished)

	# Подписка на саблю — она источник «истинного» тайминга атаки
	if owner.saber:
		if not owner.saber.attack_started.is_connected(_on_saber_attack_started):
			owner.saber.attack_started.connect(_on_saber_attack_started)
		if not owner.saber.attack_finished.is_connected(_on_saber_attack_finished):
			owner.saber.attack_finished.connect(_on_saber_attack_finished)

	# Первое нажатие при входе — только через саблю (без локального буфера)
	_handle_attack_press(true)

func is_ground_state() -> bool:
	return true

func exit() -> void:
	owner.is_attacking = false
	_cmd_playing = false
	_press_times.clear()

	if spr and spr.animation_finished.is_connected(_on_spr_animation_finished):
		spr.animation_finished.disconnect(_on_spr_animation_finished)

	if owner.saber:
		if owner.saber.attack_started.is_connected(_on_saber_attack_started):
			owner.saber.attack_started.disconnect(_on_saber_attack_started)
		if owner.saber.attack_finished.is_connected(_on_saber_attack_finished):
			owner.saber.attack_finished.disconnect(_on_saber_attack_finished)

func update(_delta: float) -> void:
	# Движение вперёд — только пока идёт персонажный клип
	if spr and spr.is_playing():
		owner.velocity.x = owner.facing_dir * owner.attack_move_speed
	else:
		owner.velocity.x = 0.0

	# Новые нажатия — только через саблю (никаких локальных очередей)
	if bool(owner.input.get("attack_pressed", false)):
		_handle_attack_press(false)

	# Переходы состояний
	if not owner.is_on_floor():
		owner.change_state(JumpAttackState.new(owner))
		return

	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return

	# Если персонажная анимация НЕ идёт и сабля тоже НЕ атакует — выходим в Idle
	if not _cmd_playing and (not owner.saber or not owner.saber.is_attacking()):
		owner.change_state(IdleState.new(owner))
		return

# ========================= ВНУТРЕННЕЕ =========================

# Обработка нажатия — только через саблю. Локальные очереди выключены.
func _handle_attack_press(_is_first: bool) -> void:

	owner.saber.set_collider_profile(&"stand")

	# Если сабля уже играет клип — ставим «буфер конца» (0.3с по умолчанию в сабле)
	if owner.saber.has_method("is_attacking") and owner.saber.is_attacking():
		if owner.saber.has_method("queue_next_if_within"):
			owner.saber.queue_next_if_within(owner.saber.end_buffer_sec)
		elif owner.saber.has_method("request_next_attack_in_cycle"):
			# Старый безопасный метод без прерывания
			owner.saber.request_next_attack_in_cycle()
		else:
			# Самый старый фоллбэк
			if owner.saber.has_method("attack_ground_cycle"):
				owner.saber.attack_ground_cycle(false)
		return

	# Сабля свободна — запускаем следующий шаг комбо
	if owner.saber.has_method("try_attack_next_in_cycle"):
		owner.saber.try_attack_next_in_cycle()
	elif owner.saber.has_method("attack_ground"):
		owner.saber.attack_ground()
	elif owner.saber.has_method("attack_ground_cycle"):
		owner.saber.attack_ground_cycle(false)

# ===== Сигналы от сабли =====

# Сабля реально стартовала атаку — проигрываем ОДИН клип персонажа
func _on_saber_attack_started(clip: StringName, _length: float) -> void:
	if not spr or not spr.sprite_frames:
		_cmd_playing = false
		return
	var anim_id := _pick_actor_anim(clip)
	_cmd_playing = _play_actor_anim(anim_id)
	

# Завершение сабельной атаки — переходы решит update() по _cmd_playing
func _on_saber_attack_finished(_clip: StringName) -> void:
	# Ничего не делаем здесь
	pass

# Персонажная «анимация приказа» доиграла — прекращаем движение вперёд
func _on_spr_animation_finished() -> void:
	_cmd_playing = false

# ===================== УТИЛИТЫ =====================

# Надёжный выбор анимации персонажа под имя клипа сабли
func _pick_actor_anim(clip: StringName) -> String:
	# Приоритет:
	# 1) Attack{цифра из конца имени клипа сабли}
	# 2) По подстроке без регистра: attack3/2/1
	# 3) Любая анимация, начинающаяся с "Attack"
	# 4) Фоллбэк "Attack1"
	var frames := spr.sprite_frames
	var names := frames.get_animation_names()

	# 1) Хвостовая цифра
	var s := String(clip)
	var step := 1
	if s.length() > 0:
		var last_char := s.substr(s.length() - 1, 1)
		if last_char.is_valid_int():
			step = int(last_char)
	var candidate := "Attack%d" % step
	if frames.has_animation(candidate):
		return candidate

	# 2) Поиск по подстроке без регистра
	var low := s.to_lower()
	if low.find("attack3") != -1 and frames.has_animation("Attack3"):
		return "Attack3"
	if low.find("attack2") != -1 and frames.has_animation("Attack2"):
		return "Attack2"
	if low.find("attack1") != -1 and frames.has_animation("Attack1"):
		return "Attack1"

	# 3) Любой Attack*
	for n in names:
		var nn := String(n)
		if nn.begins_with("Attack"):
			return nn

	# 4) Фоллбэк
	return "Attack1"

# Жёсткий и безопасный запуск анимации персонажа
func _play_actor_anim(anim_id: String) -> bool:
	var frames := spr.sprite_frames
	if not frames:
		return false

	# Выключаем луп у нужного клипа, чтобы движение не «залипало»
	if frames.has_animation(anim_id):
		frames.set_animation_loop(anim_id, false)
	else:
		# Фоллбэк на Attack1, если нужного нет
		if frames.has_animation("Attack1"):
			anim_id = "Attack1"
			frames.set_animation_loop("Attack1", false)
		else:
			return false

	# Жёсткий рестарт с кадра 0
	spr.stop()
	spr.frame = 0
	spr.speed_scale = 1.0
	spr.play(anim_id)
	return true
