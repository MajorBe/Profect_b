class_name HealState
extends State

func enter() -> void:
	owner.is_healing = true
	owner.heal_timer = owner.heal_duration
	owner.velocity = Vector3.ZERO
	owner.get_node("AnimatedSprite3D").play("Heal")

func exit() -> void:
	owner.is_healing = false

func is_ground_state() -> bool:
	return true

func update(delta: float) -> void:
	owner.velocity = Vector3.ZERO
	owner.heal_timer = owner.cd(owner.heal_timer, delta)

	if owner.heal_timer <= 0.0:
		if owner.heals_left > 0 and owner.health and owner.health.has_method("heal"):
			owner.heals_left -= 1
			owner.health.heal(owner.heal_amount)
		owner.change_state(IdleState.new(owner))
		return

	if owner.is_damaged:
		owner.change_state(HitStunState.new(owner))
		return
