extends Node
class_name PlayerInput

var snapshot: Dictionary = {}

func update() -> void:
	# Собираем тот же набор ключей и семантику, что раньше были в Player.gd
	snapshot = {
		"move_x": int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left")),
		"jump_pressed": Input.is_action_just_pressed("ui_jump"),
		"jump_down": Input.is_action_pressed("ui_jump"),
		"attack_pressed": Input.is_action_just_pressed("ui_attack"),
		"slide_pressed": Input.is_action_just_pressed("ui_slide"),
		"crouch_pressed": Input.is_action_pressed("ui_crouch"),
		"slide_down": Input.is_action_pressed("ui_slide"),
		"heal_pressed": Input.is_action_just_pressed("ui_heal"),
	}
