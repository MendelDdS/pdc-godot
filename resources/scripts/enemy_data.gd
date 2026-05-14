extends Resource
class_name EnemyData

@export var enemy_name: String = "Enemy"
@export var max_health: int = 100
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
