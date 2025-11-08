extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_FallState

func enter() -> void:
	anim.play_fall()

func update(_dt: float) -> void:
	# ждём посадки
	if body.is_on_floor():
		# если рядом игрок — в подход, иначе — в патруль
		if perception and (perception.has_target or perception.has_been_on_screen):
			owner._change_state(Cossack_01_ApproachState.new(owner))
		else:
			owner._change_state(Cossack_01_PatrolState.new(owner))
