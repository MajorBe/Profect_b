extends Node3D
class_name EnemyAnchor

@export var enemy_scene: PackedScene
@export var spawn_radius: float = 10.0          # СПАВН: по X (якорь↔игрок)
@export var forget_radius: float = 15.0         # ДЕСПАВН: по X (враг↔игрок)
@export var respawn_delay: float = 0.0
@export var align_to_floor: bool = false
@export var floor_mask: int = 1

@export var player_ref: Node3D
@export var require_offscreen_for_despawn: bool = true
@export var offscreen_grace: float = 0.35
@export var min_alive_time: float = 0.75
@export var debug_logs: bool = false

var _enemy: Node3D
var _player: Node3D
var _respawn_timer: float = 0.0
var _alive_time: float = 0.0
var _offscreen_timer: float = 0.0

func _ready() -> void:
	set_physics_process(true)
	_player = _resolve_player()
	if enemy_scene == null:
		push_warning("EnemyAnchor: enemy_scene не задан — враг не появится.")
	if spawn_radius >= forget_radius:
		push_warning("EnemyAnchor: spawn_radius >= forget_radius — увеличь forget_radius.")

func _physics_process(dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _resolve_player()
		if _player == null:
			return

	# СПАВН по X (якорь↔игрок)
	if _enemy == null:
		if _respawn_timer > 0.0:
			_respawn_timer = max(0.0, _respawn_timer - dt)
			return
		if enemy_scene == null:
			return
		var d_spawn_x: float = absf(global_position.x - _player.global_position.x)
		if d_spawn_x <= spawn_radius:
			_spawn_enemy()
		return

	# ЕСЛИ ВРАГ ЕСТЬ — таймеры и деспавн
	if not is_instance_valid(_enemy):
		_enemy = null
		return

	_alive_time += dt
	if require_offscreen_for_despawn:
		if _is_enemy_on_screen():
			_offscreen_timer = offscreen_grace
		else:
			_offscreen_timer = max(0.0, _offscreen_timer - dt)
	else:
		_offscreen_timer = 0.0

	var d_forget_x: float = absf(_enemy.global_position.x - _player.global_position.x)
	var offscreen_ok: bool = (not require_offscreen_for_despawn) or (_offscreen_timer <= 0.0)
	var alive_ok: bool = (_alive_time >= min_alive_time)

	if d_forget_x >= forget_radius and offscreen_ok and alive_ok:
		_dbg("DESPAWN: dX=%.2f (>= %.2f)" % [d_forget_x, forget_radius])
		_despawn_enemy(true)

func _spawn_enemy() -> void:
	var inst: Node3D = enemy_scene.instantiate() as Node3D
	_enemy = inst
	add_child(inst)
	inst.global_position = global_position

	if align_to_floor:
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var from: Vector3 = global_position + Vector3.UP * 2.0
		var to: Vector3 = global_position + Vector3.DOWN * 50.0
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = floor_mask
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty() and hit.has("position"):
			inst.global_position = hit["position"] as Vector3

	_alive_time = 0.0
	_offscreen_timer = offscreen_grace
	_dbg("SPAWN at x=%.2f (player x=%.2f)" % [inst.global_position.x, _player.global_position.x])

	# Подписки
	var hp: EnemyHealth = _enemy.get_node_or_null("Hp") as EnemyHealth
	if hp and hp.has_signal("died"):
		hp.died.connect(_on_enemy_died)

func _despawn_enemy(reset_timer: bool) -> void:
	if _enemy != null and is_instance_valid(_enemy):
		_dbg("QUEUE_FREE enemy at x=%.2f" % [_enemy.global_position.x])
		_enemy.queue_free()
	_enemy = null
	if reset_timer:
		_respawn_timer = max(0.0, respawn_delay)

func _on_enemy_died() -> void:
	_despawn_enemy(true)

# ---------- helpers ----------
func _resolve_player() -> Node3D:
	if player_ref != null and is_instance_valid(player_ref):
		return player_ref
	return get_tree().get_first_node_in_group(&"player") as Node3D

func _is_enemy_on_screen() -> bool:
	if _enemy == null or not is_instance_valid(_enemy):
		return false
	var stack: Array[Node] = []
	stack.push_back(_enemy as Node)
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		var vn: VisibleOnScreenNotifier3D = n as VisibleOnScreenNotifier3D
		if vn != null and vn.is_on_screen():
			return true
		var children: Array = n.get_children()
		for i in range(children.size()):
			var c: Node = children[i] as Node
			if c != null:
				stack.push_back(c)
	return true # нет нотайферов — считаем видимым

func _dbg(msg: String) -> void:
	if debug_logs:
		print("[EnemyAnchor] ", msg)
