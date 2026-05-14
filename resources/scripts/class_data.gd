extends Resource
class_name ClassData

@export var display_name: String = "Class"
@export_enum("Warrior", "Mage") var class_kind: String = "Warrior"
@export var starting_weapon_scene: PackedScene
@export var strength: int = 10
@export var dexterity: int = 10
@export var vigor: int = 10
@export var intelligence: int = 10
