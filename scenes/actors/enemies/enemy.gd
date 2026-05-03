extends CharacterBody3D
class_name Enemy

enum State { IDLE, ATTACK, STUNNED, DEAD }

@export var attack_damage: int = 10
@export var attack_windup: float = 0.35
@export var attack_cooldown: float = 1.0
@export var stun_duration: float = 1.4

@onready var health_component: HealthComponent = $HealthComponent
@onready var body: MeshInstance3D = $EnemyBody

var state: State = State.IDLE
var player: Player
var attack_timer: float = 0.0
var cooldown_timer: float = 0.0
var body_material: StandardMaterial3D
var base_body_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var attack_has_hit: bool = false
var attack_target_cell: Vector2i
var stun_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	health_component.entity_died.connect(_enemy_died)
	health_component.damage_taken.connect(_on_damage_taken)
	player = _find_player()
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = base_body_color
	body.material_override = body_material

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if player == null or not is_instance_valid(player):
		player = _find_player()
		return

	if cooldown_timer > 0.0:
		cooldown_timer -= delta

	match state:
		State.IDLE:
			if cooldown_timer <= 0.0 and _is_player_in_front_tile():
				_start_attack()
		State.ATTACK:
			_process_attack(delta)
		State.STUNNED:
			_process_stunned(delta)

func _start_attack() -> void:
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
		state = State.IDLE
		cooldown_timer = attack_cooldown

func _apply_attack_hit() -> void:
	if _world_to_cell(player.global_position) != attack_target_cell:
		return

	if player.is_blocking():
		if player.is_perfect_blocking():
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
	_play_stun_feedback()

func _process_stunned(delta: float) -> void:
	stun_timer -= delta
	if stun_timer <= 0.0:
		body.rotation_degrees = Vector3.ZERO
		state = State.IDLE
		cooldown_timer = attack_cooldown

func _is_player_in_front_tile() -> bool:
	return _get_front_cell() == _world_to_cell(player.global_position)

func _get_front_cell() -> Vector2i:
	var front_pos := global_position + (-global_transform.basis.z.normalized() * Constants.TILE_SIZE)
	return _world_to_cell(front_pos)

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
	_look_at_flat(player.global_position)
	_play_damage_feedback()

func _play_damage_feedback() -> void:
	body_material.albedo_color = Color(1.0, 0.1, 0.1, 1.0)

	var tween := create_tween()
	tween.tween_property(body_material, "albedo_color", base_body_color, 0.18)

func _play_stun_feedback() -> void:
	var tween := create_tween()
	tween.set_loops(4)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(body, "rotation_degrees", Vector3(0.0, 0.0, 7.0), 0.12)
	tween.tween_property(body, "rotation_degrees", Vector3(0.0, 0.0, -7.0), 0.12)
	tween.tween_property(body, "rotation_degrees", Vector3.ZERO, 0.08)

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / Constants.TILE_SIZE),
		floori(world_pos.z / Constants.TILE_SIZE)
	)

func get_current_cell() -> Vector2i:
	return _world_to_cell(global_position)

func _look_at_flat(target_pos: Vector3) -> void:
	var look_target := Vector3(target_pos.x, global_position.y, target_pos.z)
	if global_position.distance_squared_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP)
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
