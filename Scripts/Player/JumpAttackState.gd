class_name JumpAttackState
extends State

var _cmd_playing: bool = false

func enter() -> void:
	_cmd_playing = false

	if owner.saber:
		owner.saber.set_collider_profile(&"air")
		# сейчас: разово Attack1; позже: AirAttack, если появится
		owner.saber.start_attack_for(&"jump")

	if spr:
		if spr.is_playing():
			spr.stop()
		spr.play(&"JumpAttack")
		_cmd_playing = true

func exit() -> void:
	if owner.saber:
		owner.saber.set_collider_profile(&"stand")

func is_ground_state() -> bool:
	return false

func update(delta: float) -> void:
	if owner.is_on_floor():
		owner.change_state(IdleState.new(owner))
		return

	# мягкая гравитация воздуха
	owner.apply_gravity(delta, owner.air_attack_gravity_scale)
	if owner.velocity.y < -owner.air_attack_fall_cap:
		owner.velocity.y = -owner.air_attack_fall_cap

	# движение вперёд — только пока идёт персонажная анимация
	if _cmd_playing and spr and spr.is_playing():
		owner.velocity.x = owner.attack_move_speed * float(owner.facing_dir)
	else:
		_cmd_playing = false
		if owner.saber == null or not owner.saber.is_attacking():
			owner.change_state(FallState.new(owner))
