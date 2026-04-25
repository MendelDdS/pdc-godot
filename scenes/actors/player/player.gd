extends CharacterBody3D
class_name Player

# region --- Constantes e Configurações ---
const MOVE_DURATION: float = 0.35
const ROTATE_DURATION: float = 0.3
const HEAD_BOB_FREQ: float = 8.0
const HEAD_BOB_AMP: float = 0.08
const TILT_AMOUNT: float = 2.5 # Graus

# Configurações de Combate
const SWORD_SCENE = preload("res://scenes/actors/items/simple_sword.tscn")
const STANCES = {
	0: {"pos": Vector3(0.3, 0, -0.2), "rot": Vector3(-90, 0, 0)},    # CENTER (Meio)
	1: {"pos": Vector3(0, 0.1, -0.5), "rot": Vector3(-20, 0, 0)},     # TOP (Cima)
	2: {"pos": Vector3(0.3, 0, -0.4), "rot": Vector3(-20, -60, -40)},   # TOP_RIGHT (Cima-Direita)
	3: {"pos": Vector3(0.2, -0.2, -0.6), "rot": Vector3(-140, -60, -50)}, # BOTTOM_RIGHT (Baixo-Direita)
	4: {"pos": Vector3(-0.2, -0.2, -0.5), "rot": Vector3(-140, 40, 40)},  # BOTTOM_LEFT (Baixo-Esquerda)
	5: {"pos": Vector3(-0.3, 0, -0.4), "rot": Vector3(-50, 60, 40)}     # TOP_LEFT (Cima-Esquerda)
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
	if Input.is_action_just_pressed("Item Action"):
		perform_attack()

func update_weapon_stance(delta: float) -> void:
	if is_attacking:
		return
		
	var target_pos = target_stance_pos
	var target_rot = target_stance_rot
	
	if is_defending:
		target_pos = DEFENSE_STANCE["pos"]
		target_rot = DEFENSE_STANCE["rot"]
		
	# Interpolação de Posição
	weapon_pivot.position = weapon_pivot.position.lerp(target_pos, delta * 15.0)
	
	# Interpolação suave da rotação usando lerp_angle para evitar "saltos"
	var current_rot = weapon_pivot.rotation_degrees
	weapon_pivot.rotation_degrees.x = lerp_angle(deg_to_rad(current_rot.x), deg_to_rad(target_rot.x), delta * 15.0) * (180.0/PI)
	weapon_pivot.rotation_degrees.y = lerp_angle(deg_to_rad(current_rot.y), deg_to_rad(target_rot.y), delta * 15.0) * (180.0/PI)
	weapon_pivot.rotation_degrees.z = lerp_angle(deg_to_rad(current_rot.z), deg_to_rad(target_rot.z), delta * 15.0) * (180.0/PI)

func perform_attack() -> void:
	if is_attacking:
		return
		
	is_attacking = true
	
	# Usar posições de destino da postura como base para um bote consistente
	var original_pos = target_stance_pos
	var original_rot = target_stance_rot
	
	# Calcular destino do ataque baseado na postura
	var attack_pos = original_pos + Vector3(0, 0, -1.2) # Estocada padrão longa
	var attack_rot = original_rot
	
	match current_stance_index:
		1: # TOP -> Golpe descendente
			attack_pos = original_pos + Vector3(0, -0.6, -0.8)
			attack_rot.x -= 60
		2: # TOP_RIGHT -> Corte diagonal descendente
			attack_pos = original_pos + Vector3(-0.6, -0.4, -0.8)
			attack_rot.y += 45
		5: # TOP_LEFT -> Corte diagonal descendente
			attack_pos = original_pos + Vector3(0.6, -0.4, -0.8)
			attack_rot.y -= 45
		3: # BOTTOM_RIGHT -> Corte ascendente
			attack_pos = original_pos + Vector3(-0.5, 0.6, -0.8)
			attack_rot.x += 60
		4: # BOTTOM_LEFT -> Corte ascendente
			attack_pos = original_pos + Vector3(0.5, 0.6, -0.8)
			attack_rot.x += 60
	
	var tween = create_tween()
	
	# Ida do ataque (Rápida e linear)
	tween.tween_property(weapon_pivot, "position", attack_pos, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(weapon_pivot, "rotation_degrees", attack_rot, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Volta do ataque (Suave)
	tween.tween_property(weapon_pivot, "position", original_pos, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(weapon_pivot, "rotation_degrees", original_rot, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	tween.tween_callback(func(): is_attacking = false)

func instantiate_weapon(weapon_scene: PackedScene) -> void:
	if current_weapon:
		current_weapon.queue_free()
	
	current_weapon = weapon_scene.instantiate()
	weapon_pivot.add_child(current_weapon)
	_on_combat_direction_changed(0) # Forçar postura inicial

func _on_combat_direction_changed(dir_index: int) -> void:
	current_stance_index = dir_index
	target_stance_pos = STANCES[dir_index]["pos"]
	target_stance_rot = STANCES[dir_index]["rot"]
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
