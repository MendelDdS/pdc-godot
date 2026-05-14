extends Resource
class_name WeaponData

@export var weapon_name: String = "Weapon"
@export_enum("Sword", "Staff") var weapon_kind: String = "Sword"
@export var attack_damage_range: Vector2i = Vector2i(2, 5)
@export var critical_attack_damage_range: Vector2i = Vector2i(6, 10)
@export var magic_range: float = 18.0
@export var texture_path: String = ""

func roll_attack_damage() -> int:
	return randi_range(attack_damage_range.x, attack_damage_range.y)

func roll_critical_attack_damage() -> int:
	return randi_range(critical_attack_damage_range.x, critical_attack_damage_range.y)
