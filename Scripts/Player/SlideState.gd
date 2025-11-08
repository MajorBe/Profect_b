class_name SlideState
extends State

var slide_dir: int = 1

const STEP_FWD: float = 0.06
const STEP_UP: float  = 0.16
const STICK_DOWN: float = -0.06
const GROUND_GRACE_TIME: float = 0.08

var ground_grace: float = 0.0

func enter() -> void:
	# фиксируем направление в момент входа
	owner.set_slide_active(true)
	slide_dir = owner.facing_dir
	owner.apply_flip()

	# таймеры и статусы
	owner.slide_timer = owner.slide_duration
	owner.slide_invuln_timer = owner.slide_invuln_time
	owner.slide_cooldown_timer = owner.slide_cooldown

	owner.lock_facing = true
	owner._switch_to_crouch()
	spr.play("Slide")

	owner.set_collide_with_enemies(false)

	# если по дизайну надо гасить моментальную скорость — оставляем так
	owner.velocity = Vector3.ZERO

	# сразу даём небольшую «терпимость» отрыва от пола на кромках
	ground_grace = GROUND_GRACE_TIME

	if owner.saber:
		owner.saber.set_collider_profile(&"crouch")

func exit() -> void:
	owner.set_slide_active(false)
	if owner.saber:
		owner.saber.set_collider_profile(&"stand")
	owner.lock_facing = false
	owner._switch_to_stand()
	owner.set_collide_with_enemies(true)


func is_ground_state() -> bool:
	return true


func update(delta: float) -> void:
	var inp: Dictionary = owner.input

	# 1) ВЫХОД ПО ПРЫЖКУ: только если на земле
	if bool(inp.get("jump_pressed", false)) and owner.is_on_floor():
		owner.change_state(JumpState.new(owner))
		return

	# 2) БАЗОВОЕ СКОЛЬЖЕНИЕ
	owner.velocity.x = float(slide_dir) * owner.speed * owner.slide_speed_multiplier

	# 3) «ДРУЖЕСТВЕННО К БОРТИКАМ»: шаг вперёд с микро-приподниманием
	var forward: Vector3 = Vector3(float(slide_dir) * STEP_FWD, 0.0, 0.0)
	var blocked_low: bool = owner.test_move(owner.global_transform, forward)
	if blocked_low and owner.is_on_floor():
		var up_xf: Transform3D = owner.global_transform.translated(Vector3(0.0, STEP_UP, 0.0))
		var blocked_high: bool = owner.test_move(up_xf, forward)
		if not blocked_high:
			owner.global_transform = up_xf
			if owner.velocity.y > STICK_DOWN:
				owner.velocity.y = STICK_DOWN
			ground_grace = GROUND_GRACE_TIME
		else:
			owner.velocity.x = 0.0

	# 4) ТАЙМЕРЫ
	owner.slide_timer = owner.cd(owner.slide_timer, delta)
	if owner.slide_invuln_timer > 0.0:
		owner.slide_invuln_timer = owner.cd(owner.slide_invuln_timer, delta)

	# 5) УДЕРЖАНИЕ НА ЗЕМЛЕ С "GRACE"
	var on_floor: bool = owner.is_on_floor()
	if on_floor:
		# обновляем «терпимость» каждый раз, когда снова касаемся пола
		ground_grace = GROUND_GRACE_TIME
	else:
		ground_grace -= delta
		if ground_grace <= 0.0:
			owner.velocity.y = min(owner.velocity.y, 0.0) 
			owner.change_state(FallState.new(owner))
			return

	# 6) АВТО-ЗАВЕРШЕНИЕ ПО ВРЕМЕНИ
	if owner.slide_timer <= 0.0:
		var dir: int = int(owner.input.get("move_x", 0))
		owner.velocity.y = min(owner.velocity.y, 0.0) 
		if owner.is_on_floor() and bool(owner.input.get("slide_down", false)) and dir != 0:
			# если игрок всё ещё «жмёт слайд» и есть направление — вернёмся в спринт
			owner.change_state(SprintState.new(owner))
		else:
			# иначе — обычный выход: если есть направление, в бег; если нет — в idle
			if dir != 0:
				owner.change_state(RunState.new(owner))
			else:
				owner.change_state(IdleState.new(owner))
		return

	# 7) УРОН ПРЕРЫВАЕТ
	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return
