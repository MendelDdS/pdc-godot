extends Control
class_name CombatUI

signal direction_changed(new_direction: int)

enum Direction { CENTER, TOP, TOP_RIGHT, BOTTOM_RIGHT, BOTTOM_LEFT, TOP_LEFT }

@onready var points = {
	Direction.CENTER: $Center,
	Direction.TOP: $Top,
	Direction.TOP_RIGHT: $TopRight,
	Direction.BOTTOM_RIGHT: $BottomRight,
	Direction.BOTTOM_LEFT: $BottomLeft,
	Direction.TOP_LEFT: $TopLeft
}

var current_direction: int = Direction.CENTER
var virtual_mouse_pos: Vector2 = Vector2.ZERO
var center_threshold: float = 30.0
var max_distance: float = 100.0
var mouse_sensitivity: float = 1 # Ajuste este valor para diminuir a sensibilidade
var is_locked: bool = false
var magic_trace: Array[int] = []

func _ready() -> void:
	update_visuals()

func _draw() -> void:
	if magic_trace.size() < 2:
		return

	for i in range(magic_trace.size() - 1):
		draw_line(
			_get_point_center(magic_trace[i]),
			_get_point_center(magic_trace[i + 1]),
			Color(0.35, 0.75, 1.0, 0.95),
			4.0,
			true
		)

func set_magic_trace(trace: Array[int]) -> void:
	magic_trace = trace.duplicate()
	queue_redraw()

func clear_magic_trace() -> void:
	magic_trace.clear()
	queue_redraw()

func _get_point_center(dir: int) -> Vector2:
	var point = points.get(dir)
	if point == null:
		return Vector2.ZERO

	return point.position + point.size * 0.5

func handle_mouse_movement(relative_mouse: Vector2) -> void:
	if is_locked:
		return
	
	virtual_mouse_pos += relative_mouse * mouse_sensitivity
	
	# Limit mouse distance
	virtual_mouse_pos = virtual_mouse_pos.limit_length(max_distance)
	
	$Cursor.position = virtual_mouse_pos - ($Cursor.size / 2)
	
	var new_dir = calculate_direction(virtual_mouse_pos)
	if new_dir != current_direction:
		current_direction = new_dir
		direction_changed.emit(current_direction)
		update_visuals()

func calculate_direction(pos: Vector2) -> int:
	if pos.length() < center_threshold:
		return Direction.CENTER
	
	# atan2 retorna o ângulo em radianos (-PI a PI)
	# No Godot, 0 rad é para a direita (X+)
	# Queremos o topo como referência
	var angle = pos.angle() # radianos
	var deg = rad_to_deg(angle) + 90 # Rotaciona para que Top seja 0
	
	if deg < 0: deg += 360
	if deg >= 360: deg -= 360
	
	# Divide em 5 fatias de 72 graus
	if deg >= 324 or deg < 36: return Direction.TOP
	if deg >= 36 and deg < 108: return Direction.TOP_RIGHT
	if deg >= 108 and deg < 180: return Direction.BOTTOM_RIGHT
	if deg >= 180 and deg < 252: return Direction.BOTTOM_LEFT
	if deg >= 252 and deg < 324: return Direction.TOP_LEFT
	
	return Direction.CENTER

func update_visuals() -> void:
	for dir in points:
		var node = points[dir]
		if dir == current_direction:
			node.modulate = Color.RED
			node.scale = Vector2(1.2, 1.2)
		else:
			node.modulate = Color.WHITE
			node.scale = Vector2(1.0, 1.0)

func set_direction(dir: int) -> void:
	if dir == current_direction:
		return
		
	current_direction = dir
	update_visuals()
	
	# Atualizar virtual_mouse_pos para manter a consistência
	match dir:
		Direction.CENTER:
			virtual_mouse_pos = Vector2.ZERO
		Direction.TOP:
			virtual_mouse_pos = Vector2(0, -max_distance * 0.8)
		Direction.TOP_RIGHT:
			virtual_mouse_pos = Vector2.from_angle(deg_to_rad(72 - 90)) * max_distance * 0.8
		Direction.BOTTOM_RIGHT:
			virtual_mouse_pos = Vector2.from_angle(deg_to_rad(144 - 90)) * max_distance * 0.8
		Direction.BOTTOM_LEFT:
			virtual_mouse_pos = Vector2.from_angle(deg_to_rad(216 - 90)) * max_distance * 0.8
		Direction.TOP_LEFT:
			virtual_mouse_pos = Vector2.from_angle(deg_to_rad(288 - 90)) * max_distance * 0.8
	
	# Atualizar posição visual do cursor
	$Cursor.position = virtual_mouse_pos - ($Cursor.size / 2)
