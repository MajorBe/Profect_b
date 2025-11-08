extends "res://Scripts/Enemy/Base/EnemyState.gd"
class_name Cossack_01_HitStunState

var t: float = 0.0
var _stun_time: float = 0.2
var _kb_time_left: float = 0.0

var _dmg: DamageEvent = null

func _init(_owner: Node3D) -> void:
	super(_owner)

func setup_hit(dmg: DamageEvent, applied: int) -> void:
	if applied <= 0:
		return
	_dmg = dmg
	t = 0.0
	_kb_time_left = 0.12  # длительность «живого» нокбэка
	_stun_time = 0.2
	if config != null:
		_stun_time = max(0.05, float(config.post_hit_cooldown))

func refresh(dmg: DamageEvent, applied: int) -> void:
	if applied <= 0:
		return
	_dmg = dmg
	t = 0.0
	_kb_time_left = max(_kb_time_left, 0.08)
	if config != null:
		_stun_time = max(0.05, float(config.post_hit_cooldown))

func enter() -> void:
	t = 0.0
	_kb_time_left = max(_kb_time_left, 0.0)

	if anim != null and anim.has_method("play_hurt"):
		anim.play_hurt()

	var L := owner.get_node_or_null("Locomotion")
	var _body := owner.get_node_or_null("Body") as CharacterBody3D
	if L != null and body != null and _dmg != null and L.has_method("apply_knockback_from"):
		# Направление считаем от позиции ТЕЛА (а не корня)!
		# И сразу используем уже готовый API локомоушена по «точке удара».
		L.apply_knockback_from(_dmg.origin, 0.6)  # 2.4 можно подрегулировать

func update(dt: float) -> void:
	t += dt

	if _kb_time_left > 0.0:
		_kb_time_left = max(0.0, _kb_time_left - dt)
	else:
		var L := owner.get_node_or_null("Locomotion")
		if L != null and L.has_method("stop_immediately"):
			L.stop_immediately()

	if t < _stun_time:
		return

	var H := owner.get_node_or_null("Health")
	if H != null and H.has_method("is_dead") and H.is_dead():
		owner._change_state(Cossack_01_DeathState.new(owner))
	else:
		owner._change_state(Cossack_01_IdleState.new(owner))

func on_death() -> void:
	owner._change_state(Cossack_01_DeathState.new(owner))
