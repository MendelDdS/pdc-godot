extends Node3D

const TILE_SIZE := Constants.TILE_SIZE
const FLOOR_THICKNESS := 0.16
const WALL_THICKNESS := 0.32
const WALL_HEIGHT := 6.4
const CEILING_Y := 6.4
const ACTOR_Y := 1.8

const DUNGEON_MAP := [
	"##########",
	"#P.E#...U#",
	"#.#.#.##.#",
	"#.#.E.#..#",
	"#.###.#E##",
	"#.E.#....#",
	"###.#.##.#",
	"#E..#..Q.#",
	"#...S....#",
	"##########"
]

@export var enemy_scene: PackedScene
@export var quality_sword_scene: PackedScene
@export var quality_staff_scene: PackedScene

var floor_material: StandardMaterial3D
var wall_material: StandardMaterial3D
var ceiling_material: StandardMaterial3D
var trim_material: StandardMaterial3D

@onready var player_spawn: Marker3D = $PlayerSpawn

func _ready() -> void:
	_setup_materials()
	_clear_generated_nodes()
	_build_containers()
	_build_static_geometry()
	_build_dynamic_content()
	_setup_lighting()

func _setup_materials() -> void:
	floor_material = _make_material(Color(0.22, 0.22, 0.20), 0.9, 0.0)
	wall_material = _make_material(Color(0.30, 0.29, 0.25), 0.82, 0.0)
	ceiling_material = _make_material(Color(0.10, 0.105, 0.11), 0.95, 0.0)
	trim_material = _make_material(Color(0.38, 0.30, 0.22), 0.75, 0.0)

func _make_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _clear_generated_nodes() -> void:
	for node_name in ["StaticGeometry", "Interactables", "Enemies", "Pickups", "Lighting"]:
		var node := get_node_or_null(node_name)
		if node != null:
			node.queue_free()

func _build_containers() -> void:
	for node_name in ["StaticGeometry", "Interactables", "Enemies", "Pickups", "Lighting"]:
		var container := Node3D.new()
		container.name = node_name
		add_child(container)

	for node_name in ["Floors", "Walls", "Ceilings"]:
		var container := Node3D.new()
		container.name = node_name
		$StaticGeometry.add_child(container)

func _build_static_geometry() -> void:
	for z in DUNGEON_MAP.size():
		for x in DUNGEON_MAP[z].length():
			if not _is_walkable_cell(x, z):
				continue

			var center := _cell_to_world(Vector2i(x, z), 0.0)
			_create_box("Floor_%s_%s" % [x, z], $StaticGeometry/Floors, center + Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0), Vector3(TILE_SIZE, FLOOR_THICKNESS, TILE_SIZE), floor_material, true)
			_create_box("Ceiling_%s_%s" % [x, z], $StaticGeometry/Ceilings, center + Vector3(0.0, CEILING_Y, 0.0), Vector3(TILE_SIZE, FLOOR_THICKNESS, TILE_SIZE), ceiling_material, true)
			_create_edge_walls(x, z)

func _create_edge_walls(x: int, z: int) -> void:
	var center := _cell_to_world(Vector2i(x, z), WALL_HEIGHT * 0.5)
	var half := TILE_SIZE * 0.5
	var dirs := [
		{"offset": Vector3(0.0, 0.0, -half), "size": Vector3(TILE_SIZE, WALL_HEIGHT, WALL_THICKNESS), "cell": Vector2i(x, z - 1), "name": "N"},
		{"offset": Vector3(0.0, 0.0, half), "size": Vector3(TILE_SIZE, WALL_HEIGHT, WALL_THICKNESS), "cell": Vector2i(x, z + 1), "name": "S"},
		{"offset": Vector3(-half, 0.0, 0.0), "size": Vector3(WALL_THICKNESS, WALL_HEIGHT, TILE_SIZE), "cell": Vector2i(x - 1, z), "name": "W"},
		{"offset": Vector3(half, 0.0, 0.0), "size": Vector3(WALL_THICKNESS, WALL_HEIGHT, TILE_SIZE), "cell": Vector2i(x + 1, z), "name": "E"}
	]

	for dir in dirs:
		if _is_walkable_cell(dir["cell"].x, dir["cell"].y):
			continue
		_create_box("Wall_%s_%s_%s" % [x, z, dir["name"]], $StaticGeometry/Walls, center + dir["offset"], dir["size"], wall_material, true)

func _build_dynamic_content() -> void:
	for z in DUNGEON_MAP.size():
		for x in DUNGEON_MAP[z].length():
			var marker := _get_cell_marker(x, z)
			var cell := Vector2i(x, z)
			match marker:
				"P":
					player_spawn.position = _cell_to_world(cell, ACTOR_Y)
				"E":
					_spawn_scene(enemy_scene, $Enemies, _cell_to_world(cell, ACTOR_Y), "Enemy")
				"Q":
					_spawn_scene(quality_sword_scene, $Pickups, _cell_to_world(cell, ACTOR_Y), "QualitySwordPickup")
				"S":
					_spawn_scene(quality_staff_scene, $Pickups, _cell_to_world(cell, ACTOR_Y), "QualityStaffPickup")
				"U":
					_create_stairs_marker(cell)

func _spawn_scene(scene: PackedScene, parent: Node, position: Vector3, node_name: String) -> Node:
	if scene == null:
		return null

	var instance := scene.instantiate()
	instance.name = node_name
	parent.add_child(instance)
	instance.global_position = position
	return instance

func _create_stairs_marker(cell: Vector2i) -> void:
	var parent := $Interactables
	var base_pos := _cell_to_world(cell, 0.18)
	for i in 5:
		_create_box(
			"StairsUp_%s" % i,
			parent,
			base_pos + Vector3(0.0, 0.12 + (i * 0.18), -1.55 + (i * 0.62)),
			Vector3(TILE_SIZE * 0.64, 0.22, 0.58),
			trim_material,
			false
		)

func _setup_lighting() -> void:
	var ambient := WorldEnvironment.new()
	ambient.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.015, 0.018)
	environment.ambient_light_color = Color(0.20, 0.20, 0.19)
	environment.ambient_light_energy = 0.52
	ambient.environment = environment
	$Lighting.add_child(ambient)

	for z in DUNGEON_MAP.size():
		for x in DUNGEON_MAP[z].length():
			if _get_cell_marker(x, z) != ".":
				continue
			if (x + z) % 5 != 0:
				continue
			var light := OmniLight3D.new()
			light.name = "TorchLight_%s_%s" % [x, z]
			light.light_color = Color(1.0, 0.56, 0.26)
			light.light_energy = 1.15
			light.omni_range = 9.0
			light.shadow_enabled = true
			$Lighting.add_child(light)
			light.position = _cell_to_world(Vector2i(x, z), 2.45)

func _create_box(node_name: String, parent: Node, position: Vector3, size: Vector3, material: Material, with_collision: bool) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	root.position = position

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	root.add_child(mesh_instance)

	if with_collision:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		root.add_child(body)

	return root

func _is_walkable_cell(x: int, z: int) -> bool:
	if z < 0 or z >= DUNGEON_MAP.size():
		return false
	if x < 0 or x >= DUNGEON_MAP[z].length():
		return false
	return _get_cell_marker(x, z) != "#"

func _cell_to_world(cell: Vector2i, y: float) -> Vector3:
	var half := TILE_SIZE * 0.5
	return Vector3((cell.x * TILE_SIZE) + half, y, (cell.y * TILE_SIZE) + half)

func _get_cell_marker(x: int, z: int) -> String:
	return DUNGEON_MAP[z].substr(x, 1)
