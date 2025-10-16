extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_PatrolState

func enter() -> void:
	anim.play_walk()

func update(_dt: float) -> void:
	# мини-брожение, разворот у стен/обрывов внутри locomotion
	locomotion.walk_patrol()
	# если заметили игрока (или уже были на экране и игрок в зоне) — в подход
	if perception and (perception.has_target or perception.has_been_on_screen):
		owner._change_state(Cossack_01_ApproachState.new(owner))
