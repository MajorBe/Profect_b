class_name RunState
extends State

const STEP_FWD: float = 0.05
const STEP_UP: float  = 0.12

func enter() -> void:
	pass

func is_ground_state() -> bool:
	return true

func update(_delta: float) -> void:
	var inp: Dictionary = owner.input


	# урон перебивает
	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return

	# прыжок — раньше всего
	if bool(inp["jump_pressed"]) or owner.consume_jump_buffer_on_ground():
		owner.change_state(JumpState.new(owner))
		return

	if bool(inp.get("heal_pressed", false)) and owner.is_on_floor():
		owner.change_state(HealState.new(owner))
		return

	# направление по знаку ввода (-1, 0, +1)
	var dir: int = int(sign(float(inp["move_x"])))

	# нет ввода → Idle
	if dir == 0:
		owner.change_state(IdleState.new(owner))
		return

	# единый источник правды для направления
	owner.update_facing(dir)

	# --- дружелюбная к наклонам проверка стены ---
	var forward: Vector3 = Vector3(dir * STEP_FWD, 0.0, 0.0)
	var blocked_low: bool = owner.test_move(owner.global_transform, forward)

	var up_xform: Transform3D = owner.global_transform.translated(Vector3(0.0, STEP_UP, 0.0))
	var blocked_high: bool = owner.test_move(up_xform, forward)

	var real_wall: bool = blocked_low and blocked_high

	if real_wall:
		# настоящая стена — стоим, но остаёмся в Run (анимация Idle)
		owner.velocity.x = 0.0
		if spr.animation != "Idle":
			spr.play("Idle")
	else:
		# наклон/бортик или свободно — бежим
		owner.velocity.x = dir * owner.speed
		if spr.animation != "Run":
			spr.play("Run")

	# подкат (SlideState возьмёт направление из facing_dir)
	if bool(inp["slide_pressed"]) and owner.is_on_floor() and owner.slide_cooldown_timer <= 0.0 and not owner.is_crouching:
		owner.change_state(SlideState.new(owner))
		return

	# атака
	if bool(inp["attack_pressed"]):
		owner.change_state(AttackState.new(owner))
		return

	# потеря пола
	if not owner.is_on_floor():
		owner.change_state(FallState.new(owner))
		return
