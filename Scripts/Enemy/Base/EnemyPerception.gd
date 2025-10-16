extends Node
class_name EnemyPerception

signal seen_player(position: Vector3)
signal lost_player()
signal screen_entered_once()

@export var player_group: StringName = &"player"
@export var sight_range: float = 12.0            # радиус взятия цели (по X)
@export var near_range: float = 6.0
@export var los_use_raycast: bool = false
@export var los_collision_mask: int = 1 << 5
@export var lose_extra_range: float = 3.0        # гистерезис потери цели
@export var los_hold_time: float = 0.25          # удержание видимости при кратких перекрытиях

var _player: Node3D
var _owner_root: Node3D
var _on_screen: VisibleOnScreenNotifier3D

var has_been_on_screen: bool = false
var has_target: bool = false
var last_known_pos: Vector3 = Vector3.ZERO
var _los_timer: float = 0.0

func _ready() -> void:
	_owner_root = get_parent() as Node3D
	_on_screen = _owner_root.get_node_or_null("VisibleOnScreenNotifier3D")
	if _on_screen:
		_on_screen.screen_entered.connect(_on_screen_entered)
	_player = get_tree().get_first_node_in_group(player_group) as Node3D
	set_physics_process(true)

func _physics_process(dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(player_group) as Node3D
		return
	if _owner_root == null or not is_instance_valid(_owner_root):
		return

	# Дистанция ТОЛЬКО по X
	var dx: float = absf(_owner_root.global_position.x - _player.global_position.x)

	# Гистерезис: входим при sight_range, теряем при sight_range + lose_extra_range
	var acquire_r: float = sight_range
	var lose_r: float = maxf(sight_range, sight_range + lose_extra_range)

	# Линия видимости с удержанием
	var vis_now: bool = _visible_line_of_sight()
	if vis_now:
		_los_timer = los_hold_time
	else:
		_los_timer = max(0.0, _los_timer - dt)
	var visible_ok: bool = (_los_timer > 0.0)

	var in_range: bool = dx <= (lose_r if has_target else acquire_r)
	var new_target: bool = in_range and visible_ok

	if new_target and not has_target:
		has_target = true
		last_known_pos = _player.global_position
		seen_player.emit(last_known_pos)
	elif new_target and has_target:
		last_known_pos = _player.global_position
	elif (not new_target) and has_target:
		has_target = false
		lost_player.emit()

func _on_screen_entered() -> void:
	if not has_been_on_screen:
		has_been_on_screen = true
		screen_entered_once.emit()

func _visible_line_of_sight() -> bool:
	if not los_use_raycast:
		return true
	if _player == null or _owner_root == null:
		return false
	var space: PhysicsDirectSpaceState3D = _owner_root.get_world_3d().direct_space_state
	var from: Vector3 = _owner_root.global_position
	var to: Vector3 = _player.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = los_collision_mask
	var hit: Dictionary = space.intersect_ray(query)
	return hit.is_empty()

func get_player() -> Node3D:
	return _player

func get_distance_to_player() -> float:
	if _player == null or _owner_root == null:
		return INF
	return absf(_owner_root.global_position.x - _player.global_position.x)
