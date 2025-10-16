extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_IdleState

func enter() -> void:
	if locomotion and locomotion.has_method("stop"):
		locomotion.stop()
	elif body:
		body.velocity.x = 0.0
	if anim:
		anim.play_idle()

func update(_dt: float) -> void:
	# Выйти из Idle только если реально видим цель
	if perception and perception.has_target:
		owner._change_state(Cossack_01_ApproachState.new(owner))

func exit() -> void:
	pass
