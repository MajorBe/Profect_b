class_name CrouchAttackState
extends State

var _cmd_playing: bool = false

func enter() -> void:
	_cmd_playing = false

	if owner.has_method("_switch_to_crouch"):
		owner._switch_to_crouch()
	owner.velocity.x = 0.0

	if owner.saber:
		owner.saber.set_collider_profile(&"crouch")
		# сейчас: разово Attack1; позже: CrouchAttack, если появится
		owner.saber.start_attack_for(&"crouch")

	if spr:
		if spr.is_playing():
			spr.stop()
		spr.play(&"CrouchAttack")
		_cmd_playing = true

func exit() -> void:
	if owner.saber:
		owner.saber.set_collider_profile(&"stand")

func is_ground_state() -> bool:
	return true

func update(_delta: float) -> void:
	if not owner.is_on_floor():
		owner.change_state(FallState.new(owner))
		return

	if owner.has_method("_switch_to_crouch"):
		owner._switch_to_crouch()

	owner.velocity.x = 0.0

	if _cmd_playing and spr and not spr.is_playing():
		_cmd_playing = false

	# сразу в CrouchState — без кадра стойки
	if not _cmd_playing and (owner.saber == null or not owner.saber.is_attacking()):
		owner.change_state(CrouchState.new(owner))
