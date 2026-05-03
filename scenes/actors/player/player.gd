# res://.../player.gd

extends CharacterBody3D
class_name Player

const MOVE_DURATION: float = 0.35
const ROTATE_DURATION: float = 0.3
const HEAD_BOB_FREQ: float = 8.0
const HEAD_BOB_AMP: float = 0.08
const TILT_AMOUNT: float = 2.5
const STANCE_TRANSITION_DURATION: float = 0.22
const DEFENSE_TRANSITION_SPEED: float = 28.0
const STANCE_ROTATE_SPEED: float = 12.0
const STANCE_ARC_HEIGHT: float = 0.28
const BOTTOM_CROSS_TRANSITION_DURATION: float = 0.45
const BOTTOM_CROSS_ARC_HEIGHT: float = 0.85
const PERFECT_BLOCK_WINDOW: float = 0.22
const CRITICAL_ATTACK_WINDOW: float = 1.2
const NORMAL_ATTACK_DAMAGE: int = 20
const CRITICAL_ATTACK_DAMAGE: int = 60
const DEFENSE_READY_DISTANCE: float = 0.04
const DEFENSE_READY_ROT_DOT: float = 0.995

const SWORD_SCENE = preload("res://scenes/actors/items/simple_sword.tscn")
const STANCES = {
	0: {"pos": Vector3(0.5, -0.3, -1), "rot": Vector3(0, -90, 90)},    # CENTER (Meio)
	1: {"pos": Vector3(0, 0.7, -1), "rot": Vector3(0, -90, 0)},     # TOP (Cima)
	2: {"pos": Vector3(1, 0.5, -1), "rot": Vector3(-45, -90, 0)},   # TOP_RIGHT (Cima-Direita)
	3: {"pos": Vector3(0.6, -0.5, -1), "rot": Vector3(-135, -90, 0)}, # BOTTOM_RIGHT (Baixo-Direita)
	4: {"pos": Vector3(-0.6, -0.5, -1), "rot": Vector3(135, -90,  0)},  # BOTTOM_LEFT (Baixo-Esquerda)
	5: {"pos": Vector3(-1, 0.5, -1), "rot": Vector3(45, -90, 0)}     # TOP_LEFT (Cima-Esquerda)
}
const DEFENSE_STANCE = {"pos": Vector3(0.5, 0.3, -0.8), "rot": Vector3(180, 0, 45)}

@onready var health_component: HealthComponent = $HealthComponent
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var weapon_pivot: Node3D = $CameraPivot/Camera3D/WeaponPivot
@onready var combat_ui: CombatUI = $CombatUI/Control
@onready var forward_ray: RayCast3D = $ForwardRay
@onready var back_ray: RayCast3D = $BackRay
@onready var left_ray: RayCast3D = $LeftRay
@onready var right_ray: RayCast3D = $RightRay
@onready var melee_ray: RayCast3D = $CameraPivot/Camera3D/MeleeRay
@onready var weapon_attack_animator: WeaponAttackAnimator = $WeaponAttackAnimator

var player_name: String = "Mendel"
var is_moving: bool = false
var is_rotating: bool = false
var bob_time: float = 0.0
var base_camera_y: float = 0.0

var current_weapon: Node3D = null
var current_stance_index: int = 0
var target_stance_pos: Vector3 = STANCES[0]["pos"]
var target_stance_rot: Vector3 = STANCES[0]["rot"]
var is_attacking: bool = false
var is_defending: bool = false
var block_started_msec: int = -100000
var block_ready_msec: int = -100000
var defense_pose_ready: bool = false
var critical_attack_until_msec: int = -100000
var active_attack_is_critical: bool = false
var can_attack: bool = true
var stance_transitioning: bool = false
var stance_from_index: int = 0
var stance_to_index: int = 0
var stance_origin_pos: Vector3 = Vector3.ZERO
var stance_origin_quat: Quaternion = Quaternion.IDENTITY
var stance_actual_start_pos: Vector3 = Vector3.ZERO
var stance_actual_start_quat: Quaternion = Quaternion.IDENTITY
var stance_transition_elapsed: float = 0.0

const ATTACK_RECOVERY_DELAY: float = 0.0

var attack_recovering: bool = false
var attack_recovery_timer: float = 0.0

func _ready() -> void:
	print("Character created: " + player_name)
	base_camera_y = camera.position.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	health_component.entity_died.connect(_on_died)
	health_component.healing.connect(_on_health_changed)
	health_component.damage_taken.connect(_on_take_damage)

	combat_ui.direction_changed.connect(_on_combat_direction_changed)

	instantiate_weapon(SWORD_SCENE)
	melee_ray.add_exception(self)

func _process(delta: float) -> void:
	handle_head_bob(delta)
	handle_movement_input()
	handle_combat_input()
	_update_attack_recovery(delta)
	update_weapon_stance(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		combat_ui.handle_mouse_movement(event.relative)

	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()

func handle_combat_input() -> void:
	if Input.is_action_just_pressed("Item Passive"):
		block_started_msec = Time.get_ticks_msec()
		block_ready_msec = -100000
		defense_pose_ready = false

	is_defending = Input.is_action_pressed("Item Passive")
	if not is_defending:
		defense_pose_ready = false

	if Input.is_action_just_pressed("Item Action") and can_attack and not is_defending:
		perform_attack()

func is_blocking() -> bool:
	return is_defending

func is_perfect_blocking() -> bool:
	if not is_defending or not defense_pose_ready:
		return false

	var elapsed := float(Time.get_ticks_msec() - block_ready_msec) / 1000.0
	return elapsed <= PERFECT_BLOCK_WINDOW

func open_critical_attack_window() -> void:
	critical_attack_until_msec = Time.get_ticks_msec() + int(CRITICAL_ATTACK_WINDOW * 1000.0)

func _has_critical_attack_window() -> bool:
	return Time.get_ticks_msec() <= critical_attack_until_msec

func _consume_critical_attack_window() -> bool:
	if not _has_critical_attack_window():
		return false

	critical_attack_until_msec = -100000
	return true

func play_block_impact_feedback() -> void:
	var original_pos := weapon_pivot.position
	var original_quat := weapon_pivot.quaternion
	var recoil_pos := original_pos + Vector3(0.04, 0.05, 0.24)
	var recoil_quat := original_quat * _local_quat(Vector3(-12.0, 4.0, 9.0))
	var rattle_pos_a := original_pos + Vector3(-0.03, 0.03, 0.14)
	var rattle_quat_a := original_quat * _local_quat(Vector3(-6.0, -3.0, -7.0))
	var rattle_pos_b := original_pos + Vector3(0.02, 0.01, 0.10)
	var rattle_quat_b := original_quat * _local_quat(Vector3(4.0, 2.0, 5.0))

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(weapon_pivot, "position", recoil_pos, 0.055)
	tween.parallel().tween_property(weapon_pivot, "quaternion", recoil_quat, 0.055)
	tween.tween_property(weapon_pivot, "position", rattle_pos_a, 0.045)
	tween.parallel().tween_property(weapon_pivot, "quaternion", rattle_quat_a, 0.045)
	tween.tween_property(weapon_pivot, "position", rattle_pos_b, 0.04)
	tween.parallel().tween_property(weapon_pivot, "quaternion", rattle_quat_b, 0.04)
	tween.tween_property(weapon_pivot, "position", original_pos, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func play_perfect_block_impact_feedback() -> void:
	var original_pos := weapon_pivot.position
	var original_quat := weapon_pivot.quaternion
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(weapon_pivot, "position", original_pos + Vector3(0.03, 0.01, 0.08), 0.025)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat * _local_quat(Vector3(-4.0, 0.0, 8.0)), 0.025)
	tween.tween_property(weapon_pivot, "position", original_pos + Vector3(-0.03, -0.01, 0.06), 0.025)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat * _local_quat(Vector3(4.0, 0.0, -8.0)), 0.025)
	tween.tween_property(weapon_pivot, "position", original_pos + Vector3(0.02, 0.02, 0.04), 0.025)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat * _local_quat(Vector3(-2.0, 0.0, 5.0)), 0.025)
	tween.tween_property(weapon_pivot, "position", original_pos, 0.06)
	tween.parallel().tween_property(weapon_pivot, "quaternion", original_quat, 0.06)

func _update_attack_recovery(delta: float) -> void:
	if not attack_recovering:
		return

	attack_recovery_timer -= delta
	if attack_recovery_timer <= 0.0:
		attack_recovering = false

func update_weapon_stance(delta: float) -> void:
	if is_attacking or attack_recovering:
		return

	var base_target_pos := target_stance_pos
	var base_target_quat := _degrees_to_quat(target_stance_rot)

	if is_defending:
		base_target_pos = DEFENSE_STANCE["pos"]
		base_target_quat = _degrees_to_quat(DEFENSE_STANCE["rot"])
		if stance_transitioning:
			stance_transitioning = false

	if stance_transitioning:
		var is_arc := _is_bottom_cross_transition(stance_from_index, stance_to_index) and not is_defending
		var duration := BOTTOM_CROSS_TRANSITION_DURATION if is_arc else STANCE_TRANSITION_DURATION
		stance_transition_elapsed += delta
		var progress := clampf(stance_transition_elapsed / duration, 0.0, 1.0)
		var eased_progress := _smooth_step(progress)

		if is_arc:
			var fixed_origin: Vector3 = STANCES[stance_from_index]["pos"]
			var fixed_target: Vector3 = STANCES[stance_to_index]["pos"]
			var control: Vector3 = (fixed_origin + fixed_target) * 0.5 + Vector3(0.0, BOTTOM_CROSS_ARC_HEIGHT, 0.0)

			weapon_pivot.position = _quadratic_bezier(stance_actual_start_pos, control, base_target_pos, eased_progress)

			var mid_quat := _degrees_to_quat(STANCES[1]["rot"])
			if eased_progress < 0.5:
				weapon_pivot.quaternion = _slerp_short(stance_actual_start_quat, mid_quat, eased_progress * 2.0)
			else:
				weapon_pivot.quaternion = _slerp_short(mid_quat, base_target_quat, (eased_progress - 0.5) * 2.0)
		else:
			weapon_pivot.position = stance_actual_start_pos.lerp(base_target_pos, eased_progress)
			weapon_pivot.quaternion = _slerp_short(stance_actual_start_quat, base_target_quat, eased_progress)

		if progress >= 1.0:
			stance_transitioning = false
	else:
		var rotate_speed := DEFENSE_TRANSITION_SPEED if is_defending else STANCE_ROTATE_SPEED
		weapon_pivot.position = weapon_pivot.position.lerp(base_target_pos, clampf(delta * rotate_speed, 0.0, 1.0))
		weapon_pivot.quaternion = _slerp_short(
			weapon_pivot.quaternion,
			base_target_quat,
			clampf(delta * rotate_speed, 0.0, 1.0)
		)
		if is_defending and not defense_pose_ready:
			var position_ready := weapon_pivot.position.distance_to(base_target_pos) <= DEFENSE_READY_DISTANCE
			var rotation_ready := absf(weapon_pivot.quaternion.dot(base_target_quat)) >= DEFENSE_READY_ROT_DOT
			if position_ready and rotation_ready:
				defense_pose_ready = true
				block_ready_msec = Time.get_ticks_msec()

func perform_attack() -> void:
	if is_attacking or not can_attack:
		return
		
	is_attacking = true
	can_attack = false
	active_attack_is_critical = _consume_critical_attack_window()
	combat_ui.is_locked = true
	melee_ray.enabled = true
	
	var attack_from_stance := current_stance_index
	var next_stance := _get_next_stance_after_attack(attack_from_stance)
	combat_ui.set_direction(next_stance)

	var original_pos: Vector3 = STANCES[attack_from_stance]["pos"]
	var original_quat: Quaternion = _degrees_to_quat(STANCES[attack_from_stance]["rot"])
	var final_pos: Vector3 = STANCES[next_stance]["pos"]
	var final_quat: Quaternion = _degrees_to_quat(STANCES[next_stance]["rot"])

	weapon_pivot.position = original_pos
	weapon_pivot.quaternion = original_quat

	var pose := _build_attack_pose(attack_from_stance, original_pos, original_quat)
	var windup_pos: Vector3 = pose["windup_pos"]
	var windup_quat: Quaternion = pose["windup_quat"]
	var attack_pos: Vector3 = pose["attack_pos"]
	var attack_quat: Quaternion = pose["attack_quat"]

	var camera_kick_dir := Vector3.ZERO
	match attack_from_stance:
		1:
			camera_kick_dir = Vector3(1.2, 0.2, 0.0)
		2:
			camera_kick_dir = Vector3(0.0, 1.0, -0.5)
		3:
			camera_kick_dir = Vector3(0.0, 1.0, -0.5)
		4:
			camera_kick_dir = Vector3(0.0, -1.0, 0.5)
		5:
			camera_kick_dir = Vector3(0.0, -1.0, 0.5)
		0:
			camera_kick_dir = Vector3(0.8, 0.0, 0.0)

	var is_thrust := attack_from_stance == 0
	var max_allowed_pullback_z := original_pos.z + 0.08
	var min_required_lunge_z := original_pos.z - (2.5 if is_thrust else 0.35)
	windup_pos.z = min(windup_pos.z, max_allowed_pullback_z)
	attack_pos.z = min(attack_pos.z, min_required_lunge_z)
	if active_attack_is_critical:
		attack_pos.z -= 0.45
		camera_kick_dir *= 1.6

	weapon_attack_animator.play_attack(
		original_pos,
		original_quat,
		windup_pos,
		windup_quat,
		attack_pos,
		attack_quat,
		final_pos,
		final_quat,
		next_stance,
		camera_kick_dir,
		Callable(self, "_on_attack_impact_event"),
		Callable(self, "_on_attack_animation_finished_event")
	)

func _build_attack_pose(from_stance: int, original_pos: Vector3, original_quat: Quaternion) -> Dictionary:
	match from_stance:
		0: # CENTER
			return {
				"windup_pos": original_pos + Vector3(0.0, 0.0, 0.0),
				"windup_quat": original_quat * _local_quat(Vector3(8.0, 0.0, 0.0)),
				"attack_pos": original_pos + Vector3(0.0, 0.0, 0.0),
				"attack_quat": original_quat
			}
		1: # TOP
			return {
				"windup_pos": original_pos + Vector3(0.0, 0.16, -1.20),
				"windup_quat": original_quat * _local_quat(Vector3(0, 0.0, -5.0)),
				"attack_pos": original_pos + Vector3(0.0, -2.10, -0.95),
				"attack_quat": original_quat * _local_quat(Vector3(0, 0.0, 150.0))
			}
		2: # TOP_RIGHT
			return {
				"windup_pos": original_pos + Vector3(0.14, 0.10, 0.18),
				"windup_quat": original_quat * _local_quat(Vector3(-10.0, 0.0, -15.0)),
				"attack_pos": original_pos + Vector3(-2.30, -2.0, -0.95),
				"attack_quat": original_quat * _local_quat(Vector3(12.0, 0.0, 150.0))
			}
		3: # BOTTOM_RIGHT
			return {
				"windup_pos": original_pos + Vector3(0.12, -0.06, 0.14),
				"windup_quat": original_quat * _local_quat(Vector3(-12.0, 0.0, -15.0)),
				"attack_pos": original_pos + Vector3(-2.30, 0.76, -0.76),
				"attack_quat": original_quat * _local_quat(Vector3(18.0, 0.0, 150.0))
			}
		4: # BOTTOM_LEFT
			return {
				"windup_pos": original_pos + Vector3(-0.12, -0.06, 0.14),
				"windup_quat": original_quat * _local_quat(Vector3(5.0, 0.0, -15.0)),
				"attack_pos": original_pos + Vector3(2.0, 1.5, -0.76),
				"attack_quat": original_quat * _local_quat(Vector3(-18.0, 0.0, 150.0))
			}
		5: # TOP_LEFT
			return {
				"windup_pos": original_pos + Vector3(-0.14, 0.10, 0.18),
				"windup_quat": original_quat * _local_quat(Vector3(12.0, 0.0, -15.0)),
				"attack_pos": original_pos + Vector3(2.30, -2.0, -0.95),
				"attack_quat": original_quat * _local_quat(Vector3(18.0, 0.0, 150.0))
			}
		_:
			return {
				"windup_pos": original_pos + Vector3(0.0, 0.05, 0.15),
				"windup_quat": original_quat,
				"attack_pos": original_pos + Vector3(0.0, 0.0, -0.75),
				"attack_quat": original_quat
			}

func _local_quat(rot_degrees: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(
		deg_to_rad(rot_degrees.x),
		deg_to_rad(rot_degrees.y),
		deg_to_rad(rot_degrees.z)
	))

func _apply_camera_feedback(dir: Vector3) -> void:
	var kick_strength = 2.0
	var original_rot = camera.rotation_degrees
	var target_rot = original_rot + dir * kick_strength

	var tween = create_tween()
	tween.tween_property(camera, "rotation_degrees", target_rot, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "rotation_degrees", original_rot, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _degrees_to_quat(rot_degrees: Vector3) -> Quaternion:
	var rot_radians := Vector3(
		deg_to_rad(rot_degrees.x),
		deg_to_rad(rot_degrees.y),
		deg_to_rad(rot_degrees.z)
	)
	return Quaternion.from_euler(rot_radians)

func _on_attack_impact_event(camera_kick_dir: Vector3) -> void:
	_apply_camera_feedback(camera_kick_dir)
	if active_attack_is_critical:
		_play_critical_attack_feedback()
	_check_hit()

func _on_attack_animation_finished_event(next_stance: int, final_pos: Vector3, final_rot: Vector3) -> void:
	is_attacking = false
	attack_recovering = false
	attack_recovery_timer = 0.0
	can_attack = true
	combat_ui.is_locked = false
	melee_ray.enabled = false
	active_attack_is_critical = false
	current_stance_index = next_stance
	target_stance_pos = final_pos
	target_stance_rot = final_rot
	stance_transitioning = false

func _get_next_stance_after_attack(current: int) -> int:
	match current:
		1:
			return 3 if randf() > 0.5 else 4
		2:
			return 4
		3:
			return 5
		4:
			return 2
		5:
			return 3
		_:
			return current

func _check_hit() -> void:
	melee_ray.force_raycast_update()
	if melee_ray.is_colliding():
		var target = melee_ray.get_collider()
		print("Hit something: ", target.name)

		var health = target.get_node_or_null("HealthComponent")
		if not health and target.get_parent():
			health = target.get_parent().get_node_or_null("HealthComponent")

		if health:
			print("Dealing damage to ", target.name)
			var hit_owner = health.get_parent()
			if active_attack_is_critical and hit_owner and hit_owner.has_method("on_critical_hit_by_player"):
				hit_owner.on_critical_hit_by_player(self)
			elif hit_owner and hit_owner.has_method("on_hit_by_player"):
				hit_owner.on_hit_by_player(self)
			health.take_damage(CRITICAL_ATTACK_DAMAGE if active_attack_is_critical else NORMAL_ATTACK_DAMAGE)

func instantiate_weapon(weapon_scene: PackedScene) -> void:
	if current_weapon:
		current_weapon.queue_free()

	current_weapon = weapon_scene.instantiate()
	weapon_pivot.add_child(current_weapon)
	_on_combat_direction_changed(0)

func _on_combat_direction_changed(dir_index: int) -> void:
	if is_attacking or combat_ui.is_locked:
		return

	stance_from_index = current_stance_index
	stance_to_index = dir_index

	stance_actual_start_pos = weapon_pivot.position
	stance_actual_start_quat = weapon_pivot.quaternion

	stance_transitioning = true
	stance_transition_elapsed = 0.0

	current_stance_index = dir_index
	target_stance_pos = STANCES[dir_index]["pos"]
	target_stance_rot = STANCES[dir_index]["rot"]

func _smooth_step(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return (u * u * p0) + (2.0 * u * t * p1) + (t * t * p2)

func _slerp_short(from: Quaternion, to: Quaternion, weight: float) -> Quaternion:
	if from.dot(to) < 0.0:
		to = -to
	return from.slerp(to, weight)

func _is_bottom_cross_transition(from_index: int, to_index: int) -> bool:
	return (
		(from_index == 4 and to_index == 3) or
		(from_index == 3 and to_index == 4)
	)

func handle_movement_input() -> void:
	if is_moving or is_rotating:
		return

	if Input.is_action_pressed("Foward"):
		move_in_direction(-transform.basis.z, forward_ray)
	elif Input.is_action_pressed("Back"):
		move_in_direction(transform.basis.z, back_ray)
	elif Input.is_action_pressed("Left strafe"):
		move_in_direction(-transform.basis.x, left_ray, true, -1)
	elif Input.is_action_pressed("Right strafe"):
		move_in_direction(transform.basis.x, right_ray, true, 1)
	elif Input.is_action_pressed("Turn Left"):
		turn(90)
	elif Input.is_action_pressed("Turn Right"):
		turn(-90)

func move_in_direction(direction: Vector3, ray: RayCast3D, is_strafe: bool = false, strafe_dir: int = 0) -> void:
	var target_pos = global_position + direction.normalized() * Constants.TILE_SIZE

	if ray.is_colliding() || _has_enemy_on_tile(target_pos):
		play_wall_bump_animation(direction)
		return

	is_moving = true

	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(self, "global_position", target_pos, MOVE_DURATION)

	if is_strafe:
		var target_tilt = deg_to_rad(-strafe_dir * TILT_AMOUNT)
		tween.tween_property(camera, "rotation:z", target_tilt, MOVE_DURATION * 0.5)
		tween.chain().tween_property(camera, "rotation:z", 0.0, MOVE_DURATION * 0.5)

	tween.chain().tween_callback(func(): is_moving = false)

func _has_enemy_on_tile(target_pos: Vector3) -> bool:
	var target_cell := _world_to_cell(target_pos)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("get_current_cell") and enemy.get_current_cell() == target_cell:
			return true

	return false

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / Constants.TILE_SIZE),
		floori(world_pos.z / Constants.TILE_SIZE)
	)

func turn(angle_degrees: float) -> void:
	is_rotating = true
	var target_rot = rotation.y + deg_to_rad(angle_degrees)

	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(self, "rotation:y", target_rot, ROTATE_DURATION)

	var tilt_dir = 1 if angle_degrees > 0 else -1
	var target_tilt = deg_to_rad(tilt_dir * TILT_AMOUNT)
	tween.tween_property(camera, "rotation:z", target_tilt, ROTATE_DURATION * 0.5)
	tween.chain().tween_property(camera, "rotation:z", 0.0, ROTATE_DURATION * 0.5)

	tween.chain().tween_callback(func(): is_rotating = false)

func play_wall_bump_animation(direction: Vector3) -> void:
	is_moving = true
	var original_pos = global_position
	var bump_pos = original_pos + direction.normalized() * (Constants.TILE_SIZE * 0.1)

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", bump_pos, 0.1)
	tween.tween_property(self, "global_position", original_pos, 0.1)
	tween.tween_callback(func(): is_moving = false)

func handle_head_bob(delta: float) -> void:
	if is_moving:
		bob_time += delta * HEAD_BOB_FREQ
	else:
		bob_time = lerp(bob_time, 0.0, delta * 10.0)

	var target_y = base_camera_y + sin(bob_time) * HEAD_BOB_AMP
	camera.position.y = lerp(camera.position.y, target_y, delta * 20.0)

	var target_x = cos(bob_time * 0.5) * (HEAD_BOB_AMP * 0.5)
	camera.position.x = lerp(camera.position.x, target_x, delta * 20.0)

func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_died() -> void:
	print(player_name + " died!")
	#queue_free()

func _on_health_changed() -> void:
	print("Cura recebida! HP: ", health_component.current_health)

func _on_take_damage() -> void:
	print("Dano recebido! HP: ", health_component.current_health)
	_play_damage_camera_shake()

func _play_damage_camera_shake() -> void:
	var original_rot := camera.rotation_degrees
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(-2.0, 1.4, -1.2), 0.035)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(1.5, -1.0, 1.0), 0.04)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(-0.8, 0.5, -0.5), 0.035)
	tween.tween_property(camera, "rotation_degrees", original_rot, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _play_critical_attack_feedback() -> void:
	var original_rot := camera.rotation_degrees
	var original_fov := camera.fov
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(-5.0, 3.8, -3.2), 0.025)
	tween.parallel().tween_property(camera, "fov", original_fov + 6.0, 0.025)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(4.2, -3.0, 2.8), 0.035)
	tween.tween_property(camera, "rotation_degrees", original_rot + Vector3(-2.4, 1.6, -1.6), 0.03)
	tween.tween_property(camera, "rotation_degrees", original_rot, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(camera, "fov", original_fov, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
