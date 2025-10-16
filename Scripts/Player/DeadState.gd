class_name DeadState
extends State

func enter() -> void:
	owner.velocity = Vector3.ZERO
	spr.play("Death")

func is_ground_state() -> bool:
	return true

func update(_delta: float) -> void:
	# Ждать респавна
	pass
