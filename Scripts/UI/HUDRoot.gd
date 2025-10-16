extends CanvasLayer
@onready var hp_bar: Control = $HPBar

func set_health(cur: int, max_h: int) -> void:
	if hp_bar and hp_bar.has_method("set_health"):
		hp_bar.set_health(cur, max_h)
