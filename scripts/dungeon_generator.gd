extends Node3D

class Room:
	var x
	var y
	var w
	var h

	func _init(_x, _y, _w, _h):
		x = _x
		y = _y
		w = _w
		h = _h

	func center():
		return Vector2i(x + w / 2, y + h / 2)

	func intersects(other):
		return not (
			x + w < other.x or
			x > other.x + other.w or
			y + h < other.y or
			y > other.y + other.h
		)

var map = []
var rooms = []
var player_spawn_position: Vector3

@export var floor_scene: PackedScene
@export var wall_scene: PackedScene

func _ready():
	print("GERANDO DUNGEON...")
	randomize()

	create_map(30, 30)
	create_rooms()
	if rooms.size() == 0:
		push_error("Nenhuma sala gerada!")
		return
	build_level()
	build_walls()

func create_map(width, height):
	map.clear()
	for x in range(width):
		map.append([])
		for y in range(height):
			map[x].append(0)

func create_rooms():
	rooms.clear()
	var offset = (map.size() * Constants.TILE_SIZE) / 2

	for i in range(20):
		var w = randi_range(2, 4)
		var h = randi_range(2, 4)
		var x = randi_range(1, 15 - w - 1)
		var y = randi_range(1, 15 - h - 1)

		var new_room = Room.new(x, y, w, h)

		var failed = false
		for other in rooms:
			if new_room.intersects(other):
				failed = true
				break

		if not failed:
			carve_room(new_room)

			if rooms.size() > 0:
				connect_rooms(rooms[-1], new_room)

			rooms.append(new_room)
	
	if rooms.size() > 0:
		var first_room = rooms[0]
		var center = first_room.center()

		player_spawn_position = Vector3(
			center.x * Constants.TILE_SIZE - offset,
			1,
			center.y * Constants.TILE_SIZE - offset
		)
	
func carve_room(room):
	for x in range(room.x, room.x + room.w):
		for y in range(room.y, room.y + room.h):
			map[x][y] = 1
			
func connect_rooms(a, b):
	var a_center = a.center()
	var b_center = b.center()

	if randi() % 2 == 0:
		carve_h_corridor(a_center.x, b_center.x, a_center.y)
		carve_v_corridor(a_center.y, b_center.y, b_center.x)
	else:
		carve_v_corridor(a_center.y, b_center.y, a_center.x)
		carve_h_corridor(a_center.x, b_center.x, b_center.y)
		
func carve_h_corridor(x1, x2, y):
	for x in range(min(x1, x2), max(x1, x2) + 1):
		map[x][y] = 1

func carve_v_corridor(y1, y2, x):
	for y in range(min(y1, y2), max(y1, y2) + 1):
		map[x][y] = 1
		
func build_level():
	var count = 0
	var offset = (map.size() * Constants.TILE_SIZE) / 2

	for x in range(map.size()):
		for y in range(map[x].size()):
			if map[x][y] == 1:
				count += 1

				var tile = floor_scene.instantiate()
				tile.position = Vector3(
					x * Constants.TILE_SIZE - offset,
					0,
					y * Constants.TILE_SIZE - offset
				)
				add_child(tile)
	print("Tiles criados:", count)

func get_player_spawn_position() -> Vector3:
	return player_spawn_position

func build_walls():
	var tile_size = Constants.TILE_SIZE
	var half = tile_size / 2.0
	var offset = (map.size() * tile_size) / 2

	for x in range(map.size()):
		for y in range(map[x].size()):
			if map[x][y] != 1:
				continue

			var world_x = x * tile_size - offset
			var world_z = y * tile_size - offset

			# Norte
			if is_empty(x, y - 1):
				create_wall(Vector3(world_x, 0, world_z - half), 0)

			# Sul
			if is_empty(x, y + 1):
				create_wall(Vector3(world_x, 0, world_z + half), 180)

			# Oeste
			if is_empty(x - 1, y):
				create_wall(Vector3(world_x - half, 0, world_z), 90)

			# Leste
			if is_empty(x + 1, y):
				create_wall(Vector3(world_x + half, 0, world_z), -90)
				
func is_empty(x, y):
	if x < 0 or y < 0 or x >= map.size() or y >= map[x].size():
		return true

	return map[x][y] == 0
	
func create_wall(pos: Vector3, rot_y: float):
	var wall = wall_scene.instantiate()

	wall.position = pos
	wall.rotation.y = deg_to_rad(rot_y)
	print(wall.scale)
	add_child(wall)

func create_wall_at(pos: Vector3, rot_y_deg: float):
	var wall = wall_scene.instantiate()

	var wall_height = 3.0 # ou o tamanho do seu mesh

	wall.position = Vector3(
		pos.x,
		wall_height,
		pos.z
	)

	wall.rotation.y = deg_to_rad(rot_y_deg)

	add_child(wall)
