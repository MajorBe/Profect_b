extends Resource
class_name EnemyState

var owner: Node3D
var body: CharacterBody3D
var anim: EnemyAnimation
var locomotion: EnemyLocomotion
var perception: EnemyPerception
var config: EnemyConfig

func _init(_owner: Node3D) -> void:
	# Не привязываемся к EnemyCossack/конкретным реализациям
	owner = _owner as Node3D
	if owner == null:
		push_error("EnemyState: owner is null or not a Node3D")
		return

	# --- Аккуратный кэш зависимостей (устойчив к именам узлов) ---
	body = owner.get_node_or_null(NodePath("Body")) as CharacterBody3D

	# Anim может называться "Anim" или "Animation" — пробуем оба, затем поиск по типу
	anim = owner.get_node_or_null(NodePath("Anim")) as EnemyAnimation
	if anim == null:
		anim = owner.get_node_or_null(NodePath("Animation")) as EnemyAnimation
	if anim == null:
		# Фоллбэк: ищем первый дочерний узел типа EnemyAnimation
		for c in owner.get_children():
			if c is EnemyAnimation:
				anim = c as EnemyAnimation
				break

	# Остальные — по фиксированным именам (кеши, как в проекте)
	locomotion = owner.get_node_or_null(NodePath("Locomotion")) as EnemyLocomotion
	perception = owner.get_node_or_null(NodePath("Perception")) as EnemyPerception

	# --- Config: через метод, свойства ("config"/"Config"), затем дочерний узел "Config"; иначе дефолт ---
	if owner.has_method("get_config"):
		var v: Variant = owner.call("get_config")
		if v != null and v is EnemyConfig:
			config = v as EnemyConfig
	else:
		# пробуем свойства с разным регистром
		if owner.has_method("get"):
			var cand1: Variant = owner.get("config")
			if cand1 != null and cand1 is EnemyConfig:
				config = cand1 as EnemyConfig
			var cand2: Variant = owner.get("Config")
			if config == null and cand2 != null and cand2 is EnemyConfig:
				config = cand2 as EnemyConfig

	# если всё ещё null — ищем дочерний узел "Config"
	if config == null and owner is Node:
		var cfg_node: Node = (owner as Node).get_node_or_null(NodePath("Config"))
		if cfg_node != null and cfg_node is EnemyConfig:
			config = cfg_node as EnemyConfig

	# Фолбэк — создаём дефолт только если ничего не нашли
	if config == null:
		config = EnemyConfig.new()
		config.name = "Config"
		if owner is Node:
			owner.add_child(config)

# --- Хуки ЖЦ состояния (переопределяются в наследниках) ---
func enter() -> void:
	pass

func update(_dt: float) -> void:
	pass

func exit() -> void:
	pass

# --- Общие события ---
func on_damaged(_ev: Variant, applied: int) -> void:
	if applied > 0 and owner != null:
		# Даем право конкретной реализации решить, что за стейт включать (HitStun и т.п.)
		if owner.has_method("on_damaged"):
			owner.call("on_damaged", _ev, applied)
		elif owner.has_signal("damaged"):
			owner.emit_signal("damaged", _ev, applied)

func on_death() -> void:
	if owner != null:
		# Конкретная реализация сама инициирует переход в нужный DeathState
		if owner.has_method("on_dead"):
			owner.call("on_dead")
		elif owner.has_signal("died"):
			owner.emit_signal("died")

# --- Утилиты ---
func dist_to_player() -> float:
	if perception != null:
		return perception.get_distance_to_player()
	if owner == null:
		return INF
	var p: Node3D = null
	var tree := owner.get_tree()
	if tree:
		var list := tree.get_nodes_in_group(&"player")
		if list.size() > 0 and list[0] is Node3D:
			p = list[0] as Node3D
	if p == null:
		return INF
	return owner.global_position.distance_to(p.global_position)

# --- Геометрия: метрика «край-к-краю» по X (симметричная слева/справа) ---
func _first_half_width_under(root: Node) -> float:
	var q: Array[Node] = [root]
	while not q.is_empty():
		var n: Node = q.pop_front()
		if n is CollisionShape3D:
			var cs: CollisionShape3D = n
			if cs.shape != null:
				# ВАЖНО: ни одного промежуточного Variant; типы заданы в каждой ветке
				if cs.shape is BoxShape3D:
					var box: BoxShape3D = cs.shape
					return max(0.0, float(box.size.x) * 0.5) # Godot 4: size, не extents
				elif cs.shape is CapsuleShape3D:
					var cap: CapsuleShape3D = cs.shape
					return max(0.0, float(cap.radius))
				elif cs.shape is CylinderShape3D:
					var cyl: CylinderShape3D = cs.shape
					return max(0.0, float(cyl.radius))
				elif cs.shape is SphereShape3D:
					var sph: SphereShape3D = cs.shape
					return max(0.0, float(sph.radius))
		for c in n.get_children():
			var cn: Node = c
			if cn != null:
				q.append(cn)
	return 0.0

func _edge_dx_along_x(self_body: CharacterBody3D, other_node: Node3D) -> float:
	if self_body == null or other_node == null:
		return INF
	var ex: float = self_body.global_transform.origin.x
	var ox: float = other_node.global_transform.origin.x
	var half_self: float = _first_half_width_under(self_body)
	var half_oth: float = _first_half_width_under(other_node)
	var raw: float = absf(ox - ex) - half_self - half_oth
	return maxf(0.0, raw)

func can_attack_now() -> bool:
	
	# ===== вход и отладка путей скриптов =====
	var _self_script := ""
	var _owner_script := ""
	if get_script():
		_self_script = String(get_script().resource_path)
	if owner and owner.get_script():
		_owner_script = String(owner.get_script().resource_path)

	if owner == null or body == null or config == null:
		return false

	# --- цель: perception → группа "player"
	var p: Node3D = null
	if "perception" in owner and owner.perception and owner.perception.has_method("get_player"):
		p = owner.perception.get_player()
	if p == null:
		var tree := owner.get_tree()
		if tree:
			var list := tree.get_nodes_in_group(&"player")
			if list.size() > 0 and list[0] is Node3D:
				p = list[0] as Node3D
	if p == null:
		return false

	# --- геометрия: СТРОГО от тела
	var self_pos: Vector3 = body.global_transform.origin
	var ply_pos: Vector3 = p.global_transform.origin
	var to: Vector3 = ply_pos - self_pos

	# реальный up-вектор тела
	var up: Vector3 = Vector3.UP
	if body.has_method("get_up_direction"):
		up = body.get_up_direction()
	elif "up_direction" in body and body.up_direction != Vector3.ZERO:
		up = body.up_direction
	up = up.normalized()

	# высоты и плоскость
	var dy_proj: float = to.dot(up)
	var flat: Vector3 = to - up * dy_proj
	var dx: float = _edge_dx_along_x(body, p)	# «край-к-краю» по X
	var dz: float = absf(flat.z)				# глубина по Z (дорожка)

	# ====== ЭФФЕКТИВНЫЕ НАСТРОЙКИ (с источником) ======
	var use_over: bool = (owner != null and "use_distance_overrides" in owner and owner.use_distance_overrides)

	var _src_attack_x := "DEF"
	var _src_attack_z := "DEF"
	var _src_stop_x := "DEF"
	var _src_dead_x := "DEF"

	var x_win: float
	var z_win: float
	var stop_x: float
	var _dead_x: float

	# attack_x_window
	if use_over and "attack_x_window_override" in owner:
		x_win = float(owner.attack_x_window_override)
		_src_attack_x = "OVR"
	elif config != null and "attack_x_window" in config:
		x_win = float(config.attack_x_window)
		_src_attack_x = "CFG"
	else:
		x_win = 0.18
		_src_attack_x = "DEF"

	# attack_z_window
	if use_over and "attack_z_window_override" in owner:
		z_win = float(owner.attack_z_window_override)
		_src_attack_z = "OVR"
	elif config != null and "attack_z_window" in config:
		z_win = float(config.attack_z_window)
		_src_attack_z = "CFG"
	else:
		z_win = 0.30
		_src_attack_z = "DEF"

	# approach_stop_x
	if use_over and "approach_stop_x_override" in owner:
		stop_x = float(owner.approach_stop_x_override)
		_src_stop_x = "OVR"
	elif config != null and "approach_stop_x" in config:
		stop_x = float(config.approach_stop_x)
		_src_stop_x = "CFG"
	else:
		stop_x = 0.35
		_src_stop_x = "DEF"

	# approach_x_window (гистерезис)
	if use_over and "approach_x_window_override" in owner:
		_dead_x = float(owner.approach_x_window_override)
		_src_dead_x = "OVR"
	elif config != null and "approach_x_window" in config:
		_dead_x = float(config.approach_x_window)
		_src_dead_x = "CFG"
	else:
		_dead_x = 0.10
		_src_dead_x = "DEF"

	# ------ финальные проверки «можно ли атаковать» ------
	# логика по X: цельная «точка остановки» + окно добора для удара
	var reach_x: bool = (dx >= maxf(0.0, stop_x - 0.4)) and (dx <= stop_x + x_win)

	# состояние цели (на полу/в воздухе)
	var target_grounded: bool = true
	if "is_on_floor" in p:
		target_grounded = p.is_on_floor()
	var target_in_air: bool = not target_grounded
	if not target_in_air and "velocity" in p:
		target_in_air = absf(p.velocity.y) > 0.18

	# коридоры по высоте/глубине (Z — регулируемо)
	var y_up_max: float = (0.08 if not target_in_air else 0.00)
	var y_down_max: float = 0.40
	var aligned_y_proj: bool = (dy_proj <= y_up_max) and (dy_proj >= -y_down_max)
	var aligned_z: bool = (dz <= z_win)

	# «спереди» по фейсу
	var facing: int = 1
	if "anim" in owner and owner.anim and owner.anim.sprite:
		facing = (1 if owner.anim.sprite.flip_h else -1)
	elif "facing_dir" in owner:
		facing = int(owner.facing_dir)
	elif "scale" in owner:
		facing = 1 if owner.scale.x >= 0.0 else -1

	var FRONT_EPS: float = 0.04
	var dir_to: float = signf(ply_pos.x - self_pos.x)
	var is_in_front: bool = (dir_to == signf(float(facing))) or (dx < FRONT_EPS)

	# причины блокировки
	var grounded_self: bool = body.is_on_floor() or absf(body.velocity.y) < 0.12
	if not grounded_self:
		return false
	if not reach_x:
		return false
	if not aligned_z:
		return false
	if not aligned_y_proj:
		return false
	if not is_in_front:
		return false

	return true

func should_wait_bias() -> bool:
	if config == null:
		return false
	return randf() < config.wait_bias

# --- Distances getters with overrides (EnemyCossack > Config > Defaults) ---
func _cfg_attack_x_win() -> float:
	# Приоритет: оверрайд на владельце, потом конфиг, потом дефолт
	if owner != null and owner.has_variable("attack_x_window_override"):
		var v = owner.get("attack_x_window_override")
		if typeof(v) in [TYPE_FLOAT, TYPE_INT] and float(v) >= 0.0:
			return float(v)
	return (float(config.attack_x_window) if config != null else 0.18)

func _cfg_attack_z_win() -> float:
	if owner != null and owner.has_variable("attack_z_window_override"):
		var v = owner.get("attack_z_window_override")
		if typeof(v) in [TYPE_FLOAT, TYPE_INT] and float(v) >= 0.0:
			return float(v)
	return (float(config.attack_z_window) if config != null else 0.30)

func _cfg_approach_stop_x() -> float:
	if owner != null and owner.has_variable("approach_stop_x_override"):
		var v = owner.get("approach_stop_x_override")
		if typeof(v) in [TYPE_FLOAT, TYPE_INT] and float(v) >= 0.0:
			return float(v)
	return (float(config.approach_stop_x) if config != null else 0.35)

func _cfg_approach_x_window() -> float:
	if owner != null and owner.has_variable("approach_x_window_override"):
		var v = owner.get("approach_x_window_override")
		if typeof(v) in [TYPE_FLOAT, TYPE_INT] and float(v) >= 0.0:
			return float(v)
	return (float(config.approach_x_window) if config != null else 0.10)
