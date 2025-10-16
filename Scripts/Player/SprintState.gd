class_name SprintState
extends State

const STEP_FWD: float = 0.05
const STEP_UP:  float = 0.12

func enter() -> void:
	# играем свою анимацию быстрого бега
	spr.play("Sprint")

func is_ground_state() -> bool:
	return true

func update(_delta: float) -> void:
	var inp: Dictionary = owner.input

	# если отпустили кнопку слайда — обычный Run
	if not bool(inp["slide_down"]):
		owner.change_state(RunState.new(owner))
		return

	# направление (-1/0/+1) — берём знак, чтобы полуось не терялась
	var dir: int = int(sign(float(inp["move_x"])))

	if bool(inp.get("heal_pressed", false)) and owner.is_on_floor():
		owner.change_state(HealState.new(owner))
		return

	# нет входа — в Idle
	if dir == 0:
		owner.change_state(IdleState.new(owner))
		return

	# единый источник правды для направления
	owner.update_facing(dir)

	# проверка «настоящей» стены, как в RunState
	var forward: Vector3 = Vector3(dir * STEP_FWD, 0.0, 0.0)
	var blocked_low: bool = owner.test_move(owner.global_transform, forward)
	var up_xform: Transform3D = owner.global_transform.translated(Vector3(0.0, STEP_UP, 0.0))
	var blocked_high: bool = owner.test_move(up_xform, forward)
	var real_wall: bool = blocked_low and blocked_high

	if real_wall:
		owner.velocity.x = 0.0
		# прижаты к стене — остаёмся в SprintState, но анимация Idle
		if spr.animation != "Idle":
			spr.play("Idle")
	else:
		owner.velocity.x = dir * owner.speed * owner.sprint_speed_multiplier
		if spr.animation != "Sprint":
			spr.play("Sprint")

	# прыжок — как обычно
	if bool(inp["jump_pressed"]) or owner.consume_jump_buffer_on_ground():
		owner.change_state(JumpState.new(owner))
		return

	# атака
	if bool(inp["attack_pressed"]):
		owner.change_state(AttackState.new(owner))
		return

	# потеря пола — в Fall
	if not owner.is_on_floor():
		owner.change_state(FallState.new(owner))
		return

	# урон
	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return

	# --- УСЛОВИЯ СТАРТА СЛАЙДА ---
	var want_crouch: bool = bool(inp.get("crouch_pressed", false)) or bool(inp.get("crouch_down", false))
	var speed_ok: bool = abs(owner.velocity.x) >= float(owner.slide_min_speed)  # <-- явный bool + float(...)
	var on_floor: bool = owner.is_on_floor()

	# Не даём случайный drop-through: тут НЕ реагируем на crouch+jump.
	if want_crouch and speed_ok and on_floor:
		owner.change_state(SlideState.new(owner))
		return

	# Сход с края → твоя обычная логика в Fall (как было)
	if not on_floor:
		owner.change_state(FallState.new(owner))
		return
