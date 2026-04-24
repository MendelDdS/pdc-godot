extends Node

@onready var level_container = $LevelContainer
@onready var player: Player = $Player

var current_level: Node3D

func _ready():
	load_level("res://scenes/levels/dungeon_entrance.tscn")

func load_level(path: String):
	if current_level:
		current_level.queue_free()

	current_level = load(path).instantiate()
	level_container.add_child(current_level)
#
	await get_tree().process_frame
#
	var spawn_pos = current_level.get_node("PlayerSpawn").position
	#var spawn_pos = generator.get_player_spawn_position()

	player.global_position = spawn_pos
