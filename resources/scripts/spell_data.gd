extends Resource
class_name SpellData

@export var spell_name: String = "Spell"
@export var pattern: Array[int] = []
@export var mana_cost: float = 20.0
@export var damage_range: Vector2i = Vector2i(2, 5)
@export var critical_damage_range: Vector2i = Vector2i(6, 10)
@export var spell_range: float = 18.0
@export var critical_max_time: float = 0.3

func roll_damage(critical: bool = false) -> int:
	var damage := critical_damage_range if critical else damage_range
	return randi_range(damage.x, damage.y)
