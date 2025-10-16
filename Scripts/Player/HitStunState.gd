class_name HitStunState
extends State

func enter() -> void:
	owner._switch_to_stand()
	owner.is_damaged = false
	owner.hit_stun_timer = owner.hit_stun_duration
	spr.play("Hit")

	# --- НОВОЕ: фиксируем разворот на время хитстана ---
	var kx := owner.knockback_dir.x
	if kx != 0.0:
		# ВАРИАНТ А (рекомендую): лицом к атакующему
		var face_dir := -int(sign(kx))     # противоположно вектору нокбэка по X
		# ВАРИАНТ B (если хочешь смотреть по полёту): var face_dir := int(sign(kx))
		owner.update_facing(face_dir, true)  # force = true игнорирует lock_facing
	# блокируем поворот по вводу на время хитстана
	owner.lock_facing = true
	# -----------------------------------------------

func update(delta: float) -> void:
	# нокбэк по X (оставляю твоё поведение 1:1)
	owner.velocity.x = owner.knockback_dir.x * owner.knockback_strength

	# гравитация, если в воздухе
	if not owner.is_on_floor():
		owner.apply_gravity(delta)

	owner.hit_stun_timer = owner.cd(owner.hit_stun_timer, delta)
	if owner.hit_stun_timer <= 0.0:
		owner.lock_facing = false
		if owner.is_on_floor():
			owner.change_state(IdleState.new(owner))
		else:
			owner.change_state(FallState.new(owner))

# (опционально, но полезно на случай принудительных переходов из вне)
func exit() -> void:
	owner.lock_facing = false
