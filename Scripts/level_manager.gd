extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  level_manager.gd  –  Autoload (LevelManager)
#  Se encarga de configurar los personajes (P1 y P2 en multijugador) cada vez
#  que se carga o transiciona a un nivel jugable (Node2D raíz).
# ─────────────────────────────────────────────────────────────────────────────

const PLAYER_NODE_NAMES := ["ninja_frog", "pink_man", "mask_dude", "virtual_guy"]

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	# Detectamos cuando se agrega una raíz de nivel jugable (Node2D hijo directo de /root)
	if not (node is Node2D):
		return
	if node.get_parent() != get_tree().root:
		return
	# Diferimos la ejecución para asegurar que todos los hijos de la escena estén listos
	_setup_players.call_deferred(node)


func _setup_players(level_root: Node) -> void:
	if not is_instance_valid(level_root):
		return

	# Sincronizar el mundo y nivel actual en GeneralRules desde la escena activa
	if level_root.scene_file_path != "":
		GeneralRules.sync_from_scene_path(level_root.scene_file_path)

	# 1. Buscar personajes plantilla preexistentes en la escena del nivel
	var template_players: Array[Node] = []
	for child in level_root.get_children():
		if child.name in PLAYER_NODE_NAMES or child.is_in_group("player"):
			template_players.append(child)

	# Si no hay personajes ni nodo Start, es un menú o escena no jugable
	if template_players.is_empty() and not level_root.has_node("Start"):
		return

	# ── Instanciar HUD (PlayerInfo) y Menú de Pausa automáticamente ───────────
	_spawn_hud(level_root)
	_spawn_pause_menu(level_root)

	# 2. Determinar punto de aparición inicial
	var spawn_pos := Vector2.ZERO
	if not template_players.is_empty() and template_players[0].global_position != Vector2.ZERO:
		spawn_pos = template_players[0].global_position
	elif level_root.has_node("Start"):
		var start_node = level_root.get_node("Start")
		spawn_pos = start_node.global_position + Vector2(0, -6)
	elif not template_players.is_empty():
		spawn_pos = template_players[0].global_position

	# 3. Conservar la cámara si algún personaje plantilla la tenía
	var cam_to_transfer: Camera2D = null
	for p in template_players:
		if p.has_node("Camera2D"):
			var cam: Camera2D = p.get_node("Camera2D")
			p.remove_child(cam)
			cam_to_transfer = cam
			break

	# 4. Eliminar limpiamente los personajes plantilla para evitar colisiones y duplicados
	for p in template_players:
		p.remove_from_group("player")
		p.queue_free()

	# ── Instanciar Jugador 1 ──────────────────────────────────────────────────
	var desired_p1: String = GeneralRules.selected_character
	if desired_p1.is_empty():
		desired_p1 = "ninja_frog"

	var p1_path: String = GeneralRules.CHARACTER_SCENES.get(desired_p1, "")
	if p1_path.is_empty():
		p1_path = "res://Scenes/Characters/ninja_frog.tscn"

	var p1_scene: PackedScene = load(p1_path)
	var p1: CharacterBody2D = p1_scene.instantiate()
	p1.name = desired_p1
	level_root.add_child(p1)
	p1.global_position = spawn_pos
	if p1.has_method("set_player_index"):
		p1.set_player_index(1)
	if p1.has_method("set_checkpoint"):
		p1.set_checkpoint(spawn_pos)

	if cam_to_transfer != null:
		# Si la escena ya incluía cámara en la plantilla, transferirla
		if p1.has_node("Camera2D"):
			p1.get_node("Camera2D").queue_free()
		p1.add_child(cam_to_transfer)
		cam_to_transfer.enabled = true

	# Configurar cámara de P1: fija al inicio en x=0, empieza a seguir cuando el jugador llega al centro
	var p1_cam: Camera2D = p1.get_node_or_null("Camera2D")
	if p1_cam != null:
		p1_cam.enabled = true
		p1_cam.limit_left = 0
		p1_cam.limit_top = 0
		p1_cam.limit_right = 6600
		p1_cam.limit_bottom = 648

	# ── Instanciar Jugador 2 en multijugador ───────────────────────────────────
	if not GeneralRules.is_multiplayer:
		return
	if GeneralRules.selected_character_p2.is_empty():
		return

	var desired_p2: String = GeneralRules.selected_character_p2
	var p2_path: String = GeneralRules.CHARACTER_SCENES.get(desired_p2, "")
	if p2_path.is_empty():
		return

	var p2_scene: PackedScene = load(p2_path)
	var p2: CharacterBody2D = p2_scene.instantiate()
	p2.name = desired_p2 + "_p2"
	level_root.add_child(p2)
	var p2_spawn: Vector2 = spawn_pos + Vector2(60, 0)
	p2.global_position = p2_spawn
	if p2.has_method("set_player_index"):
		p2.set_player_index(2)
	if p2.has_method("set_checkpoint"):
		p2.set_checkpoint(p2_spawn)

	# Desactivar la cámara de P2 para que la cámara principal siga al juego sin conflictos
	if p2.has_node("Camera2D"):
		p2.get_node("Camera2D").enabled = false


# ── Instanciar el HUD (PlayerInfo) automáticamente en niveles jugables ────────
func _spawn_hud(level_root: Node) -> void:
	# Evitar duplicados: si ya existe un PlayerInfo en el árbol, no crear otro
	for child in level_root.get_children():
		if child.name == "PlayerInfo":
			return

	var hud_path := "res://Scenes/Screens/PlayerInfo.tscn"
	if not ResourceLoader.exists(hud_path):
		return

	var hud_scene: PackedScene = load(hud_path)
	var hud := hud_scene.instantiate()
	hud.name = "PlayerInfo"
	level_root.add_child(hud)


# ── Instanciar el Menú de Pausa automáticamente en niveles jugables ──────────
func _spawn_pause_menu(level_root: Node) -> void:
	for child in level_root.get_children():
		if child.name == "PauseMenu":
			return

	var pause_path := "res://Scenes/Screens/pause_menu.tscn"
	if not ResourceLoader.exists(pause_path):
		return

	var pause_scene: PackedScene = load(pause_path)
	var pause_menu := pause_scene.instantiate()
	pause_menu.name = "PauseMenu"
	level_root.add_child(pause_menu)
