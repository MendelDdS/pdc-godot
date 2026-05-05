extends Node3D
class_name Weapon

@export var weapon_name: String = "Simple Sword"
@export_enum("Sword", "Staff") var weapon_kind: String = "Sword"
@export var attack_damage_range: Vector2i = Vector2i(2, 5)
@export var critical_attack_damage_range: Vector2i = Vector2i(6, 10)
@export var magic_range: float = 18.0
@export var texture_path: String = "res://assets/weapons/knight_texture.png"
@export var is_pickup: bool = false
@export var pickup_float_height: float = 1.0
@export var pickup_bob_height: float = 0.15
@export var pickup_spin_speed: float = 90.0

var pickup_origin_y: float = 0.0
var pickup_time: float = 0.0

func _ready() -> void:
	set_pickup_enabled(is_pickup)
	var mesh_instance := _find_first_mesh_instance(self)
	if mesh_instance == null:
		return

	if texture_path.is_empty():
		return

	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_warning("%s: nao foi possivel carregar a textura em %s" % [weapon_name, texture_path])
		return

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.metallic = 0.0
	material.roughness = 0.5
	mesh_instance.material_override = material

func _process(delta: float) -> void:
	if not is_pickup:
		return

	pickup_time += delta
	position.y = pickup_origin_y + sin(pickup_time * 3.0) * pickup_bob_height
	rotation_degrees.y += pickup_spin_speed * delta

func set_pickup_enabled(value: bool) -> void:
	is_pickup = value
	if is_pickup:
		add_to_group("weapon_pickups")
		pickup_origin_y = position.y + pickup_float_height
		position.y = pickup_origin_y
	else:
		remove_from_group("weapon_pickups")
		pickup_time = 0.0

func get_weapon_scene() -> PackedScene:
	return load(scene_file_path) as PackedScene

func roll_attack_damage() -> int:
	return randi_range(attack_damage_range.x, attack_damage_range.y)

func roll_critical_attack_damage() -> int:
	return randi_range(critical_attack_damage_range.x, critical_attack_damage_range.y)

func get_magic_range() -> float:
	return magic_range

func get_weapon_kind() -> String:
	return weapon_kind

func is_sword() -> bool:
	return weapon_kind == "Sword"

func is_staff() -> bool:
	return weapon_kind == "Staff"

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D

	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found

	return null
