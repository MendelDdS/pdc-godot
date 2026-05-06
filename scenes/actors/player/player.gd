# res://.../player.gd

extends CharacterBody3D
class_name Player

enum PlayerClass { WARRIOR, MAGE }

@export var player_class: PlayerClass = PlayerClass.MAGE
@export var warrior_starting_weapon_scene: PackedScene
@export var mage_starting_weapon_scene: PackedScene

const MOVE_DURATION: float = 0.35
const ROTATE_DURATION: float = 0.3
const HEAD_BOB_FREQ: float = 8.0
const HEAD_BOB_AMP: float = 0.08
const TILT_AMOUNT: float = 2.5
const PERFECT_BLOCK_WINDOW: float = 0.22
const CRITICAL_ATTACK_WINDOW: float = 1.2
const DEFAULT_ATTACK_DAMAGE: int = 20
const DEFAULT_CRITICAL_ATTACK_DAMAGE: int = 60

const COMBAT_SCRIPT_BY_WEAPON_KIND = {
	"Sword": preload("res://scenes/actors/player/sword_combat.gd"),
	"Staff": preload("res://scenes/actors/player/staff_combat.gd")
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
var moving_from_cell: Vector2i
var moving_target_cell: Vector2i
var is_rotating: bool = false
var bob_time: float = 0.0
var base_camera_y: float = 0.0

var current_weapon: Node3D = null
var current_weapon_scene: PackedScene = null
var active_weapon_combat: Node = null
var is_attacking: bool = false
var is_defending: bool = false
var block_started_msec: int = -100000
var block_ready_msec: int = -100000
var defense_pose_ready: bool = false
var critical_attack_until_msec: int = -100000
var active_attack_is_critical: bool = false
var queued_magic_is_critical: bool = false
var can_attack: bool = true

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

	var starting_weapon_scene := _get_starting_weapon_scene()
	if starting_weapon_scene != null:
		equip_weapon(starting_weapon_scene, false, global_position)
	else:
		push_warning("Player sem arma inicial configurada.")
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

	if active_weapon_combat == null:
		return

	if _is_using_staff():
		if Input.is_action_just_pressed("Item Action") and can_attack and not is_defending:
			active_weapon_combat.start_draw(combat_ui.current_direction)
		elif Input.is_action_just_released("Item Action") and active_weapon_combat.is_drawing():
			var cast_result: Dictionary = active_weapon_combat.finish_draw()
			if cast_result["valid"]:
				queued_magic_is_critical = cast_result["critical"]
				perform_attack()
	elif Input.is_action_just_pressed("Item Action") and can_attack and not is_defending:
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

func _get_starting_weapon_scene() -> PackedScene:
	return mage_starting_weapon_scene if player_class == PlayerClass.MAGE else warrior_starting_weapon_scene

func _is_using_staff() -> bool:
	return current_weapon != null and current_weapon.has_method("is_staff") and current_weapon.is_staff()

func _is_using_sword() -> bool:
	return current_weapon != null and not _is_using_staff()

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
	if active_weapon_combat == null or is_attacking or attack_recovering:
		return

	var result: Dictionary = active_weapon_combat.update_weapon_stance(delta, is_defending, DEFENSE_STANCE)
	if is_defending and not defense_pose_ready and result.get("defense_ready", false):
		defense_pose_ready = true
		block_ready_msec = Time.get_ticks_msec()

func perform_attack() -> void:
	if is_attacking or not can_attack or active_weapon_combat == null:
		return
		
	is_attacking = true
	can_attack = false
	active_attack_is_critical = _consume_critical_attack_window() or (queued_magic_is_critical if _is_using_staff() else false)
	queued_magic_is_critical = false
	combat_ui.is_locked = true
	melee_ray.enabled = true

	var attack_data: Dictionary = active_weapon_combat.build_attack_data(active_attack_is_critical)
	weapon_pivot.position = attack_data["original_pos"]
	weapon_pivot.quaternion = attack_data["original_quat"]

	weapon_attack_animator.play_attack(
		attack_data["original_pos"],
		attack_data["original_quat"],
		attack_data["windup_pos"],
		attack_data["windup_quat"],
		attack_data["attack_pos"],
		attack_data["attack_quat"],
		attack_data["final_pos"],
		attack_data["final_quat"],
		attack_data["next_stance"],
		attack_data["camera_kick_dir"],
		Callable(self, "_on_attack_impact_event"),
		Callable(self, "_on_attack_animation_finished_event")
	)

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

func _on_attack_impact_event(camera_kick_dir: Vector3) -> void:
	_apply_camera_feedback(camera_kick_dir)
	if active_attack_is_critical:
		_play_critical_attack_feedback()
	if _is_using_staff():
		_check_magic_hit()
	else:
		_check_hit()

func _on_attack_animation_finished_event(next_stance: int, _final_pos: Vector3, _final_rot: Vector3) -> void:
	is_attacking = false
	attack_recovering = false
	attack_recovery_timer = 0.0
	can_attack = true
	combat_ui.is_locked = false
	melee_ray.enabled = false
	active_attack_is_critical = false
	if active_weapon_combat != null:
		active_weapon_combat.on_attack_finished(next_stance)

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
			health.take_damage(_get_current_attack_damage())

func _check_magic_hit() -> void:
	var start := camera.global_position
	var end := start + (-camera.global_transform.basis.z.normalized() * _get_current_magic_range())
	var query := PhysicsRayQueryParameters3D.create(start, end, 2)
	query.exclude = [self]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_pos: Vector3 = hit.get("position", end)
	_spawn_magic_projectile(hit_pos, active_attack_is_critical)
	if hit.is_empty():
		return

	var target = hit.get("collider")
	var health = target.get_node_or_null("HealthComponent")
	if not health and target.get_parent():
		health = target.get_parent().get_node_or_null("HealthComponent")

	if health:
		var hit_owner = health.get_parent()
		if active_attack_is_critical and hit_owner and hit_owner.has_method("on_critical_hit_by_player"):
			hit_owner.on_critical_hit_by_player(self)
		elif hit_owner and hit_owner.has_method("on_hit_by_player"):
			hit_owner.on_hit_by_player(self)
		health.take_damage(_get_current_attack_damage())

func _get_current_magic_range() -> float:
	if current_weapon != null and current_weapon.has_method("get_magic_range"):
		return current_weapon.get_magic_range()

	return 18.0

func _get_current_attack_damage() -> int:
	if current_weapon == null:
		return DEFAULT_CRITICAL_ATTACK_DAMAGE if active_attack_is_critical else DEFAULT_ATTACK_DAMAGE

	if active_attack_is_critical and current_weapon.has_method("roll_critical_attack_damage"):
		return current_weapon.roll_critical_attack_damage()

	if current_weapon.has_method("roll_attack_damage"):
		return current_weapon.roll_attack_damage()

	return DEFAULT_CRITICAL_ATTACK_DAMAGE if active_attack_is_critical else DEFAULT_ATTACK_DAMAGE

func equip_weapon(weapon_scene: PackedScene, drop_current: bool, drop_position: Vector3) -> void:
	var next_weapon := weapon_scene.instantiate()
	if not _can_equip_weapon(next_weapon):
		next_weapon.queue_free()
		return

	if drop_current and current_weapon_scene != null:
		_drop_current_weapon(drop_position)

	if current_weapon:
		current_weapon.queue_free()

	current_weapon = next_weapon
	current_weapon_scene = weapon_scene
	if current_weapon.has_method("set_pickup_enabled"):
		current_weapon.set_pickup_enabled(false)
	weapon_pivot.add_child(current_weapon)
	current_weapon.position = Vector3.ZERO
	current_weapon.rotation = Vector3.ZERO
	_refresh_weapon_combat()
	_on_combat_direction_changed(0)

func _can_equip_weapon(weapon: Node) -> bool:
	if player_class == PlayerClass.WARRIOR:
		return weapon.has_method("is_sword") and weapon.is_sword()

	return weapon.has_method("is_staff") and weapon.is_staff()

func _drop_current_weapon(drop_position: Vector3) -> void:
	var dropped_weapon := current_weapon_scene.instantiate()
	var drop_parent := _get_weapon_drop_parent()
	drop_parent.add_child(dropped_weapon)
	dropped_weapon.global_position = Vector3(drop_position.x, drop_position.y, drop_position.z)
	dropped_weapon.rotation = Vector3.ZERO
	if dropped_weapon.has_method("set_pickup_enabled"):
		dropped_weapon.set_pickup_enabled(true)

func _get_weapon_drop_parent() -> Node:
	var level_container := get_parent().get_node_or_null("LevelContainer")
	if level_container and level_container.get_child_count() > 0:
		return level_container.get_child(0)

	return get_tree().current_scene

func _refresh_weapon_combat() -> void:
	if active_weapon_combat != null:
		active_weapon_combat.queue_free()
		active_weapon_combat = null

	var weapon_kind := _get_current_weapon_kind()
	if not COMBAT_SCRIPT_BY_WEAPON_KIND.has(weapon_kind):
		push_error("Sem combat configurado para arma do tipo: %s" % weapon_kind)
		return

	var combat_script: Script = COMBAT_SCRIPT_BY_WEAPON_KIND[weapon_kind]
	active_weapon_combat = combat_script.new()
	active_weapon_combat.name = "%sCombat" % weapon_kind
	add_child(active_weapon_combat)
	active_weapon_combat.setup(combat_ui, weapon_pivot, camera)
	active_weapon_combat.reset()

func _get_current_weapon_kind() -> String:
	if current_weapon != null and current_weapon.has_method("get_weapon_kind"):
		return current_weapon.get_weapon_kind()

	return ""

func _on_combat_direction_changed(dir_index: int) -> void:
	if active_weapon_combat == null:
		return

	active_weapon_combat.handle_direction_changed(dir_index, is_attacking, combat_ui.is_locked)

func handle_movement_input() -> void:
	if is_moving or is_rotating or is_attacking:
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
	var previous_pos := global_position
	var target_pos = global_position + direction.normalized() * Constants.TILE_SIZE
	ray.force_raycast_update()

	if ray.is_colliding() || _has_enemy_on_tile(target_pos):
		play_wall_bump_animation(direction)
		return

	is_moving = true
	moving_from_cell = _world_to_cell(previous_pos)
	moving_target_cell = _world_to_cell(target_pos)

	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(self, "global_position", target_pos, MOVE_DURATION)

	if is_strafe:
		var target_tilt = deg_to_rad(-strafe_dir * TILT_AMOUNT)
		tween.tween_property(camera, "rotation:z", target_tilt, MOVE_DURATION * 0.5)
		tween.chain().tween_property(camera, "rotation:z", 0.0, MOVE_DURATION * 0.5)

	tween.chain().tween_callback(func():
		is_moving = false
		_try_pickup_weapon_current_tile(previous_pos)
	)

func _try_pickup_weapon_current_tile(drop_position: Vector3) -> void:
	var current_cell := _world_to_cell(global_position)
	for pickup in get_tree().get_nodes_in_group("weapon_pickups"):
		if not pickup is Node3D:
			continue
		if _world_to_cell(pickup.global_position) != current_cell:
			continue
		if not pickup.has_method("get_weapon_scene"):
			continue

		var weapon_scene: PackedScene = pickup.get_weapon_scene()
		if _try_equip_pickup_weapon(weapon_scene, pickup, drop_position):
			return

func _try_equip_pickup_weapon(weapon_scene: PackedScene, pickup: Node, drop_position: Vector3) -> bool:
	var test_weapon := weapon_scene.instantiate()
	var can_equip := _can_equip_weapon(test_weapon)
	test_weapon.queue_free()
	if not can_equip:
		return false

	pickup.queue_free()
	equip_weapon(weapon_scene, true, drop_position)
	return true

func _has_enemy_on_tile(target_pos: Vector3) -> bool:
	var target_cell := _world_to_cell(target_pos)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("blocks_player_cell") and enemy.blocks_player_cell(target_cell):
			return true
		if enemy.has_method("occupies_cell") and enemy.occupies_cell(target_cell):
			return true
		if enemy.has_method("get_current_cell") and enemy.get_current_cell() == target_cell:
			return true

	return false

func occupies_cell(cell: Vector2i) -> bool:
	if _world_to_cell(global_position) == cell:
		return true

	return is_moving and (moving_from_cell == cell or moving_target_cell == cell)

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

func _spawn_magic_projectile(target_pos: Vector3, critical: bool) -> void:
	var projectile := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08 if not critical else 0.13
	mesh.height = mesh.radius * 2.0
	projectile.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.75, 1.0, 1.0) if not critical else Color(1.0, 0.85, 0.25, 1.0)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.5 if not critical else 5.0
	projectile.material_override = material

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = weapon_pivot.global_position

	var tween := create_tween()
	tween.tween_property(projectile, "global_position", target_pos, 0.16 if not critical else 0.1)
	tween.tween_property(projectile, "scale", Vector3.ZERO, 0.08)
	tween.tween_callback(projectile.queue_free)
