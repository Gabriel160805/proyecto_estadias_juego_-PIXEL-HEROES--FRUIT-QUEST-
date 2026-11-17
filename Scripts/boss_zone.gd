extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  boss_zone.gd
#  - La sala del jefe tiene DOS muros (izquierdo y derecho) en el TileMap "block".
#  - Al inicio ambos muros están ocultos (los huecos están abiertos).
#  - Cuando el jugador entra a la sala por cualquier lado, AMBOS muros se
#    cierran y la pelea comienza de inmediato.
#  - Al vencer al jefe, ambos muros se abren y el jugador puede salir.
#  - Si el jugador muere, se resetea la zona para poder volver a intentar.
# ─────────────────────────────────────────────────────────────────────────────

@export_group("Límites de Cámara de la Habitación")
@export var auto_calculate_camera_limits: bool = true
@export var custom_limit_left: int = 5440
@export var custom_limit_right: int = 6592
@export var custom_limit_top: int = 0
@export var custom_limit_bottom: int = 648

var _block: TileMap = null
var _triggered: bool = false
var _boss_defeated: bool = false

# Muros físicos (uno para cada lado)
var _left_wall_body: StaticBody2D = null
var _left_wall_shape: CollisionShape2D = null
var _right_wall_body: StaticBody2D = null
var _right_wall_shape: CollisionShape2D = null

# Trigger que cubre toda la sala
var _trigger_area: Area2D = null

# Referencias para la cámara
var _active_camera: Camera2D = null
var _orig_limit_left: int = 0
var _orig_limit_right: int = 6600
var _orig_limit_top: int = 0
var _orig_limit_bottom: int = 648

var _room_left: int = 5440
var _room_right: int = 6592
var _room_top: int = 0
var _room_bottom: int = 648

func _ready() -> void:
	add_to_group("boss_zone_controller")

	# Buscar el TileMap del grupo "block"
	_block = _find_child_in_group("block")
	if _block == null:
		push_warning("boss_zone: No se encontró un TileMap en el grupo 'block'")
		return

	# Ocultar visualmente y desactivar capas del TileMap al inicio (muros abiertos)
	_block.visible = false
	for layer_idx: int in _block.get_layers_count():
		_block.set_layer_enabled(layer_idx, false)

	# Calcular dimensiones de la habitación para la cámara
	if auto_calculate_camera_limits:
		_calculate_room_bounds()
	else:
		_room_left = custom_limit_left
		_room_right = custom_limit_right
		_room_top = custom_limit_top
		_room_bottom = custom_limit_bottom

	# Crear los muros físicos y el trigger de entrada
	_setup_walls_and_trigger()


func _process(_delta: float) -> void:
	if not _triggered or _boss_defeated:
		return

	# Si el jugador murió y reaparece fuera de la habitación del jefe, resetear la zona
	var any_alive_in_room: bool = false
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	for p: Node in players:
		if p is CharacterBody2D:
			var is_dead: bool = p.get("is_dead") if "is_dead" in p else false
			if not is_dead:
				var px: float = p.global_position.x
				# Considerar "dentro de la sala" si está entre los muros (con margen)
				if px >= (_room_left - 64.0) and px <= (_room_right + 64.0):
					any_alive_in_room = true
					break

	if not any_alive_in_room and players.size() > 0:
		_reset_boss_zone()


func _find_child_in_group(group_name: String) -> TileMap:
	for child: Node in get_children():
		if child is TileMap and child.is_in_group(group_name):
			return child
	return null


func _calculate_room_bounds() -> void:
	var general_tile: TileMap = _find_child_in_group("boss_zone")
	if general_tile != null:
		var used_rect: Rect2i = general_tile.get_used_rect()
		var tile_size: Vector2 = Vector2(general_tile.tile_set.tile_size) * general_tile.scale
		var room_pos: Vector2 = general_tile.global_position + Vector2(used_rect.position) * tile_size
		var room_size: Vector2 = Vector2(used_rect.size) * tile_size

		_room_left = int(room_pos.x)
		_room_right = int(room_pos.x + maxf(room_size.x, 1152.0))
		_room_top = int(room_pos.y)
		_room_bottom = int(room_pos.y + 648.0)
	else:
		_room_left = custom_limit_left
		_room_right = custom_limit_right
		_room_top = custom_limit_top
		_room_bottom = custom_limit_bottom


func _setup_walls_and_trigger() -> void:
	# ─── Analizar las celdas del TileMap "block" para encontrar 2 muros ───
	var used_rect: Rect2i = _block.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		push_warning("boss_zone: El TileMap 'block' no tiene celdas pintadas")
		return

	var tile_size: Vector2 = Vector2(_block.tile_set.tile_size) * _block.scale

	# Recopilar todas las columnas X que tienen tiles pintados
	var columns: Dictionary = {}  # x_tile -> array de y_tiles
	for y: int in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
		for x: int in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
			var cell_coords := Vector2i(x, y)
			if _block.get_cell_source_id(0, cell_coords) != -1:
				if not columns.has(x):
					columns[x] = []
				columns[x].append(y)

	if columns.is_empty():
		push_warning("boss_zone: No se encontraron celdas en 'block'")
		return

	# Obtener las X ordenadas y separar en dos grupos (izquierdo y derecho)
	var x_keys: Array = columns.keys()
	x_keys.sort()

	var left_cols: Array = []
	var right_cols: Array = []

	if x_keys.size() >= 2:
		# Buscar el "gap" más grande entre columnas consecutivas
		var max_gap: int = 0
		var gap_index: int = 0
		for i: int in range(1, x_keys.size()):
			var gap: int = x_keys[i] - x_keys[i - 1]
			if gap > max_gap:
				max_gap = gap
				gap_index = i

		if max_gap > 2:
			# Hay un hueco significativo: dos muros separados
			for i: int in range(0, gap_index):
				left_cols.append(x_keys[i])
			for i: int in range(gap_index, x_keys.size()):
				right_cols.append(x_keys[i])
		else:
			# Todas las columnas están juntas: un solo muro (comportamiento legacy)
			left_cols = x_keys.duplicate()
	else:
		left_cols = x_keys.duplicate()

	# ─── Calcular posición y tamaño de cada muro en píxeles ───
	var all_ys: Array = []
	for x_key: int in x_keys:
		for y_val: int in columns[x_key]:
			if not all_ys.has(y_val):
				all_ys.append(y_val)
	all_ys.sort()

	var min_y: int = all_ys[0]
	var max_y: int = all_ys[all_ys.size() - 1]
	var wall_height: float = float(max_y - min_y + 1) * tile_size.y

	# Crear muro izquierdo
	if left_cols.size() > 0:
		var lx_min: int = left_cols[0]
		var lx_max: int = left_cols[left_cols.size() - 1]
		var lw: float = float(lx_max - lx_min + 1) * tile_size.x
		var left_pos: Vector2 = _block.position + Vector2(float(lx_min), float(min_y)) * tile_size
		var left_center: Vector2 = left_pos + Vector2(lw / 2.0, wall_height / 2.0)

		_left_wall_body = StaticBody2D.new()
		_left_wall_body.name = "LeftWallPhysics"
		_left_wall_body.position = left_center
		_left_wall_body.collision_layer = 1
		_left_wall_body.collision_mask = 1

		_left_wall_shape = CollisionShape2D.new()
		var left_rect := RectangleShape2D.new()
		left_rect.size = Vector2(lw, wall_height)
		_left_wall_shape.shape = left_rect
		_left_wall_shape.disabled = true  # Muro abierto al inicio
		_left_wall_body.add_child(_left_wall_shape)
		add_child(_left_wall_body)

	# Crear muro derecho (si existe)
	if right_cols.size() > 0:
		var rx_min: int = right_cols[0]
		var rx_max: int = right_cols[right_cols.size() - 1]
		var rw: float = float(rx_max - rx_min + 1) * tile_size.x
		var right_pos: Vector2 = _block.position + Vector2(float(rx_min), float(min_y)) * tile_size
		var right_center: Vector2 = right_pos + Vector2(rw / 2.0, wall_height / 2.0)

		_right_wall_body = StaticBody2D.new()
		_right_wall_body.name = "RightWallPhysics"
		_right_wall_body.position = right_center
		_right_wall_body.collision_layer = 1
		_right_wall_body.collision_mask = 1

		_right_wall_shape = CollisionShape2D.new()
		var right_rect := RectangleShape2D.new()
		right_rect.size = Vector2(rw, wall_height)
		_right_wall_shape.shape = right_rect
		_right_wall_shape.disabled = true  # Muro abierto al inicio
		_right_wall_body.add_child(_right_wall_shape)
		add_child(_right_wall_body)

	# ─── Crear Area2D de detección que cubre TODA la sala ───
	# Se extiende un poco adentro de cada muro para detectar al jugador
	# justo cuando entra por el hueco
	var trigger_left: float = _block.position.x + float(left_cols[0]) * tile_size.x + (float(left_cols.size()) * tile_size.x) + 8.0
	var trigger_right: float
	if right_cols.size() > 0:
		trigger_right = _block.position.x + float(right_cols[0]) * tile_size.x - 8.0
	else:
		trigger_right = float(_room_right)

	var trigger_center_x: float = (trigger_left + trigger_right) / 2.0
	var trigger_width: float = trigger_right - trigger_left
	var trigger_center_y: float = _block.position.y + float(min_y) * tile_size.y + wall_height / 2.0

	_trigger_area = Area2D.new()
	_trigger_area.name = "BossZoneTrigger"
	_trigger_area.position = Vector2(trigger_center_x, trigger_center_y)
	_trigger_area.collision_layer = 0
	_trigger_area.collision_mask = 0xFFFFFFFF
	_trigger_area.monitoring = true

	var trigger_shape := CollisionShape2D.new()
	var trigger_rect := RectangleShape2D.new()
	# Altura generosa para cubrir todo el hueco de entrada
	var trigger_height: float = maxf(wall_height + 400.0, 1000.0)
	trigger_rect.size = Vector2(trigger_width, trigger_height)
	trigger_shape.shape = trigger_rect
	_trigger_area.add_child(trigger_shape)

	add_child(_trigger_area)
	_trigger_area.body_entered.connect(_on_player_entered)


func _get_active_camera() -> Camera2D:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		return cam
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p.has_node("Camera2D"):
			var c: Camera2D = p.get_node("Camera2D")
			if c.enabled:
				return c
	return null


func _on_player_entered(body: Node2D) -> void:
	if _triggered or _boss_defeated:
		return
	if not body.is_in_group("player") and not (body is CharacterBody2D):
		return

	_triggered = true

	# 1. Mostrar el TileMap visual (ambos muros aparecen)
	if _block:
		_block.visible = true
		for layer_idx: int in _block.get_layers_count():
			_block.set_layer_enabled(layer_idx, true)

	# 2. Activar colisión de AMBOS muros (cerrar los huecos)
	if _left_wall_shape and is_instance_valid(_left_wall_shape):
		_left_wall_shape.set_deferred("disabled", false)
	if _right_wall_shape and is_instance_valid(_right_wall_shape):
		_right_wall_shape.set_deferred("disabled", false)

	# 3. Desactivar el trigger mientras dura la pelea
	if _trigger_area and is_instance_valid(_trigger_area):
		_trigger_area.set_deferred("monitoring", false)

	# 4. Centrar y bloquear la cámara en la habitación del jefe
	_lock_camera_to_boss_room()

	# 5. Activar la aparición del jefe
	_activate_boss()


func _lock_camera_to_boss_room() -> void:
	_active_camera = _get_active_camera()
	if _active_camera == null:
		return

	_orig_limit_left = _active_camera.limit_left
	_orig_limit_right = _active_camera.limit_right
	_orig_limit_top = _active_camera.limit_top
	_orig_limit_bottom = _active_camera.limit_bottom

	# Transición suave hacia los límites de la habitación del jefe
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_active_camera, "limit_left", _room_left, 0.7)
	tween.tween_property(_active_camera, "limit_right", _room_right, 0.7)
	tween.tween_property(_active_camera, "limit_top", _room_top, 0.7)
	tween.tween_property(_active_camera, "limit_bottom", _room_bottom, 0.7)


func _reset_boss_zone() -> void:
	_triggered = false

	# Restaurar los límites originales de la cámara
	if _active_camera and is_instance_valid(_active_camera):
		var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_active_camera, "limit_left", _orig_limit_left, 0.5)
		tween.tween_property(_active_camera, "limit_right", _orig_limit_right, 0.5)
		tween.tween_property(_active_camera, "limit_top", _orig_limit_top, 0.5)
		tween.tween_property(_active_camera, "limit_bottom", _orig_limit_bottom, 0.5)

	# Reabrir ambos muros
	_open_walls()

	# Reactivar el trigger para cuando el jugador vuelva a entrar
	if _trigger_area and is_instance_valid(_trigger_area):
		_trigger_area.set_deferred("monitoring", true)

	# Resetear el jefe para la próxima entrada
	_reset_boss()


func _activate_boss() -> void:
	for boss_name: String in ["boss_slime", "boss_bat", "boss_mimic", "boss_rat"]:
		var boss := get_node_or_null(boss_name)
		if boss != null and boss.has_method("activate_boss"):
			boss.activate_boss()
			return
	get_tree().call_group("boss", "activate_boss")


func _reset_boss() -> void:
	for boss_name: String in ["boss_slime", "boss_bat", "boss_mimic", "boss_rat"]:
		var boss := get_node_or_null(boss_name)
		if boss != null and boss.has_method("reset_boss"):
			boss.reset_boss()
			return
	get_tree().call_group("boss", "reset_boss")


# ─── Funciones auxiliares para abrir/cerrar muros ───

func _open_walls() -> void:
	# Ocultar TileMap visual
	if _block:
		_block.visible = false
		for layer_idx: int in _block.get_layers_count():
			_block.set_layer_enabled(layer_idx, false)

	# Desactivar colisión de ambos muros
	if _left_wall_shape and is_instance_valid(_left_wall_shape):
		_left_wall_shape.set_deferred("disabled", true)
	if _right_wall_shape and is_instance_valid(_right_wall_shape):
		_right_wall_shape.set_deferred("disabled", true)


# ─── Función llamada por los jefes al morir ───

func unlock_boss_zone() -> void:
	_triggered = false
	_boss_defeated = true

	# Restaurar los límites originales de la cámara
	if _active_camera and is_instance_valid(_active_camera):
		var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_active_camera, "limit_left", _orig_limit_left, 0.7)
		tween.tween_property(_active_camera, "limit_right", _orig_limit_right, 0.7)
		tween.tween_property(_active_camera, "limit_top", _orig_limit_top, 0.7)
		tween.tween_property(_active_camera, "limit_bottom", _orig_limit_bottom, 0.7)

	# Abrir ambos muros permanentemente
	_open_walls()

	# Desactivar el trigger para que no se vuelva a cerrar la sala
	if _trigger_area and is_instance_valid(_trigger_area):
		_trigger_area.set_deferred("monitoring", false)
