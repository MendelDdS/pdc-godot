extends CharacterBody3D
class_name Player

# --- Constantes e Configurações ---
const MOVE_DURATION: float = 0.35
const ROTATE_DURATION: float = 0.3
const HEAD_BOB_FREQ: float = 8.0
const HEAD_BOB_AMP: float = 0.08
const TILT_AMOUNT: float = 2.5 # Graus

# --- Referências de Nós ---
@onready var health_component: HealthComponent = $HealthComponent
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var forward_ray: RayCast3D = $ForwardRay
@onready var back_ray: RayCast3D = $BackRay
@onready var left_ray: RayCast3D = $LeftRay
@onready var right_ray: RayCast3D = $RightRay

# --- Estado ---
var player_name: String = "Mendel"
var is_moving: bool = false
var is_rotating: bool = false
var bob_time: float = 0.0
var base_camera_y: float = 0.0

func _ready() -> void:
	print("Character created: " + player_name)
	base_camera_y = camera.position.y
	
	health_component.entity_died.connect(_on_died)
	health_component.healing.connect(_on_health_changed)
	health_component.damage_taken.connect(_on_take_damage)

func _process(delta: float) -> void:
	handle_head_bob(delta)
	handle_movement_input()

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

func _input(_event: InputEvent) -> void:
	# Ações não contínuas podem ser tratadas aqui se necessário
	pass

# --- Lógica de Movimento ---

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

# --- Efeitos Visuais ---

func handle_head_bob(delta: float) -> void:
	if is_moving:
		bob_time += delta * HEAD_BOB_FREQ
	else:
		bob_time = lerp(bob_time, 0.0, delta * 10.0) # Reset suave
		
	var target_y = base_camera_y + sin(bob_time) * HEAD_BOB_AMP
	camera.position.y = lerp(camera.position.y, target_y, delta * 20.0)
	
	# Adiciona um leve balanço horizontal também
	var target_x = cos(bob_time * 0.5) * (HEAD_BOB_AMP * 0.5)
	camera.position.x = lerp(camera.position.x, target_x, delta * 20.0)

func play_wall_bump_animation(direction: Vector3) -> void:
	is_moving = true
	var original_pos = global_position
	var bump_pos = original_pos + direction.normalized() * (Constants.TILE_SIZE * 0.1)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", bump_pos, 0.1)
	tween.tween_property(self, "global_position", original_pos, 0.1)
	tween.tween_callback(func(): is_moving = false)

# --- Callbacks de Vida ---

func _on_died():
	print(player_name + " died!")
	queue_free()

func _on_health_changed():
	print("Boa! ", health_component.current_health)
	
func _on_take_damage():
	print("AI! ", health_component.current_health)
