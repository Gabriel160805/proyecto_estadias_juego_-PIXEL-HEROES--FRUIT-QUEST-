extends Node

var applePoints = 1
var bananaPoints = 2
var cherryPoints = 3

# Selección de personaje y modo de juego
var selected_character: String = "ninja_frog"
var selected_character_p2: String = ""
var is_multiplayer: bool = false

# ── Sistema de Vidas y Puntos ─────────────────────────────────────────────────
var lives: int = 3
var total_fruit_points: int = 0
const LIVES_BONUS_THRESHOLD := 100   # +1 vida cada 100 puntos
const MAX_LIVES := 9
var _last_bonus_milestone: int = 0   # Último umbral en que se dio vida extra

# Añade puntos y otorga vida extra si se supera el umbral
func add_fruit_points(amount: int) -> void:
	total_fruit_points += amount
	if total_fruit_points > high_score:
		high_score = total_fruit_points
		save_game_data()
	var new_milestone := total_fruit_points / LIVES_BONUS_THRESHOLD
	if new_milestone > _last_bonus_milestone:
		var bonus := new_milestone - _last_bonus_milestone
		lives = mini(lives + bonus, MAX_LIVES)
		_last_bonus_milestone = new_milestone

# Reinicia las vidas y puntos (al iniciar una partida nueva)
func reset_run() -> void:
	lives = 3
	total_fruit_points = 0
	_last_bonus_milestone = 0

const CHARACTER_SCENES: Dictionary = {
	"ninja_frog": "res://Scenes/Characters/ninja_frog.tscn",
	"pink_man": "res://Scenes/Characters/pink_man.tscn",
	"mask_dude": "res://Scenes/Characters/mask_dude.tscn",
	"virtual_guy": "res://Scenes/Characters/virtual_guy.tscn"
}

const CHARACTER_NAMES: Dictionary = {
	"ninja_frog": "Ninja Frog",
	"pink_man": "Pink Man",
	"mask_dude": "Mask Dude",
	"virtual_guy": "Virtual Guy"
}

# ── Progresión de Mundos y Niveles (4 Mundos × 3 Niveles) ────────────────────
const MAX_WORLDS := 4
const LEVELS_PER_WORLD := 3

const SAVE_FILE_PATH := "user://save_data.json"

var max_unlocked_world: int = 1
var max_unlocked_level: int = 1
var high_score: int = 0

func _ready() -> void:
	load_game_data()

func save_game_data() -> void:
	var data := {
		"unlocked_world": max_unlocked_world,
		"unlocked_level": max_unlocked_level,
		"high_score": high_score
	}
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_game_data() -> void:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		max_unlocked_world = 1
		max_unlocked_level = 1
		high_score = 0
		return

	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file != null:
		var content := file.get_as_text()
		file.close()
		var json := JSON.new()
		if json.parse(content) == OK and json.data is Dictionary:
			var d: Dictionary = json.data
			max_unlocked_world = clampi(int(d.get("unlocked_world", 1)), 1, MAX_WORLDS)
			max_unlocked_level = clampi(int(d.get("unlocked_level", 1)), 1, LEVELS_PER_WORLD)
			high_score = int(d.get("high_score", 0))

func unlock_level(world: int, level: int) -> void:
	var changed := false
	if world > max_unlocked_world:
		max_unlocked_world = clampi(world, 1, MAX_WORLDS)
		max_unlocked_level = clampi(level, 1, LEVELS_PER_WORLD)
		changed = true
	elif world == max_unlocked_world and level > max_unlocked_level:
		max_unlocked_level = clampi(level, 1, LEVELS_PER_WORLD)
		changed = true

	if changed:
		save_game_data()

func is_level_unlocked(world: int, level: int) -> bool:
	if world == 1 and level == 1:
		return true
	if world < max_unlocked_world:
		return true
	if world == max_unlocked_world:
		return level <= max_unlocked_level
	return false

var current_world: int = 1
var current_level: int = 1
var target_scene_path: String = ""

const WORLD_BACKGROUNDS: Dictionary = {
	1: "res://Assets/Background/Green.png",   # Mundo 1: Bosque Verde
	2: "res://Assets/Background/Brown.png",   # Mundo 2: Rocas / Caverna
	3: "res://Assets/Background/Blue.png",    # Mundo 3: Agua / Cielo
	4: "res://Assets/Background/Purple.png"   # Mundo 4: Noche / Místico
}

const WORLD_NAMES: Dictionary = {
	1: "BOSQUE DE VERANO",
	2: "TIERRAS ROCOSAS",
	3: "VALLE CELESTE",
	4: "CASTILLO OSCURO"
}


# Resuelve un UID (uid://...) o ruta a su ruta de archivo real (res://...)
func resolve_scene_path(path: String) -> String:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
			var resolved := ResourceUID.get_id_path(id)
			if not resolved.is_empty():
				return resolved
		if ResourceLoader.exists(path):
			var res = ResourceLoader.load(path)
			if res != null and not res.resource_path.is_empty():
				return res.resource_path
	return path


# Extrae el número de mundo y nivel a partir del nombre o ruta de una escena
func extract_world_and_level(path: String) -> Vector2i:
	var resolved := resolve_scene_path(path)
	var regex := RegEx.new()
	regex.compile("(?i)level_?(\\d+)_(\\d+)")
	var result := regex.search(resolved)
	if result:
		return Vector2i(result.get_string(1).to_int(), result.get_string(2).to_int())
	return Vector2i(0, 0)


# Sincroniza el mundo y nivel actual en base a la escena cargada
func sync_from_scene_path(path: String) -> void:
	var coords := extract_world_and_level(path)
	if coords.x > 0 and coords.y > 0:
		current_world = coords.x
		current_level = coords.y


# Busca la ruta de la escena del nivel en base al mundo y nivel
func get_level_scene_path(world: int, level: int) -> String:
	var candidates: Array[String] = [
		"res://Scenes/Escenarios/Level_%d_%d.tscn" % [world, level],
		"res://Scenes/Escenarios/level_%d_%d.tscn" % [world, level],
		"res://Scenes/Screens/Level_%d_%d.tscn" % [world, level],
		"res://Scenes/Screens/level_%d_%d.tscn" % [world, level]
	]
	for path in candidates:
		if ResourceLoader.exists(path):
			return path
	return "res://Scenes/Escenarios/Level_%d_%d.tscn" % [world, level]


# Inicia el juego desde el Mundo 1, Nivel 1 mostrando la pantalla de transición
func start_game() -> void:
	reset_run()
	current_world = 1
	current_level = 1
	target_scene_path = get_level_scene_path(1, 1)
	get_tree().change_scene_to_file("res://Scenes/Screens/level_transition.tscn")


# Salta a un mundo y nivel específico pasando por la pantalla de transición
func go_to_level(world: int, level: int) -> void:
	current_world = clampi(world, 1, MAX_WORLDS)
	current_level = clampi(level, 1, LEVELS_PER_WORLD)
	target_scene_path = get_level_scene_path(current_world, current_level)
	get_tree().change_scene_to_file("res://Scenes/Screens/level_transition.tscn")


# Avanza al siguiente nivel en la secuencia (1_1 → 1_2 → 1_3 → 2_1 → 2_2 ...)
func advance_level() -> void:
	if current_level < LEVELS_PER_WORLD:
		current_level += 1
	elif current_world < MAX_WORLDS:
		current_world += 1
		current_level = 1
	else:
		# Se completó todo el juego
		current_world = MAX_WORLDS + 1
		current_level = 1

	if current_world <= MAX_WORLDS:
		unlock_level(current_world, current_level)

	target_scene_path = get_level_scene_path(current_world, current_level)
	get_tree().change_scene_to_file("res://Scenes/Screens/level_transition.tscn")


# Transiciona hacia una ruta de escena específica y detecta mundo/nivel del nombre
func transition_to_scene(scene_path: String) -> void:
	var resolved := resolve_scene_path(scene_path)
	var coords := extract_world_and_level(resolved)
	if coords.x > 0 and coords.y > 0:
		current_world = coords.x
		current_level = coords.y
	else:
		# Si no contiene números en el nombre, avanzamos el contador del nivel actual
		if current_level < LEVELS_PER_WORLD:
			current_level += 1
		elif current_world < MAX_WORLDS:
			current_world += 1
			current_level = 1

	if current_world <= MAX_WORLDS:
		unlock_level(current_world, current_level)

	target_scene_path = resolved
	get_tree().change_scene_to_file("res://Scenes/Screens/level_transition.tscn")
