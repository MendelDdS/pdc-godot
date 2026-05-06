extends CharacterBody3D
class_name Enemy

enum State { IDLE, CHASE, ATTACK, STUNNED, DEAD }

@export var attack_damage: int = 5
@export var attack_windup: float = 0.35
@export var attack_cooldown: float = 1.0
@export var stun_duration: float = 1.4
@export var vision_range_tiles: int = 4
@export var move_duration: float = 0.7

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
var position_feedback_tween: Tween
var reset_body_rotation_next_frame: bool = false
var base_global_position: Vector3 = Vector3.ZERO
var reset_position_next_frame: bool = false
var has_detected_player: bool = false
var is_moving: bool = false
var moving_from_cell: Vector2i
var moving_target_cell: Vector2i
var move_tween: Tween

func _ready() -> void:
	add_to_group("enemies")
	health_component.entity_died.connect(_enemy_died)
	health_component.damage_taken.connect(_on_damage_taken)
	player = _find_player()
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = base_body_color
	body.material_override = body_material
	base_global_position = global_position
	base_body_rotation_degrees = body.rotation_degrees

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
			player.play_block_impact_feedback()
	else:
		player.health_component.take_damage(attack_damage)

func stun(duration: float) -> void:
	state = State.STUNNED
	stun_timer = duration
	cooldown_timer = attack_cooldown
	_stop_movement()
	_reset_body_rotation()
	_play_stun_feedback()

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

func _play_damage_feedback() -> void:
	body_material.albedo_color = Color(1.0, 0.1, 0.1, 1.0)

	var tween := create_tween()
	tween.tween_property(body_material, "albedo_color", base_body_color, 0.18)

func _play_critical_damage_feedback() -> void:
	body_material.albedo_color = Color(1.0, 0.85, 0.25, 1.0)
	if body_rotation_tween:
		body_rotation_tween.kill()
	if position_feedback_tween:
		position_feedback_tween.kill()
	body.rotation_degrees = base_body_rotation_degrees
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

func _reset_body_rotation() -> void:
	if body_rotation_tween:
		body_rotation_tween.kill()
		body_rotation_tween = null
	body.rotation_degrees = base_body_rotation_degrees

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
	queue_free()
