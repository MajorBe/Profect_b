extends Area3D
class_name EnemyHitbox

@export var base_damage: int = 8
@export var damage_type: StringName = &"melee"
@export var damage_tags: Array[StringName] = [&"enemy_melee"]

var _window_token: int = 0
var _hit_ids: PackedInt64Array = PackedInt64Array()
var _instigator: Node = null  # владелец удара (EnemyCossack)
var _attack_token_snapshot: int = -1

func _ready() -> void:
	monitoring = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func open_window_sec(start_sec: float, end_sec: float, instigator: Node) -> void:
	# без гонок: увеличим токен, чтобы предыдущие окна гарантированно закрылись
	_window_token += 1
	var my := _window_token
	_instigator = instigator
	_hit_ids = PackedInt64Array()

	# отложенный старт окна
	_start_window_delayed(start_sec, end_sec, my)

func cancel_window() -> void:
	_window_token += 1
	monitoring = false
	_instigator = null
	_hit_ids = PackedInt64Array()

func _start_window_delayed(start_sec: float, end_sec: float, my: int) -> void:
	await get_tree().create_timer(max(0.0, start_sec)).timeout
	if my != _window_token:
		return
	monitoring = true

	# моментальный опрос «кто уже внутри»
	_poll_overlaps_once()

	# авто-закрытие
	await get_tree().create_timer(max(0.0, end_sec - start_sec)).timeout
	if my != _window_token:
		return
	monitoring = false

func _poll_overlaps_once() -> void:
	var bodies: Array[Node3D] = get_overlapping_bodies()
	for b in bodies:
		_on_body_entered(b)

	var areas: Array[Area3D] = get_overlapping_areas()
	for a in areas:
		_on_area_entered(a)

func _on_body_entered(body: Node) -> void:
	if not monitoring or body == null:
		return
	_try_apply_to_target(body)

func _on_area_entered(area: Area3D) -> void:
	if not monitoring or area == null:
		return
	_try_apply_to_target(area)

func _try_apply_to_target(target: Node) -> void:
	var sink := _resolve_health_receiver(target)
	if sink == null:
		return

	# Явный анти-friendly-fire: врага не бьём, игрока — да
	if not ("team" in sink):
		return
	if StringName(sink.team) != &"player":
		return

	var dedup_node: Node = sink
	var iid := dedup_node.get_instance_id()
	if _hit_ids.has(iid):
		return
	_hit_ids.append(iid)

	var origin := global_transform.origin
	var tgt_pos := (target as Node3D).global_transform.origin if target is Node3D else origin
	var dir: Vector3 = (tgt_pos - origin)

	var actor := _find_actor()
	var cur_tok := (int(actor.get_meta("attack_token")) 
		if actor != null and actor.has_meta("attack_token") else -2)
	if _attack_token_snapshot != cur_tok:
		return  # атака прервана/сменён стейт — урон запрещён

	_apply_damage_debug(sink, _resolve_instigator(), origin, dir, base_damage, _window_token)

func _apply_damage_debug(sink: Node, instigator: Node, origin: Vector3, dir: Vector3, amount: int, hit_id: int) -> void:
	var dmg := DamageEvent.new()
	dmg.amount = amount
	dmg.type = damage_type
	dmg.tags = damage_tags
	dmg.source = self
	dmg.instigator = instigator
	dmg.origin = origin
	dmg.direction = dir.normalized()
	dmg.impulse = 6.0
	dmg.hit_id = hit_id

	# Поддержка Health/HpBase одинаково, как в Saber.gd
	if sink != null and String(sink.name) == "HpBase":
		var p := sink.get_parent()
		if p != null and (String(p.name) == "Health" or p.has_method("apply_damage")):
			sink = p

	if sink != null and sink.has_method("apply_damage"):
		sink.apply_damage(dmg)

func _resolve_health_receiver(target: Node) -> Node:
	if target == null:
		return null
	var cur := target
	var depth := 0
	while cur != null and depth < 6:
		if cur.has_node("Health"):
			return cur.get_node("Health")
		if String(cur.name) == "HpBase":
			var p := cur.get_parent()
			if p != null and (String(p.name) == "Health" or p.has_method("apply_damage")):
				return p
		cur = cur.get_parent()
		depth += 1
	return null

func _resolve_instigator() -> Node:
	# Ищем ближайшего предка с Health (обычно сам EnemyCossack)
	var p: Node = self
	var step := 0
	while p != null and step < 6:
		if p.has_node("Health"):
			return p
		p = p.get_parent()
		step += 1
	# фолбэк: два уровня вверх
	return get_parent()

func _find_actor() -> Node:
	var p: Node = self
	var depth := 0
	while p != null and depth < 8:
		if p.has_node("Anim"):  # корень врага
			return p
		p = p.get_parent()
		depth += 1
	return null

func begin_window() -> void:
	_window_token += 1
	_hit_ids = PackedInt64Array()

	var actor := _find_actor()
	_attack_token_snapshot = (int(actor.get_meta("attack_token")) 
		if actor != null and actor.has_meta("attack_token") else -1)

	monitoring = true
	_poll_overlaps_once()

func end_window() -> void:
	_window_token += 1
	monitoring = false
