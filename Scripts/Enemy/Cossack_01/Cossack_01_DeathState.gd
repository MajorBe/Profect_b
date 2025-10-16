extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_DeathState

# ========================= #   State # =========================
var t: float = 0.0
var death_len: float = 0.7

# ========================= #   Lifecycle # =========================
func _init(_owner: Node3D) -> void:
	super(_owner)

func enter() -> void:
	t = 0.0

	# Останавливаем движение/синхронизацию, чтобы никто не трогал скорость анимаций
	if locomotion and locomotion.has_method("stop"):
		locomotion.stop()

	# --- Анимация смерти ---
	if anim:
		var ap := anim.get_node_or_null(NodePath("AnimationPlayer")) as AnimationPlayer
		var death_id: StringName = &"Death"
		if anim.has_method("get_death_id"):
			death_id = anim.get_death_id()

		if ap != null:
			ap.speed_scale = 1.0
			# Godot 4: play(name, custom_blend, custom_speed, from_end=false)
			ap.play(death_id, 0.0, 1.0, false)
		elif anim.has_method("play_death"):
			anim.play_death()

		if anim.has_method("get_clip_len"):
			death_len = anim.get_clip_len(death_id, death_len)

	# --- Коллизии: отключаем ТОЛЬКО для игрока и врагов ---
	var kbody := owner.get_node_or_null("Body") as CharacterBody3D
	if kbody:
		# Берём текущие слои/маски
		var layer: int = kbody.collision_layer
		var mask: int = kbody.collision_mask

		# Пытаемся вытащить номера битов слоёв "враг" и "игрок"
		var enemy_bit: int = _get_layer_bit_safe(owner, ["enemy_body_layer_bit", "ENEMY_BODY_LAYER_BIT"])
		var player_bit: int = _get_layer_bit_safe(owner, ["player_body_layer_bit", "PLAYER_BODY_LAYER_BIT"])

		# Если у owner нет — пробуем из конфига
		if enemy_bit < 0 and config != null and config.has_method("get"):
			var eb = config.get("enemy_body_layer_bit")
			if typeof(eb) == TYPE_INT:
				enemy_bit = int(eb)
		if player_bit < 0 and config != null and config.has_method("get"):
			var pb = config.get("player_body_layer_bit")
			if typeof(pb) == TYPE_INT:
				player_bit = int(pb)

		# Чистим в маске только слои игрока и врага (коллизии с ними исчезнут)
		if player_bit >= 0:
			mask &= ~(1 << player_bit)
		if enemy_bit >= 0:
			mask &= ~(1 << enemy_bit)

		# Дополнительно убираем СВОЙ "enemy"-бит из слоя,
		# чтобы игрок/враги, у которых маска включает "enemy", тоже нас не цепляли
		if enemy_bit >= 0:
			layer &= ~(1 << enemy_bit)

		kbody.collision_layer = layer
		kbody.collision_mask  = mask
		# ВАЖНО: другие биты слоя/маски НЕ трогаем — чтобы тело продолжало
		# столкновения с полом/статикой/декором как раньше.

func update(dt: float) -> void:
	t += dt
	if t >= death_len:
		owner.queue_free() # удаляем узел после проигрыша клипа

func exit() -> void:
	# Обычно из смерти не выходим; хук на будущее
	pass

# ========================= #   Helpers # =========================
func _get_layer_bit_safe(node: Object, keys: Array) -> int:
	if node == null:
		return -1
	# Узлы в Godot всегда имеют get(), так что проверяем содержимое и тип
	for k in keys:
		var v = null
		if node.has_method("get"):
			v = node.get(k)
		if typeof(v) == TYPE_INT:
			return int(v)
	return -1
