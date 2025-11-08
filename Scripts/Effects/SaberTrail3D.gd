extends MeshInstance3D
class_name SwordTrail3D

@export_node_path("Node3D") var blade_edge_a_path     # верхняя кромка (маркер на клинке)
@export_node_path("Node3D") var blade_edge_b_path     # нижняя кромка (маркер на клинке)
@export var trail_lifetime_sec: float = 0.25          # сколько секунд хвост живёт
@export var min_segment_dist: float = 0.01            # минимальная дистанция для новой секции
@export var max_points: int = 96                      # ограничение количества записей
@export var auto_hide_when_still: bool = true         # скрывать ленту, если клинок не движется
@export var min_speed_for_trail: float = 0.4          # м/с — ниже не пишем точки
@export var fade_out_when_disabled_sec: float = 0.18  # дотухание после выключения

@export var material_unshaded: Material               # ShaderMaterial с градиентом/аддитивом

var _edge_a: Node3D
var _edge_b: Node3D
var _history: Array = []          # элементы: { "a": Vector3, "b": Vector3, "t": float }
var _enabled: bool = false
var _fade_until: float = 0.0

var _last_a: Vector3
var _last_b: Vector3
var _have_last: bool = false

func _ready() -> void:
	_edge_a = get_node_or_null(blade_edge_a_path)
	_edge_b = get_node_or_null(blade_edge_b_path)

	if not _edge_a or not _edge_b:
		push_warning("SwordTrail3D: назначь два маркера клинка (edge_a/edge_b).")
		set_process(false)
	else:
		set_process(true)

	if material_unshaded:
		material_override = material_unshaded

	hide()

func enable_trail() -> void:
	_enabled = true
	_fade_until = 0.0
	show()

func disable_trail() -> void:
	_enabled = false
	_fade_until = float(Time.get_ticks_msec()) / 1000.0 + fade_out_when_disabled_sec

func clear_trail() -> void:
	_history.clear()
	_have_last = false
	_rebuild_mesh()
	hide()

func _process(delta: float) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0

	# удалить старые записи
	while _history.size() > 0 and (now - (_history[0]["t"] as float)) > trail_lifetime_sec:
		_history.remove_at(0)

	# добавить новую запись, если нужно
	if _edge_a and _edge_b and (_enabled or now < _fade_until):
		var a: Vector3 = _edge_a.global_transform.origin
		var b: Vector3 = _edge_b.global_transform.origin

		var accept: bool = true
		if _have_last:
			var dist_a: float = a.distance_to(_last_a)
			var dist_b: float = b.distance_to(_last_b)
			var avg_dist: float = 0.5 * (dist_a + dist_b)
			var speed: float = avg_dist / maxf(delta, 1e-6)
			if auto_hide_when_still and speed < min_speed_for_trail:
				accept = false
			if avg_dist < min_segment_dist:
				accept = false

		if accept:
			_history.append({ "a": a, "b": b, "t": now })
			_last_a = a
			_last_b = b
			_have_last = true

		# ограничить размер истории
		if _history.size() > max_points:
			var overflow: int = _history.size() - max_points
			for i in range(overflow):
				_history.remove_at(0)

	# автоскрытие, когда всё выгорело
	if not _enabled and _history.size() == 0 and now >= _fade_until:
		hide()

	_rebuild_mesh()

func _rebuild_mesh() -> void:
	if _history.size() < 2:
		mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var n: int = _history.size()

	# ВАЖНО: переводим мировые точки в локальные координаты этого MeshInstance3D
	for i in range(n):
		var rec: Dictionary = _history[i]
		var a_world: Vector3 = rec["a"]
		var b_world: Vector3 = rec["b"]
		var t: float = rec["t"]

		var a_local: Vector3 = to_local(a_world)
		var b_local: Vector3 = to_local(b_world)

		var age: float = clampf((now - t) / maxf(trail_lifetime_sec, 1e-6), 0.0, 1.0)

		vertices.push_back(a_local)
		vertices.push_back(b_local)
		uvs.push_back(Vector2(0.0, age))
		uvs.push_back(Vector2(1.0, age))

	for i in range(n - 1):
		var i0: int = i * 2
		var i1: int = i * 2 + 1
		var i2: int = i * 2 + 2
		var i3: int = i * 2 + 3
		indices.push_back(i0); indices.push_back(i2); indices.push_back(i1)
		indices.push_back(i1); indices.push_back(i2); indices.push_back(i3)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = am
