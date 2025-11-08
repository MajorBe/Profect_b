extends Node
class_name DropThrough

signal started
signal finished

@export_category("Platform Mask")
@export var platform_layer_mask: int = 1 << 3    # слой, на котором стоят one-way платформы
@export var duration: float = 0.30              # сколько времени игнорировать платформы
@export var min_down_vel: float = -0.2          # легонько толкнуть вниз
@export var zero_snap: bool = true              # на время проскока отключать floor_snap
@export var use_crouch_shape: bool = false      # если хочешь автопереключение на "низкую" форму

var active := false
var _timer := 0.0
var _snap_backup := 0.0
var _cached_mask := 0

@onready var body: CharacterBody3D = get_parent()
@onready var crouch_shape: CollisionShape3D = body.get_node_or_null("CrouchShape")
@onready var stand_shape: CollisionShape3D = body.get_node_or_null("StandShape")

func can_drop() -> bool:
	# На полу и под нами есть платформа нужного слоя
	if not body.is_on_floor():
		return false
	var from := body.global_transform.origin + Vector3(0.0, 0.05, 0.0)
	var to := from + Vector3(0.0, -0.30, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [body]
	q.collision_mask = platform_layer_mask
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.has("position")

func start_drop() -> void:
	if active or not can_drop():
		return
	active = true
	_timer = duration
	emit_signal("started")

	_cached_mask = body.collision_mask
	body.collision_mask = _cached_mask & ~platform_layer_mask

	if zero_snap:
		_snap_backup = body.floor_snap_length
		body.floor_snap_length = 0.0

	if use_crouch_shape and crouch_shape and stand_shape:
		stand_shape.disabled = true
		crouch_shape.disabled = false

	if body.velocity.y > min_down_vel:
		body.velocity.y = min_down_vel

func update(delta: float) -> void:
	if not active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_finish()

func cancel() -> void:
	if active:
		_finish()

func is_active() -> bool:
	return active

func _finish() -> void:
	active = false
	# вернуть маску и снап
	body.collision_mask = _cached_mask
	if zero_snap:
		body.floor_snap_length = _snap_backup
	# вернуть форму
	if use_crouch_shape and crouch_shape and stand_shape:
		crouch_shape.disabled = true
		stand_shape.disabled = false
	emit_signal("finished")
