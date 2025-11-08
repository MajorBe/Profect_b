class_name State
extends Resource    # Можно extends RefCounted

var owner: Player
var spr: AnimatedSprite3D


func _init(_owner: Player) -> void:
	owner = _owner
	spr = owner.sprite


# Виртуальный метод: по умолчанию стейт НЕ "земляной".
func is_ground_state() -> bool:
	return false


func enter() -> void:
	# Вызывается при входе в состояние
	pass


func exit() -> void:
	# Вызывается при выходе из состояния
	pass


func update(_delta: float) -> void:
	# Обновление состояния (физика/логика)
	pass


func handle_input(_input: Dictionary) -> void:
	# Обработка инпута (если нужно)
	pass
