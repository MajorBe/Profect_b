class_name JumpState
extends State

func enter() -> void:
	owner.coyote_counter = 0.0
	owner.jump_count += 1
	owner.jump_time = 0.0
	owner.jump_held_active = true
	owner.velocity.y = owner.jump_velocity
	var anim: String = "Jump" if owner.jump_count == 1 else "DoubleJump"
	spr.play(anim)
	var ground_like := owner.is_on_floor() or (owner.time_since_on_floor <= owner.coyote_like_time)

	if ground_like:
		owner.refresh_air_jumps_on_ground_like()
	else:
		owner.consume_air_jump()

	owner.velocity.y = owner.get_takeoff_speed(not ground_like)

func update(delta: float) -> void:
	var inp: Dictionary = owner.input

	# управление в воздухе + флип
	owner.velocity.x = inp["move_x"] * owner.speed
	if inp["move_x"] != 0 and not owner.lock_facing:
		owner.facing_dir = inp["move_x"]
		owner.apply_flip()

	# one-way платформы
	if owner.velocity.y > 1.0 or owner.dropper.is_active():
		owner.collision_mask &= ~owner.platform_layer_mask
	else:
		owner.collision_mask |= owner.platform_layer_mask

	# мульти-прыжок
	if inp["jump_pressed"] and owner.jump_count < owner.max_jumps:
		owner.change_state(JumpState.new(owner))
		return

	# удержание прыжка — “высота”
	if owner.jump_held_active:
		owner.jump_time += delta
		if not inp["jump_down"] or owner.jump_time >= owner.max_jump_hold_time:
			owner.jump_held_active = false

	var scale: float = 0.2 if owner.jump_held_active else 1.0
	owner.apply_gravity(delta, scale)

	# переход в падение
	if owner.velocity.y <= 0.0:
		owner.change_state(FallState.new(owner))
		return

	# атака в воздухе
	if inp["attack_pressed"]:
		owner.change_state(JumpAttackState.new(owner))
		return

	# урон
	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return
