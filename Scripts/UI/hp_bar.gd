extends Control

signal damaged(amount, from_pos)
signal health_changed(current, max)
signal died()

@export var max_health: int = 100
@export var current_health: int = 100

@export var back_delay: float = 0.25
@export var back_follow_speed: float = 6.0
@export var use_ease: bool = true
@export var debug_mode: bool = false

@onready var front: TextureRect = get_node("Front")
@onready var back: TextureRect = get_node("Back")

var _target_ratio: float = 1.0
var _back_ratio: float = 1.0

var _front_full_width: float = 0.0
var _back_full_width: float = 0.0

var _back_tween: Tween = null

const EPSILON: float = 0.001

func _ready():
	
	
	if not front or not back:
		push_error("HPBar: node 'Front' or 'Back' not found")
		return

	# Сохраняем ширину региона из AtlasTexture (ВАЖНО: region.size.x!)
	_front_full_width = front.texture.region.size.x
	_back_full_width = back.texture.region.size.x

	_target_ratio = clamp(float(current_health) / float(max_health), 0.0, 1.0)
	_back_ratio = _target_ratio

	_update_front(_target_ratio)
	_update_back(_back_ratio)


func set_health(cur: int, maxh: int):
	max_health = max(1, maxh)
	current_health = clamp(cur, 0, max_health)
	var new_target = clamp(float(current_health) / float(max_health), 0.0, 1.0)

	

	_target_ratio = new_target
	_update_front(_target_ratio)
	emit_signal("health_changed", current_health, max_health)
	if current_health == 0:
		emit_signal("died")

	if _back_ratio <= _target_ratio:
		_cancel_back_tween()
		_back_ratio = _target_ratio
		_update_back(_back_ratio)
	else:
		_start_back_follow()

func heal(amount: int):
	if amount <= 0:
		return
	set_health(current_health + amount, max_health)

func take_damage(amount: int, from_pos: Vector3):
	if amount <= 0:
		return
	emit_signal("damaged", amount, from_pos)
	set_health(current_health - amount, max_health)

func _start_back_follow():
	_cancel_back_tween()
	_back_tween = create_tween()
	_back_tween.tween_interval(back_delay)
	_back_tween.connect("finished", Callable(self, "_on_back_delay_complete"))
	_back_tween.play()

func _on_back_delay_complete(_tween = null):
	_cancel_back_tween()
	_back_tween = create_tween()
	var end_value = _target_ratio
	var duration = 1.0 / back_follow_speed if back_follow_speed > 0 else 0.1
	if use_ease:
		_back_tween.tween_callback(Callable(self, "_back_tween_update"))
		_back_tween.tween_property(self, "_back_ratio", end_value, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_back_tween.tween_callback(Callable(self, "_back_tween_update"))
		_back_tween.tween_property(self, "_back_ratio", end_value, duration)
	_back_tween.connect("finished", Callable(self, "_on_back_tween_finished"))
	_back_tween.play()

func _on_back_tween_finished():
	_back_ratio = _target_ratio
	_update_back(_back_ratio)
	_back_tween = null

func _cancel_back_tween():
	if _back_tween:
		_back_tween.kill()
		_back_tween = null

func _back_tween_update():
	_update_back(_back_ratio)

func _update_front(ratio: float):
	if not front:
		return
	var clamped = clamp(ratio, 0.0, 1.0)
	var atlas_tex := front.texture
	if atlas_tex is AtlasTexture:
		var region = atlas_tex.region
		region.size.x = _front_full_width * clamped
		atlas_tex.region = region
	front.visible = clamped > 0.0

func _update_back(ratio: float):
	if not back:
		return
	var clamped = clamp(ratio, 0.0, 1.0)
	var atlas_tex := back.texture
	if atlas_tex is AtlasTexture:
		var region = atlas_tex.region
		region.size.x = _back_full_width * clamped
		atlas_tex.region = region
	back.visible = clamped > 0.0
