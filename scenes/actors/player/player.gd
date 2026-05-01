extends CharacterBody3D
class_name Player

# region --- Constantes e Configurações ---
const MOVE_DURATION: float = 0.35
const ROTATE_DURATION: float = 0.3
const HEAD_BOB_FREQ: float = 8.0
const HEAD_BOB_AMP: float = 0.08
const TILT_AMOUNT: float = 2.5 # Graus
const STANCE_TRANSITION_DURATION: float = 0.22
const STANCE_ROTATE_SPEED: float = 12.0
const STANCE_ARC_HEIGHT: float = 0.28
const BOTTOM_CROSS_TRANSITION_DURATION: float = 0.45
const BOTTOM_CROSS_ARC_HEIGHT: float = 0.85

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
var stance_transitioning: bool = false
var stance_from_index: int = 0
var stance_to_index: int = 0
var stance_origin_pos: Vector3 = Vector3.ZERO
var stance_origin_quat: Quaternion = Quaternion.IDENTITY
var stance_actual_start_pos: Vector3 = Vector3.ZERO
var stance_actual_start_quat: Quaternion = Quaternion.IDENTITY
var stance_transition_elapsed: float = 0.0

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
		
	# 1. Determinar Alvos Base (Defesa ou Postura Atual)
	var base_target_pos := target_stance_pos
	var base_target_quat := _degrees_to_quat(target_stance_rot)
	
	if is_defending:
		base_target_pos = DEFENSE_STANCE["pos"]
		base_target_quat = _degrees_to_quat(DEFENSE_STANCE["rot"])
		
	# 2. Processar Transição
	if stance_transitioning:
		var is_arc := _is_bottom_cross_transition(stance_from_index, stance_to_index) and not is_defending
		var duration := BOTTOM_CROSS_TRANSITION_DURATION if is_arc else STANCE_TRANSITION_DURATION
		stance_transition_elapsed += delta
		var progress := clampf(stance_transition_elapsed / duration, 0.0, 1.0)
		var eased_progress := _smooth_step(progress)
		
		# Transição em ARCO (Especial entre posições inferiores e NÃO defendendo)
		if is_arc:
			# Arco de Posição Estabilizado (usa origens fixas para o controle, mas interpola do ponto real)
			var fixed_origin: Vector3 = STANCES[stance_from_index]["pos"]
			var fixed_target: Vector3 = STANCES[stance_to_index]["pos"]
			var control: Vector3 = (fixed_origin + fixed_target) * 0.5 + Vector3(0.0, BOTTOM_CROSS_ARC_HEIGHT, 0.0)
			
			weapon_pivot.position = _quadratic_bezier(stance_actual_start_pos, control, base_target_pos, eased_progress)
			
			# Rotação em Arco via SLERP duplo (atravessa a postura TOP como ponto médio)
			# _slerp_short garante caminho curto e evita giro indesejado no eixo Y/Z
			var mid_quat := _degrees_to_quat(STANCES[1]["rot"])
			if eased_progress < 0.5:
				weapon_pivot.quaternion = _slerp_short(stance_actual_start_quat, mid_quat, eased_progress * 2.0)
			else:
				weapon_pivot.quaternion = _slerp_short(mid_quat, base_target_quat, (eased_progress - 0.5) * 2.0)
		else:
			# Transição Linear (Normal ou Defesa)
			weapon_pivot.position = stance_actual_start_pos.lerp(base_target_pos, eased_progress)
			weapon_pivot.quaternion = stance_actual_start_quat.slerp(base_target_quat, eased_progress)
			
		if progress >= 1.0:
			stance_transitioning = false
	else:
		# Estado Estático / Idle Follow
		weapon_pivot.position = base_target_pos
		var rot_weight := clampf(delta * STANCE_ROTATE_SPEED, 0.0, 1.0)
		weapon_pivot.quaternion = weapon_pivot.quaternion.slerp(base_target_quat, rot_weight)

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
	var stance_origin_quat: Quaternion = _degrees_to_quat(STANCES[attack_from_stance]["rot"])
	weapon_pivot.position = stance_origin_pos
	weapon_pivot.quaternion = stance_origin_quat
	
	# Usa a pose atual real como origem
	var original_pos = weapon_pivot.position
	var original_quat = weapon_pivot.quaternion
	var final_pos = STANCES[next_stance]["pos"]
	var final_quat = _degrees_to_quat(STANCES[next_stance]["rot"])
	
	# 2. Calcular parâmetros de impacto
	var is_thrust = (attack_from_stance == 0)
	var lunge_z = -2.5 if is_thrust else -0.7 
	
	var lerp_weight = 0.5 
	var attack_pos = original_pos.lerp(final_pos, lerp_weight) + Vector3(0, 0, lunge_z)
	var attack_quat = original_quat.slerp(final_quat, lerp_weight)
	
	# Antecipação (Recuo antes do golpe)
	var windup_lerp = 0.25
	var windup_pos = original_pos.lerp(final_pos, windup_lerp) + Vector3(0, 0.05, 0.15)
	# Adiciona um pequeno "tilt" de recuo na rotação
	var windup_tilt = Quaternion(Vector3(1, 0, 0), deg_to_rad(8.0))
	var windup_quat = (original_quat.slerp(final_quat, windup_lerp)) * windup_tilt
	
	# Ajustes de impacto baseados na postura inicial
	var camera_kick_dir = Vector3.ZERO
	match attack_from_stance:
		1: # TOP -> Corte descendente pesado
			attack_pos.y -= 0.45
			var edge_tilt = Quaternion(Vector3(1, 0, 1), deg_to_rad(25.0))
			attack_quat = attack_quat * edge_tilt
			camera_kick_dir = Vector3(1.2, 0.2, 0)
		2, 3: # RIGHT SIDES
			var edge_tilt = Quaternion(Vector3(0, 0, 1), deg_to_rad(-15.0))
			attack_quat = attack_quat * edge_tilt
			camera_kick_dir = Vector3(0, 1, -0.5)
		4, 5: # LEFT SIDES
			var edge_tilt = Quaternion(Vector3(0, 0, 1), deg_to_rad(15.0))
			attack_quat = attack_quat * edge_tilt
			camera_kick_dir = Vector3(0, -1, 0.5)
		0: # CENTER -> Estocada
			windup_pos = original_pos + Vector3(0, 0, 0.4)
			attack_pos = original_pos + Vector3(0, 0, -2.5)
			camera_kick_dir = Vector3(0.8, 0, 0)

	# Segurança de trajetória
	var max_allowed_pullback_z: float = original_pos.z + 0.08
	var min_required_lunge_z: float = original_pos.z - (2.5 if is_thrust else 0.35)
	windup_pos.z = min(windup_pos.z, max_allowed_pullback_z)
	attack_pos.z = min(attack_pos.z, min_required_lunge_z)
	
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

func _apply_camera_feedback(dir: Vector3) -> void:
	var kick_strength = 2.0
	var original_rot = camera.rotation_degrees
	var target_rot = original_rot + dir * kick_strength
	
	var tween = create_tween()
	# Kick rápido
	tween.tween_property(camera, "rotation_degrees", target_rot, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Retorno suave
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
		
	stance_from_index = current_stance_index
	stance_to_index = dir_index
	
	# Captura o estado REAL de onde estamos saindo (pode ser mid-air)
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

# Garante que o SLERP sempre toma o caminho mais curto,
# evitando rotações inesperadas quando quaternions são quase opostos (ex: Z=+180 vs Z=-180).
func _slerp_short(from: Quaternion, to: Quaternion, weight: float) -> Quaternion:
	if from.dot(to) < 0.0:
		to = -to
	return from.slerp(to, weight)

func _is_bottom_cross_transition(from_index: int, to_index: int) -> bool:
	return (
		(from_index == 4 and to_index == 3) or
		(from_index == 3 and to_index == 4)
	)
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
