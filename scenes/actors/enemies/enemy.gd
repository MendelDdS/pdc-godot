extends CharacterBody3D
class_name Enemy

enum State { IDLE, CHASE, ATTACK, STUNNED, DEAD }

@export var enemy_data: EnemyData
@export var xp_reward: int = 25
@export var attack_damage: int = 5
@export var attack_windup: float = 0.35
@export var attack_cooldown: float = 1.0
@export var stun_duration: float = 1.4
@export var vision_range_tiles: int = 4
@export var move_duration: float = 0.7
@export_range(0.0, 1.0, 0.05) var predicted_sword_block_chance: float = 0.75
@export_range(0.0, 1.0, 0.05) var unpredicted_sword_block_chance: float = 0.2
@export_range(0.0, 1.0, 0.05) var magic_dodge_chance: float = 0.45
@export_range(0.0, 1.0, 0.05) var critical_magic_dodge_chance: float = 0.2
@export var defense_cooldown: float = 0.55

@onready var health_component: HealthComponent = $HealthComponent
@onready var body: MeshInstance3D = $EnemyBody

var state: State = State.IDLE
var player: Player
var attack_timer: float = 0.0
var cooldown_timer: float = 0.0
var body_material: StandardMaterial3D
var base_body_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var base_body_rotation_degrees: Vector3 = Vector3.ZERO
var attack_has_hit: bool = false
var attack_target_cell: Vector2i
var stun_timer: float = 0.0
var stun_tween: Tween
var body_rotation_tween: Tween
var body_position_tween: Tween
var position_feedback_tween: Tween
var reset_body_rotation_next_frame: bool = false
var base_global_position: Vector3 = Vector3.ZERO
var base_body_position: Vector3 = Vector3.ZERO
var reset_position_next_frame: bool = false
var has_detected_player: bool = false
var is_moving: bool = false
var moving_from_cell: Vector2i
var moving_target_cell: Vector2i
var move_tween: Tween
var defense_timer: float = 0.0
var predicted_sword_guards: Array[int] = []

func _ready() -> void:
	_apply_enemy_data()
	add_to_group("enemies")
	health_component.entity_died.connect(_enemy_died)
	health_component.damage_taken.connect(_on_damage_taken)
	player = _find_player()
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = base_body_color
	body.material_override = body_material
	base_global_position = global_position
	base_body_position = body.position
	base_body_rotation_degrees = body.rotation_degrees

func _apply_enemy_data() -> void:
	if enemy_data == null:
		return

	xp_reward = enemy_data.xp_reward
	attack_damage = enemy_data.attack_damage
	attack_windup = enemy_data.attack_windup
	attack_cooldown = enemy_data.attack_cooldown
	stun_duration = enemy_data.stun_duration
	vision_range_tiles = enemy_data.vision_range_tiles
	move_duration = enemy_data.move_duration
	predicted_sword_block_chance = enemy_data.predicted_sword_block_chance
	unpredicted_sword_block_chance = enemy_data.unpredicted_sword_block_chance
	magic_dodge_chance = enemy_data.magic_dodge_chance
	critical_magic_dodge_chance = enemy_data.critical_magic_dodge_chance
	if health_component != null:
		health_component.max_health = enemy_data.max_health

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if reset_body_rotation_next_frame:
		reset_body_rotation_next_frame = false
		body.rotation_degrees = base_body_rotation_degrees
	if reset_position_next_frame:
		reset_position_next_frame = false
		global_position = base_global_position

	if player == null or not is_instance_valid(player):
		player = _find_player()
		return

	if cooldown_timer > 0.0:
		cooldown_timer -= delta
	if defense_timer > 0.0:
		defense_timer -= delta

	match state:
		State.IDLE:
			if _is_player_in_front_tile() and cooldown_timer <= 0.0:
				has_detected_player = true
				_start_attack()
			elif _can_see_player():
				has_detected_player = true
				state = State.CHASE
		State.CHASE:
			_process_chase()
		State.ATTACK:
			_process_attack(delta)
		State.STUNNED:
			_process_stunned(delta)

func _start_attack() -> void:
	if is_moving:
		return

	has_detected_player = true
	state = State.ATTACK
	attack_timer = attack_windup
	attack_has_hit = false
	attack_target_cell = _get_front_cell()
	_play_attack_feedback()

func _process_attack(delta: float) -> void:
	attack_timer -= delta
	if not attack_has_hit and attack_timer <= attack_windup * 0.55:
		attack_has_hit = true
		_apply_attack_hit()

	if attack_timer <= 0.0:
		state = State.CHASE if has_detected_player else State.IDLE
		cooldown_timer = attack_cooldown

func _apply_attack_hit() -> void:
	if _world_to_cell(player.global_position) != attack_target_cell:
		return

	if player.is_blocking():
		if player.is_perfect_blocking():
			player.open_critical_attack_window()
			player.play_perfect_block_impact_feedback()
			stun(stun_duration)
		else:
			if not player.play_block_impact_feedback():
				player.health_component.take_damage(attack_damage)
	else:
		player.health_component.take_damage(attack_damage)

func stun(duration: float) -> void:
	state = State.STUNNED
	stun_timer = duration
	cooldown_timer = attack_cooldown
	_stop_movement()
	_reset_body_rotation()
	_play_stun_feedback()
	_show_stunned_text()

func _process_stunned(delta: float) -> void:
	stun_timer -= delta
	if stun_timer <= 0.0:
		_reset_body_rotation()
		state = State.CHASE if has_detected_player else State.IDLE
		cooldown_timer = attack_cooldown

func _is_player_in_front_tile() -> bool:
	return _get_front_cell() == _world_to_cell(player.global_position)

func _get_front_cell() -> Vector2i:
	return get_current_cell() + _get_forward_cell_direction()

func _can_see_player() -> bool:
	var current_cell: Vector2i = get_current_cell()
	var player_cell: Vector2i = _world_to_cell(player.global_position)
	var forward_dir: Vector2i = _get_forward_cell_direction()

	for distance in range(1, vision_range_tiles + 1):
		if _is_step_blocked(current_cell + (forward_dir * (distance - 1)), forward_dir):
			return false
		var checked_cell: Vector2i = current_cell + (forward_dir * distance)
		if checked_cell == player_cell:
			return true

	return false

func _process_chase() -> void:
	if is_moving:
		return

	if _is_player_in_front_tile():
		if cooldown_timer <= 0.0:
			_start_attack()
		return

	var current_cell := get_current_cell()
	var player_cell := _world_to_cell(player.global_position)
	var distance := _manhattan_distance(current_cell, player_cell)
	if distance > vision_range_tiles:
		has_detected_player = false
		state = State.IDLE
		return

	if distance <= 1:
		_face_cell(player_cell)
		return

	var step_dir := _get_chase_step_direction(current_cell, player_cell)
	if step_dir == Vector2i.ZERO:
		return

	_face_direction(step_dir)
	_start_tile_move(step_dir)

func _get_chase_step_direction(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var delta := to_cell - from_cell
	var primary := Vector2i(_int_sign(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, _int_sign(delta.y))
	var secondary := Vector2i(0, _int_sign(delta.y)) if primary.x != 0 else Vector2i(_int_sign(delta.x), 0)

	if _can_step_to(from_cell, primary):
		return primary
	if _can_step_to(from_cell, secondary):
		return secondary

	return Vector2i.ZERO

func _can_step_to(from_cell: Vector2i, direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO:
		return false

	var target_cell := from_cell + direction
	if player.has_method("occupies_cell") and player.occupies_cell(target_cell):
		return false
	if target_cell == _world_to_cell(player.global_position):
		return false
	if _has_enemy_on_cell(target_cell):
		return false

	return not _is_step_blocked(from_cell, direction)

func _start_tile_move(direction: Vector2i) -> void:
	is_moving = true
	moving_from_cell = _world_to_cell(global_position)
	moving_target_cell = moving_from_cell + direction
	var target_pos := _cell_to_world(moving_target_cell)
	_face_direction(direction)

	move_tween = create_tween()
	move_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_property(self, "global_position", target_pos, move_duration)
	move_tween.tween_callback(_finish_tile_move)

func _finish_tile_move() -> void:
	global_position = _cell_to_world(moving_target_cell)
	is_moving = false
	base_global_position = global_position
	move_tween = null

func _stop_movement() -> void:
	if move_tween:
		move_tween.kill()
		move_tween = null
	is_moving = false

func _play_attack_feedback() -> void:
	var origin := global_position
	var hit_pos := origin + (-global_transform.basis.z.normalized() * Constants.TILE_SIZE * 0.18)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", hit_pos, attack_windup * 0.45)
	tween.tween_property(self, "global_position", origin, attack_windup * 0.55)

func _on_damage_taken() -> void:
	if player != null and is_instance_valid(player):
		_look_at_flat(player.global_position)

	_play_damage_feedback()

func on_hit_by_player(attacker: Player) -> void:
	player = attacker
	has_detected_player = true
	if state == State.IDLE:
		state = State.CHASE
	_look_at_flat(player.global_position)
	_play_damage_feedback()

func on_critical_hit_by_player(attacker: Player) -> void:
	player = attacker
	has_detected_player = true
	if state == State.IDLE:
		state = State.CHASE
	_look_at_flat(player.global_position)
	_play_critical_damage_feedback()

func try_avoid_player_attack(attacker: Player, attack_context: Dictionary) -> bool:
	if state == State.DEAD or state == State.STUNNED:
		return false

	player = attacker
	has_detected_player = true
	if state == State.IDLE:
		state = State.CHASE
	_look_at_flat(player.global_position)

	var weapon_kind := String(attack_context.get("weapon_kind", ""))
	var critical := bool(attack_context.get("critical", false))
	if weapon_kind == "Staff":
		var dodge_chance := critical_magic_dodge_chance if critical else magic_dodge_chance
		if randf() <= dodge_chance:
			_play_dodge_feedback()
			_show_miss_text()
			defense_timer = defense_cooldown
			return true
		return false

	if weapon_kind != "Sword":
		return false
	if critical or defense_timer > 0.0:
		_update_sword_prediction(attack_context)
		return false

	var attack_direction := int(attack_context.get("attack_direction", -1))
	var block_chance := predicted_sword_block_chance if predicted_sword_guards.has(attack_direction) else unpredicted_sword_block_chance
	if attack_direction == 0 and predicted_sword_guards.has(0):
		block_chance = 1.0
	_update_sword_prediction(attack_context)
	if randf() > block_chance:
		return false

	_play_block_feedback()
	_show_block_text()
	defense_timer = defense_cooldown
	return true

func show_damage_number(amount: int, critical: bool = false) -> void:
	var color := Color(1.0, 0.84, 0.28, 1.0) if critical else Color(1.0, 0.22, 0.16, 1.0)
	var label := _create_floating_text(str(amount), color, 100 if critical else 80)
	var start_pos := label.global_position + Vector3(randf_range(-0.18, 0.18), 0.0, 0.0)
	label.global_position = start_pos
	label.scale = Vector3.ONE * (1.25 if critical else 1.0)

	var tween := label.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "global_position", start_pos + Vector3(0.0, 1.05 if critical else 0.82, 0.0), 0.56)
	tween.parallel().tween_property(label, "scale", Vector3.ONE * 0.9, 0.56)
	tween.parallel().tween_property(label, "modulate", Color(color.r, color.g, color.b, 0.0), 0.56)
	tween.tween_callback(label.queue_free)

func _play_damage_feedback() -> void:
	body_material.albedo_color = Color(1.0, 0.1, 0.1, 1.0)

	var tween := create_tween()
	tween.tween_property(body_material, "albedo_color", base_body_color, 0.18)

func _play_critical_damage_feedback() -> void:
	body_material.albedo_color = Color(1.0, 0.85, 0.25, 1.0)
	if body_rotation_tween:
		body_rotation_tween.kill()
	if body_position_tween:
		body_position_tween.kill()
	if position_feedback_tween:
		position_feedback_tween.kill()
	body.rotation_degrees = base_body_rotation_degrees
	body.position = base_body_position
	var anchor_pos := _cell_to_world(get_current_cell())
	global_position = anchor_pos
	base_global_position = anchor_pos

	var recoil_pos := anchor_pos + (global_transform.basis.z.normalized() * Constants.TILE_SIZE * 0.22)
	position_feedback_tween = create_tween()
	position_feedback_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	position_feedback_tween.tween_property(self, "global_position", recoil_pos, 0.08)
	position_feedback_tween.tween_property(self, "global_position", anchor_pos, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	position_feedback_tween.tween_callback(_finish_position_feedback)

	body_rotation_tween = create_tween()
	body_rotation_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	body_rotation_tween.tween_property(body, "rotation_degrees", base_body_rotation_degrees + Vector3(-10.0, 0.0, 13.0), 0.08)
	body_rotation_tween.parallel().tween_property(body_material, "albedo_color", base_body_color, 0.32)
	body_rotation_tween.parallel().tween_property(body, "rotation_degrees", base_body_rotation_degrees + Vector3(4.0, 0.0, -6.0), 0.08)
	body_rotation_tween.tween_property(body, "rotation_degrees", base_body_rotation_degrees, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	body_rotation_tween.tween_callback(_finish_body_rotation_feedback)

func _play_stun_feedback() -> void:
	if body_rotation_tween:
		body_rotation_tween.kill()
	body_rotation_tween = create_tween()
	body_rotation_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in 4:
		body_rotation_tween.tween_property(body, "rotation_degrees", base_body_rotation_degrees + Vector3(0.0, 0.0, 7.0), 0.12)
		body_rotation_tween.tween_property(body, "rotation_degrees", base_body_rotation_degrees + Vector3(0.0, 0.0, -7.0), 0.12)
	body_rotation_tween.tween_property(body, "rotation_degrees", base_body_rotation_degrees, 0.08)
	body_rotation_tween.tween_callback(_reset_body_rotation)

func _play_block_feedback() -> void:
	body_material.albedo_color = Color(0.65, 0.75, 0.85, 1.0)
	if body_rotation_tween:
		body_rotation_tween.kill()
	if body_position_tween:
		body_position_tween.kill()
	body.rotation_degrees = base_body_rotation_degrees
	body.position = base_body_position

	body_rotation_tween = create_tween()
	body_rotation_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	body_rotation_tween.tween_property(body, "rotation_degrees", base_body_rotation_degrees + Vector3(-7.0, 0.0, 16.0), 0.045)
	body_rotation_tween.parallel().tween_property(body_material, "albedo_color", Color(0.95, 1.0, 1.0, 1.0), 0.045)
	body_rotation_tween.tween_property(body, "rotation_degrees", base_body_rotation_degrees + Vector3(3.0, 0.0, -8.0), 0.055)
	body_rotation_tween.parallel().tween_property(body_material, "albedo_color", base_body_color, 0.18)
	body_rotation_tween.tween_property(body, "rotation_degrees", base_body_rotation_degrees, 0.09)
	body_rotation_tween.tween_callback(_finish_body_rotation_feedback)

	body_position_tween = create_tween()
	body_position_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	body_position_tween.tween_property(body, "position", base_body_position + Vector3(0.0, 0.04, 0.26), 0.045)
	body_position_tween.tween_property(body, "position", base_body_position + Vector3(0.0, 0.0, -0.08), 0.055)
	body_position_tween.tween_property(body, "position", base_body_position, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	body_position_tween.tween_callback(_finish_body_position_feedback)

func _show_block_text() -> void:
	var color := Color(0.78, 0.88, 1.0, 1.0)
	var label := _create_floating_text("Block!", color, 80)
	var origin := label.global_position
	label.scale = Vector3.ONE * 1.08

	var tween := label.create_tween()
	tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	for i in 20:
		var offset := Vector3(0.0, randf_range(-0.08, 0.08), randf_range(-0.1, 0.1))
		tween.tween_property(label, "global_position", origin + offset, 0.025)
	tween.tween_property(label, "global_position", origin + Vector3(0.0, 0.28, 0.0), 1.12)
	tween.parallel().tween_property(label, "modulate", Color(color.r, color.g, color.b, 0.0), 1)
	tween.tween_callback(label.queue_free)

func _play_dodge_feedback() -> void:
	body_material.albedo_color = Color(0.25, 0.9, 1.0, 1.0)
	if body_position_tween:
		body_position_tween.kill()
	body.position = base_body_position

	var side := -1.0 if randf() < 0.5 else 1.0
	var dodge_offset := global_transform.basis.x.normalized() * side * (Constants.TILE_SIZE * 0.16)
	body_position_tween = create_tween()
	body_position_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	body_position_tween.tween_property(body, "position", base_body_position + dodge_offset, 0.07)
	body_position_tween.parallel().tween_property(body_material, "albedo_color", base_body_color, 0.2)
	body_position_tween.tween_property(body, "position", base_body_position, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	body_position_tween.tween_callback(_finish_body_position_feedback)

func _show_miss_text() -> void:
	var color := Color(0.72, 0.78, 0.86, 1.0)
	var label := _create_floating_text("Miss...", color, 80)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_face_label_to_camera(label)
	var origin := label.global_position
	var side := -1.0 if randf() < 0.5 else 1.0
	var lateral := _get_screen_lateral_direction() * side
	var peak := origin + lateral * 0.32 + Vector3(0.0, 0.62, 0.0)
	var end := origin + lateral * 1.05 + Vector3(0.0, -0.22, 0.0)

	var tween := label.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(progress: float) -> void:
		label.global_position = _quadratic_bezier(origin, peak, end, progress)
	, 0.0, 1.0, 0.58)
	tween.parallel().tween_property(label, "rotation:z", deg_to_rad(side * 26.0), 0.58)
	tween.parallel().tween_property(label, "modulate", Color(color.r, color.g, color.b, 0.0), 0.58)
	tween.tween_callback(label.queue_free)

func _show_stunned_text() -> void:
	var color := Color(1.0, 0.88, 0.32, 1.0)
	var label := _create_floating_text("Stunned!", color, 88, false)
	_face_label_to_camera(label)
	label.position += Vector3(0.0, 0.12, 0.0)

	var tween := label.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in 3:
		tween.tween_property(label, "rotation:z", deg_to_rad(25.0), 0.09)
		tween.tween_property(label, "rotation:z", deg_to_rad(-25.0), 0.09)
	tween.tween_property(label, "rotation:z", 0.0, 0.08)
	tween.tween_property(label, "modulate", Color(color.r, color.g, color.b, 0.0), 0.18)
	tween.tween_callback(label.queue_free)

func _create_floating_text(text: String, color: Color, font_size: int, use_billboard: bool = true) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0.02, 0.02, 0.025, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED if use_billboard else BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	get_tree().current_scene.add_child(label)
	label.global_position = global_position + Vector3(0.0, 2.55, 0.0)
	return label

func _face_label_to_camera(label: Label3D) -> void:
	var viewport_camera := get_viewport().get_camera_3d()
	if viewport_camera == null:
		return

	label.global_rotation = viewport_camera.global_rotation

func _get_screen_lateral_direction() -> Vector3:
	var viewport_camera := get_viewport().get_camera_3d()
	if viewport_camera != null:
		return viewport_camera.global_transform.basis.x.normalized()

	return global_transform.basis.x.normalized()

func _quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return (u * u * p0) + (2.0 * u * t * p1) + (t * t * p2)

func _update_sword_prediction(attack_context: Dictionary) -> void:
	var next_stance := int(attack_context.get("next_stance", -1))
	predicted_sword_guards = _guards_from_player_stance(next_stance)

func _guards_from_player_stance(stance: int) -> Array[int]:
	match stance:
		0:
			return [0]
		1, 2, 5:
			return [1, 2, 5]
		3, 4:
			return [3, 4]
		_:
			return []

func _reset_body_rotation() -> void:
	if body_rotation_tween:
		body_rotation_tween.kill()
		body_rotation_tween = null
	body.rotation_degrees = base_body_rotation_degrees

func _finish_body_position_feedback() -> void:
	body_position_tween = null
	body.position = base_body_position

func _finish_body_rotation_feedback() -> void:
	body_rotation_tween = null
	body.rotation_degrees = base_body_rotation_degrees
	reset_body_rotation_next_frame = true

func _finish_position_feedback() -> void:
	position_feedback_tween = null
	global_position = base_global_position
	reset_position_next_frame = true

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / Constants.TILE_SIZE),
		floori(world_pos.z / Constants.TILE_SIZE)
	)

func get_current_cell() -> Vector2i:
	if is_moving:
		return moving_target_cell

	return _world_to_cell(global_position)

func occupies_cell(cell: Vector2i) -> bool:
	if _world_to_cell(global_position) == cell:
		return true

	return is_moving and (moving_from_cell == cell or moving_target_cell == cell)

func blocks_player_cell(cell: Vector2i) -> bool:
	if occupies_cell(cell):
		return true

	return state == State.ATTACK and attack_target_cell == cell

func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _get_forward_cell_direction() -> Vector2i:
	var forward := -global_transform.basis.z.normalized()
	if absf(forward.x) >= absf(forward.z):
		return Vector2i(_int_sign(forward.x), 0)

	return Vector2i(0, _int_sign(forward.z))

func _is_step_blocked(from_cell: Vector2i, direction: Vector2i) -> bool:
	var from_pos := _cell_to_world(from_cell) + Vector3(0.0, 1.0, 0.0)
	var to_pos := from_pos + Vector3(direction.x, 0.0, direction.y) * Constants.TILE_SIZE
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [self, player]

	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _has_enemy_on_cell(cell: Vector2i) -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self:
			continue
		if enemy.has_method("occupies_cell") and enemy.occupies_cell(cell):
			return true
		if enemy.has_method("get_current_cell") and enemy.get_current_cell() == cell:
			return true

	return false

func _cell_to_world(cell: Vector2i) -> Vector3:
	var half_tile := Constants.TILE_SIZE * 0.5
	return Vector3(
		(cell.x * Constants.TILE_SIZE) + half_tile,
		global_position.y,
		(cell.y * Constants.TILE_SIZE) + half_tile
	)

func _face_cell(cell: Vector2i) -> void:
	var current_cell := get_current_cell()
	var delta := cell - current_cell
	if absi(delta.x) >= absi(delta.y):
		_face_direction(Vector2i(_int_sign(delta.x), 0))
	else:
		_face_direction(Vector2i(0, _int_sign(delta.y)))

func _face_direction(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return

	var target_pos := global_position + Vector3(direction.x, 0.0, direction.y) * Constants.TILE_SIZE
	_look_at_flat(target_pos)

func _int_sign(value: float) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 0

func _look_at_flat(target_pos: Vector3) -> void:
	var look_target := Vector3(target_pos.x, global_position.y, target_pos.z)
	if global_position.distance_squared_to(look_target) > 0.01:
		var previous_direction := _get_forward_cell_direction()
		look_at(look_target, Vector3.UP)
		if _get_forward_cell_direction() != previous_direction:
			cooldown_timer = attack_cooldown

func _find_player() -> Player:
	return _find_player_in(get_tree().current_scene)

func _find_player_in(node: Node) -> Player:
	if node is Player:
		return node

	for child in node.get_children():
		var found := _find_player_in(child)
		if found != null:
			return found

	return null

func _enemy_died() -> void:
	state = State.DEAD
	if player != null and is_instance_valid(player) and player.has_method("add_experience"):
		player.add_experience(xp_reward)
	queue_free()
