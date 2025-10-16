extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_JumpState

func enter() -> void:
	anim.play_jump()
	# предположим, что прыжок уже заказан извне (locomotion.perform_jump()),
	# тут просто ждём выхода на вершину
	# можно подстраховать лёгким импульсом:
	# locomotion.perform_jump(false)

func update(_dt: float) -> void:
	if body.velocity.y <= 0.0:
		owner._change_state(Cossack_01_FallState.new(owner))
