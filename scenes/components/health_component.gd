extends Node
class_name HealthComponent

signal healing
signal damage_taken
signal entity_died

@export var max_health: int

var current_health: int = 100

func _ready() -> void:
	current_health = max_health
	
func take_damage(damage: int) -> void:
	current_health -= damage
	current_health = max(current_health, 0)
	print("Current Health", current_health)
	if current_health <= 0:
		emit_signal("entity_died")
	else: 
		emit_signal("damage_taken")

func heal_entity(value) -> void:
	current_health += value
	current_health = min(current_health, max_health)

	emit_signal("healing")

func die():
	print("It died! Rest in peace...")
