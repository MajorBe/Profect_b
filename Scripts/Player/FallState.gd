class_name FallState
extends State

func enter() -> void:
	# Если активен drop-through — продолжаем играть его анимацию
	if owner.dropper.is_active():
		if spr.animation != "DropThrough":
			spr.play("DropThrough")
	else:
		spr.play("Fall")

	# если начали падать — сброс таймера падения
	if owner.fall_time < 0.0:
		owner.fall_time = 0.0

func update(delta: float) -> void:
	var inp: Dictionary = owner.input

	# считаем длительность падения (для авто-ролла при приземлении)
	owner.fall_time += delta

	# управление в воздухе + флип
	var mx: int = int(inp["move_x"])
	owner.velocity.x = float(mx) * owner.speed
	if mx != 0 and not owner.lock_facing:
		owner.facing_dir = mx
		owner.apply_flip()

	# поддерживаем корректную анимацию на время drop-through
	if owner.dropper.is_active():
		if spr.animation != "DropThrough":
			spr.play("DropThrough")
	else:
		if spr.animation != "Fall":
			spr.play("Fall")

	# one-way платформы (на время активного drop-through или активного падения)
	if owner.velocity.y > 1.0 or owner.dropper.is_active():
		owner.collision_mask &= ~owner.platform_layer_mask
	else:
		owner.collision_mask |= owner.platform_layer_mask

	# гравитация
	owner.apply_gravity(delta)

	# === Прыжки ===
	# Первый прыжок в воздухе только по койот-тайму
	if bool(inp["jump_pressed"]) and owner.jump_count == 0 and owner.coyote_counter > 0.0:
		owner.change_state(JumpState.new(owner))
		return

	# Мульти-прыжок (второй и далее)
	if bool(inp["jump_pressed"]):
		if owner.air_jumps_left > 0 or owner.time_since_on_floor <= owner.coyote_like_time:
			owner.change_state(JumpState.new(owner))
			return

	# === Приземление ===
	if owner.is_on_floor():
		owner.jump_count = 0
		owner.dropper.cancel()

		# авто-ролл после долгого падения (если у тебя есть RollState)
		if owner.fall_time >= owner.min_fall_time_for_roll and owner.slide_cooldown_timer <= 0.0:
			owner.change_state(RollState.new(owner))
		else:
			owner.change_state(IdleState.new(owner))

		owner.fall_time = 0.0
		return

	# Атака в воздухе
	if bool(inp["attack_pressed"]):
		owner.change_state(JumpAttackState.new(owner))
		return

	# Получение урона
	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return
