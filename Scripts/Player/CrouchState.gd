class_name CrouchState
extends State

func enter() -> void:
	owner._switch_to_crouch()
	owner.velocity.x = 0.0
	spr.play("CrouchLoop")
	if owner.saber:
		owner.saber.set_collider_profile(&"crouch")

func exit() -> void:
	if owner.saber:
		owner.saber.set_collider_profile(&"stand")
	pass

func is_ground_state() -> bool:
	return true

func update(_delta: float) -> void:
	var inp: Dictionary = owner.input

	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return

	# движение — встаём и бежим
	if int(inp["move_x"]) != 0:
		owner._switch_to_stand()
		owner.facing_dir = int(inp["move_x"])
		owner.apply_flip()
		owner.change_state(RunState.new(owner))
		return

	# drop-through
	if bool(inp["crouch_pressed"]) and bool(inp["jump_pressed"]):
		owner.dropper.start_drop()
		return

	# АТАКА из приседа
	if bool(inp["attack_pressed"]):
		owner.change_state(CrouchAttackState.new(owner))
		return

	if bool(inp["heal_pressed"]):
		owner.change_state(HealState.new(owner))
		return

	# отпустили присед — встаём и в Idle
	if not bool(inp["crouch_pressed"]):
		owner._switch_to_stand()
		owner.change_state(IdleState.new(owner))
		return

	if not owner.is_on_floor():
		owner.change_state(FallState.new(owner))
		return
