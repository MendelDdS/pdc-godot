extends CharacterBody3D
class_name Player

# region --- Constantes e Configurações ---
const MOVE_DURATION: float = 0.35
const ROTATE_DURATION: float = 0.3
const HEAD_BOB_FREQ: float = 8.0
const HEAD_BOB_AMP: float = 0.08
const TILT_AMOUNT: float = 2.5 # Graus
const STANCE_TRANSITION_DURATION: float = 0.24
const STANCE_ROTATE_SPEED: float = 12.0

# Configurações de Combate
const SWORD_SCENE = preload("res://scenes/actors/items/simple_sword.tscn")
const STANCES = {
	0: {"pos": Vector3(0.5, -0.3, -1), "rot": Vector3(0, -90, 90)},    # CENTER (Meio)
	1: {"pos": Vector3(0, 0.7, -1), "rot": Vector3(0, -90, 0)},     # TOP (Cima)
	2: {"pos": Vector3(0.8, 0.5, -1), "rot": Vector3(-45, -90, 0)},   # TOP_RIGHT (Cima-Direita)
	3: {"pos": Vector3(0.8, -0.5, -1), "rot": Vector3(45, -90, 180)}, # BOTTOM_RIGHT (Baixo-Direita)
	4: {"pos": Vector3(-0.8, -0.5, -1), "rot": Vector3(-45, -90, -180)},  # BOTTOM_LEFT (Baixo-Esquerda)
	5: {"pos": Vector3(-0.8, 0.5, -1), "rot": Vector3(45, -90, 0)}     # TOP_LEFT (Cima-Esquerda)
}
const DEFENSE_STANCE = {"pos": Vector3(0.7, 0.5, -0.2), "rot": Vector3(180, 0, 45)}
# endregion

# region --- Referências de Nós ---
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
# endregion

# region --- Estado do Personagem ---
var player_name: String = "Mendel"
var is_moving: bool = false
var is_rotating: bool = false
var bob_time: float = 0.0
var base_camera_y: float = 0.0

# Estado de Combate
var current_weapon: Node3D = null
var current_stance_index: int = 0
var target_stance_pos: Vector3 = STANCES[0]["pos"]
var target_stance_rot: Vector3 = STANCES[0]["rot"]
var is_attacking: bool = false
var is_defending: bool = false
var can_attack: bool = true

# endregion

# region --- Ciclo de Vida ---
func _ready() -> void:
	print("Character created: " + player_name)
	base_camera_y = camera.position.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	health_component.entity_died.connect(_on_died)
	health_component.healing.connect(_on_health_changed)
	health_component.damage_taken.connect(_on_take_damage)
	
	combat_ui.direction_changed.connect(_on_combat_direction_changed)
	
	instantiate_weapon(SWORD_SCENE)
	
	# Impedir que a espada acerte o próprio jogador
	melee_ray.add_exception(self)

func _process(delta: float) -> void:
	handle_head_bob(delta)
	handle_movement_input()
	handle_combat_input()
	update_weapon_stance(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		combat_ui.handle_mouse_movement(event.relative)
	
	# Tecla para liberar o mouse para testes
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()
# endregion

# region --- Lógica de Combate ---
func handle_combat_input() -> void:
	# Detectar defesa (segurando botão de ação passiva)
	is_defending = Input.is_action_pressed("Item Passive")
	
	# Detectar ataque (clique único)
	if Input.is_action_just_pressed("Item Action") and can_attack and not is_defending:
		perform_attack()

func update_weapon_stance(delta: float) -> void:
	if is_attacking:
		return
		
	var target_pos = target_stance_pos
	var target_rot = target_stance_rot
	
	if is_defending:
		target_pos = DEFENSE_STANCE["pos"]
		target_rot = DEFENSE_STANCE["rot"]
		
	# Movimento linear de posição.
	weapon_pivot.position = weapon_pivot.position.move_toward(target_pos, STANCE_TRANSITION_DURATION * 25.0 * delta)

	# Rotação contínua, estável, sem flip 180/-180.
	var stable_target_rot := _get_stable_target_rotation(weapon_pivot.rotation_degrees, target_rot)
	var rot_weight := clampf(delta * STANCE_ROTATE_SPEED, 0.0, 1.0)
	_set_weapon_rotation_quat_weight(rot_weight, weapon_pivot.rotation_degrees, stable_target_rot)

func perform_attack() -> void:
	if is_attacking or not can_attack:
		return
		
	is_attacking = true
	can_attack = false
	combat_ui.is_locked = true
	melee_ray.enabled = true
	
	# 1. Preparar dados da postura e sincronizar UI
	var attack_from_stance := current_stance_index
	var next_stance = _get_next_stance_after_attack(attack_from_stance)
	combat_ui.set_direction(next_stance)

	# Força origem limpa do ataque para evitar bug em transição rápida.
	var stance_origin_pos: Vector3 = STANCES[attack_from_stance]["pos"]
	var stance_origin_rot: Vector3 = _normalize_degrees(STANCES[attack_from_stance]["rot"])
	weapon_pivot.position = stance_origin_pos
	_set_weapon_rotation_quat_weight(1.0, weapon_pivot.rotation_degrees, stance_origin_rot)
	
	# Usa a pose atual real como origem para evitar "snap" quando a arma ainda está em transição.
	var original_pos = weapon_pivot.position
	var original_rot = _normalize_degrees(weapon_pivot.rotation_degrees)
	var final_pos = STANCES[next_stance]["pos"]
	var final_rot = _normalize_degrees(STANCES[next_stance]["rot"])
	
	# 2. Calcular parâmetros de impacto
	var is_thrust = (attack_from_stance == 0)
	# Menos Z para cortes para evitar o efeito de "empurrar"; mais Z para estocada
	var lunge_z = -2.5 if is_thrust else -0.7 
	
	var lerp_weight = 0.5 
	var attack_pos = original_pos.lerp(final_pos, lerp_weight) + Vector3(0, 0, lunge_z)
	var attack_rot = _normalize_degrees(_lerp_degrees(original_rot, final_rot, lerp_weight))
	
	# Antecipação (Recuo antes do golpe)
	var windup_lerp = 0.25
	var windup_pos = original_pos.lerp(final_pos, windup_lerp) + Vector3(0, 0.05, 0.15)
	var windup_rot = _normalize_degrees(_lerp_degrees(original_rot, final_rot, windup_lerp) + Vector3(8, 0, 0))
	
	# Ajustes de peso baseados na postura inicial
	var camera_kick_dir = Vector3.ZERO
	match attack_from_stance:
		1: # TOP -> Corte descendente pesado (O "Rasgo")
			attack_pos.y -= 0.45
			attack_rot.x -= 35
			attack_rot.z += 20 # Inclina o gume da lâmina para o efeito de rasgo
			camera_kick_dir = Vector3(1.2, 0.2, 0)
		2, 3: # RIGHT SIDES
			attack_rot.z -= 15 # Inclina gume
			camera_kick_dir = Vector3(0, 1, -0.5)
		4, 5: # LEFT SIDES
			attack_rot.z += 15 # Inclina gume
			camera_kick_dir = Vector3(0, -1, 0.5)
		0: # CENTER -> Estocada
			windup_pos = original_pos + Vector3(0, 0, 0.4)
			attack_pos = original_pos + Vector3(0, 0, -2.5)
			camera_kick_dir = Vector3(0.8, 0, 0)

	# Segurança de trajetória:
	# evita que a animação "puxe" a espada para o player quando STANCES/offsets mudam.
	var max_allowed_pullback_z: float = original_pos.z + 0.08
	var min_required_lunge_z: float = original_pos.z - (2.5 if is_thrust else 0.35)
	windup_pos.z = min(windup_pos.z, max_allowed_pullback_z)
	attack_pos.z = min(attack_pos.z, min_required_lunge_z)
	
	attack_rot = _normalize_degrees(attack_rot)
	windup_rot = _normalize_degrees(windup_rot)

	weapon_attack_animator.play_attack(
		original_pos,
		_degrees_to_quat(original_rot),
		windup_pos,
		_degrees_to_quat(windup_rot),
		attack_pos,
		_degrees_to_quat(attack_rot),
		final_pos,
		_degrees_to_quat(final_rot),
		next_stance,
		camera_kick_dir,
		Callable(self, "_on_attack_impact_event"),
		Callable(self, "_on_attack_animation_finished_event")
	)

func _apply_camera_feedback(dir: Vector3) -> void:
	var kick_strength = 2.0
	var original_rot = camera.rotation_degrees
	var target_rot = original_rot + dir * kick_strength
	
	var tween = create_tween()
	# Kick rápido
	tween.tween_property(camera, "rotation_degrees", target_rot, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Retorno suave
	tween.tween_property(camera, "rotation_degrees", original_rot, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _lerp_degrees(from: Vector3, to: Vector3, weight: float) -> Vector3:
	return Vector3(
		rad_to_deg(lerp_angle(deg_to_rad(from.x), deg_to_rad(to.x), weight)),
		rad_to_deg(lerp_angle(deg_to_rad(from.y), deg_to_rad(to.y), weight)),
		rad_to_deg(lerp_angle(deg_to_rad(from.z), deg_to_rad(to.z), weight))
	)

func _normalize_degrees(rot: Vector3) -> Vector3:
	return Vector3(
		wrapf(rot.x, -180.0, 180.0),
		wrapf(rot.y, -180.0, 180.0),
		wrapf(rot.z, -180.0, 180.0)
	)

func _set_weapon_rotation_quat_weight(weight: float, from_rot: Vector3, to_rot: Vector3) -> void:
	var from_quat := _degrees_to_quat(from_rot)
	var to_quat := _degrees_to_quat(to_rot)
	weapon_pivot.quaternion = from_quat.slerp(to_quat, weight)

func _degrees_to_quat(rot_degrees: Vector3) -> Quaternion:
	var rot_radians := Vector3(
		deg_to_rad(rot_degrees.x),
		deg_to_rad(rot_degrees.y),
		deg_to_rad(rot_degrees.z)
	)
	return Quaternion.from_euler(rot_radians)

func _rotation_distance_degrees(from_rot: Vector3, to_rot: Vector3) -> float:
	var from_quat := _degrees_to_quat(_normalize_degrees(from_rot))
	var to_quat := _degrees_to_quat(_normalize_degrees(to_rot))
	return rad_to_deg(from_quat.angle_to(to_quat))

func _on_attack_impact_event(camera_kick_dir: Vector3) -> void:
	_apply_camera_feedback(camera_kick_dir)
	_check_hit()

func _on_attack_animation_finished_event(next_stance: int, final_pos: Vector3, final_rot: Vector3) -> void:
	is_attacking = false
	can_attack = true
	combat_ui.is_locked = false
	melee_ray.enabled = false
	current_stance_index = next_stance
	target_stance_pos = final_pos
	target_stance_rot = final_rot

func _get_next_stance_after_attack(current: int) -> int:
	match current:
		1: # TOP -> Move para baixo aleatoriamente
			return 3 if randf() > 0.5 else 4 # BOTTOM_RIGHT ou BOTTOM_LEFT
		2: # TOP_RIGHT -> BOTTOM_LEFT
			return 4
		3: # BOTTOM_RIGHT -> TOP_LEFT
			return 5
		4: # BOTTOM_LEFT -> TOP_RIGHT
			return 2
		5: # TOP_LEFT -> BOTTOM_RIGHT
			return 3
		_: # CENTER ou outros -> Mantém
			return current

func _check_hit() -> void:
	melee_ray.force_raycast_update()
	if melee_ray.is_colliding():
		var target = melee_ray.get_collider()
		print("Hit something: ", target.name)
		
		# Procurar por HealthComponent
		var health = target.get_node_or_null("HealthComponent")
		if not health and target.get_parent():
			health = target.get_parent().get_node_or_null("HealthComponent")
			
		if health:
			print("Dealing damage to ", target.name)
			health.take_damage(20)

func instantiate_weapon(weapon_scene: PackedScene) -> void:
	if current_weapon:
		current_weapon.queue_free()
	
	current_weapon = weapon_scene.instantiate()
	weapon_pivot.add_child(current_weapon)
	_on_combat_direction_changed(0) # Forçar postura inicial

func _on_combat_direction_changed(dir_index: int) -> void:
	if is_attacking or combat_ui.is_locked:
		return
	current_stance_index = dir_index
	target_stance_pos = STANCES[dir_index]["pos"]
	target_stance_rot = STANCES[dir_index]["rot"]

func _get_stable_target_rotation(current_rot: Vector3, target_rot: Vector3) -> Vector3:
	return Vector3(
		_closest_angle_degrees(current_rot.x, target_rot.x),
		_closest_angle_degrees(current_rot.y, target_rot.y),
		_closest_angle_degrees(current_rot.z, target_rot.z)
	)

func _closest_angle_degrees(current: float, target: float) -> float:
	var delta := wrapf(target - current, -180.0, 180.0)
	return current + delta
# endregion

# region --- Lógica de Movimento ---
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
	if ray.is_colliding():
		play_wall_bump_animation(direction)
		return

	is_moving = true
	var target_pos = global_position + direction.normalized() * Constants.TILE_SIZE
	
	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Movimento principal
	tween.tween_property(self, "global_position", target_pos, MOVE_DURATION)
	
	# Inclinação de Strafe (Tilt)
	if is_strafe:
		var target_tilt = deg_to_rad(-strafe_dir * TILT_AMOUNT)
		tween.tween_property(camera, "rotation:z", target_tilt, MOVE_DURATION * 0.5)
		tween.chain().tween_property(camera, "rotation:z", 0.0, MOVE_DURATION * 0.5)
	
	tween.chain().tween_callback(func(): is_moving = false)

func turn(angle_degrees: float) -> void:
	is_rotating = true
	var target_rot = rotation.y + deg_to_rad(angle_degrees)
	
	var tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Rotação principal
	tween.tween_property(self, "rotation:y", target_rot, ROTATE_DURATION)
	
	# Inclinação de Rotação (Sway)
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
# endregion

# region --- Efeitos Visuais ---
func handle_head_bob(delta: float) -> void:
	if is_moving:
		bob_time += delta * HEAD_BOB_FREQ
	else:
		bob_time = lerp(bob_time, 0.0, delta * 10.0) # Reset suave
		
	var target_y = base_camera_y + sin(bob_time) * HEAD_BOB_AMP
	camera.position.y = lerp(camera.position.y, target_y, delta * 20.0)
	
	var target_x = cos(bob_time * 0.5) * (HEAD_BOB_AMP * 0.5)
	camera.position.x = lerp(camera.position.x, target_x, delta * 20.0)

func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
# endregion

# region --- Callbacks e Sinais ---
func _on_died() -> void:
	print(player_name + " died!")
	queue_free()

func _on_health_changed() -> void:
	print("Cura recebida! HP: ", health_component.current_health)
	
func _on_take_damage() -> void:
	print("Dano recebido! HP: ", health_component.current_health)
# endregion
