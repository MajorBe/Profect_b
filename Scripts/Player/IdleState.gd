class_name IdleState
extends State

func enter() -> void:
	owner._switch_to_stand()
	if owner.saber:
		owner.saber.set_collider_profile(&"stand")
		owner.saber.set_move_mode(&"idle")
	owner.velocity.x = 0.0
	spr.play("Idle")

func is_ground_state() -> bool:
	return true

func update(_delta: float) -> void:
	var inp: Dictionary = owner.input

	# урон
	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return

	# drop-through (вниз + прыжок) — ПРИОРИТЕТ №1
	if bool(inp["crouch_pressed"]) and bool(inp["jump_pressed"]):
		owner.dropper.start_drop()
		return

	# присед из статики
	if bool(inp["crouch_pressed"]) and owner.is_on_floor() and int(inp["move_x"]) == 0:
		owner.change_state(CrouchState.new(owner))
		return

	# слайд
	if bool(inp["slide_pressed"]) and owner.is_on_floor() and owner.slide_cooldown_timer <= 0.0 and not owner.is_crouching:
		owner.change_state(SlideState.new(owner))
		return


	# прыжок с места — ПРИОРИТЕТНЕЕ движения, даже у стены
	if (bool(inp["jump_pressed"]) and owner.is_on_floor()) or owner.consume_jump_buffer_on_ground():
		owner.change_state(JumpState.new(owner))
		return

	# движение → Run (c анти-миганием у стены)
	var dir: int = int(inp["move_x"])
	if dir != 0 and not owner.lock_facing:
		var STEP_FWD: float = 0.05
		var STEP_UP: float = 0.12

		var forward: Vector3 = Vector3(dir * STEP_FWD, 0.0, 0.0)
		var blocked_low: bool = owner.test_move(owner.global_transform, forward)

		var up_xform: Transform3D = owner.global_transform.translated(Vector3(0.0, STEP_UP, 0.0))
		var blocked_high: bool = owner.test_move(up_xform, forward)

		var real_wall: bool = blocked_low and blocked_high

		if real_wall:
			owner.velocity.x = 0.0
			owner.facing_dir = dir
			owner.apply_flip()
			return

		owner.facing_dir = dir
		owner.apply_flip()
		owner.change_state(RunState.new(owner))
		return

	# атака
	if bool(inp["attack_pressed"]):
		owner.change_state(AttackState.new(owner))
		return

	# лечение
	if bool(inp["heal_pressed"]) and owner.heals_left > 0:
		owner.change_state(HealState.new(owner))
		return

	# потеря пола
	if not owner.is_on_floor():
		owner.change_state(FallState.new(owner))
		return
