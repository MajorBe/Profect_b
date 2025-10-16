class_name RollState
extends State

func enter() -> void:
	owner.set_roll_active(true)
	owner.roll_timer = owner.roll_duration
	owner.lock_facing = true
	owner._switch_to_crouch()
	owner.get_node("AnimatedSprite3D").play("Roll")
	# небольшой горизонтальный импульс вперёд на приземлении
	owner.velocity.x = owner.facing_dir * owner.speed * 1.1
	owner.velocity.y = 0.0
	if owner.saber:
		owner.saber.set_collider_profile(&"crouch")

func exit() -> void:
	owner.set_roll_active(false)
	if owner.saber:
		owner.saber.set_collider_profile(&"stand")
	owner.lock_facing = false
	owner._switch_to_stand()

func is_ground_state() -> bool:
	return true

func update(delta: float) -> void:
	owner.roll_timer = owner.cd(owner.roll_timer, delta)
	# катимся вперёд
	owner.velocity.x = owner.facing_dir * owner.speed * 1.1
	owner.velocity.y = 0.0

	# на всякий случай: если потеряли пол — падаем
	if not owner.is_on_floor():
		owner.change_state(FallState.new(owner))
		return

	if owner.roll_timer <= 0.0:
		owner.change_state(IdleState.new(owner))
		return

	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return
