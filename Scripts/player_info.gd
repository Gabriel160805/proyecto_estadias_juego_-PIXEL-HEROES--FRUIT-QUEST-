extends CanvasLayer

# ─────────────────────────────────────────────────────────────────────────────
#  HUD – PlayerInfo
#  Muestra: Vidas | Timer | Puntos de Frutas | Barra de Vida
# ─────────────────────────────────────────────────────────────────────────────

const TIMER_SECONDS  := 100.0
const LOW_TIME_WARN  := 20.0       # Segundos restantes en que el timer se pone rojo
const ICON_SIZE      := 28         # Tamaño de cada ícono de vida (px)
const MAX_ICON_LIVES := 9          # Máximo de íconos mostrados
const HUD_HEIGHT     := 48         # Alto del panel HUD
const HUD_MARGIN     := 8

const CHAR_FOLDER: Dictionary = {
	"ninja_frog":   "Ninja Frog",
	"pink_man":     "Pink Man",
	"mask_dude":    "Mask Dude",
	"virtual_guy":  "Virtual Guy"
}

# ── Paleta ────────────────────────────────────────────────────────────────────
const COL_BG         := Color(0.05, 0.05, 0.10, 0.82)
const COL_PANEL      := Color(0.10, 0.10, 0.18, 0.90)
const COL_TEXT       := Color(1.00, 1.00, 1.00, 1.00)
const COL_TIME_OK    := Color(0.20, 1.00, 0.45, 1.00)
const COL_TIME_LOW   := Color(1.00, 0.25, 0.20, 1.00)
const COL_HP_FG      := Color(0.20, 0.85, 0.35, 1.00)
const COL_HP_BG      := Color(0.15, 0.15, 0.20, 1.00)
const COL_FRUIT      := Color(1.00, 0.85, 0.20, 1.00)
const COL_SEPARATOR  := Color(0.35, 0.35, 0.55, 0.70)

# ── Estado interno ─────────────────────────────────────────────────────────
var _timer_left: float = TIMER_SECONDS
var _timer_running: bool = false
var _dead_by_timer: bool = false
var _blink_acc: float = 0.0

# ── Referencias a nodos ────────────────────────────────────────────────────
var _life_icons: Array[TextureRect] = []
var _timer_label: Label
var _fruit_label: Label
var _hp_bar: ColorRect
var _hp_bar_fill: ColorRect

# ── Referencia al jugador principal ────────────────────────────────────────
@export var player: CharacterBody2D

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer = 10
	_build_ui()
	find_player()
	_refresh_life_icons()
	_timer_running = true

func _process(delta: float) -> void:
	if player == null:
		find_player()

	# Si el jugador murió por timer y ya revivió, reiniciar el timer
	if _dead_by_timer and player != null and not player.is_dead:
		reset_timer()

	_tick_timer(delta)
	_update_ui()

# ─────────────────────────────────────────────────────────────────────────────
#  Construcción de la UI por script
# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var vp_w := 1152
	var vp_h := 648

	# ── Panel de fondo completo ───────────────────────────────────────────────
	var panel := ColorRect.new()
	panel.name = "HUDPanel"
	panel.color = COL_BG
	panel.set_position(Vector2(0, 0))
	panel.set_size(Vector2(vp_w, HUD_HEIGHT))
	add_child(panel)

	# ── Sección IZQUIERDA: íconos de vida ─────────────────────────────────────
	var left_x := HUD_MARGIN
	var icon_y  := (HUD_HEIGHT - ICON_SIZE) / 2

	# Carga la textura de salto del personaje seleccionado
	var char_key = GeneralRules.selected_character
	var folder = CHAR_FOLDER.get(char_key, "Ninja Frog")
	var tex_path := "res://Assets/Main Characters/%s/Jump (32x32).png" % folder
	var base_tex: Texture2D = null
	if ResourceLoader.exists(tex_path):
		base_tex = load(tex_path)

	for i in MAX_ICON_LIVES:
		var tr := TextureRect.new()
		tr.name = "LifeIcon%d" % i
		tr.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_position(Vector2(left_x + i * (ICON_SIZE + 3), icon_y))
		tr.set_size(Vector2(ICON_SIZE, ICON_SIZE))
		if base_tex != null:
			var atlas := AtlasTexture.new()
			atlas.atlas = base_tex
			atlas.region = Rect2(0, 0, 32, 32)
			tr.texture = atlas
		tr.modulate = Color(1, 1, 1, 0)   # Oculto hasta que _refresh_life_icons lo muestre
		panel.add_child(tr)
		_life_icons.append(tr)

	# ── CENTRO: Timer ─────────────────────────────────────────────────────────
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.text = "1:40"
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", COL_TIME_OK)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.set_position(Vector2(vp_w / 2 - 60, 0))
	_timer_label.set_size(Vector2(120, HUD_HEIGHT))
	panel.add_child(_timer_label)

	# Ícono de reloj (emoji como texto, o símbolo simple)
	var clock_icon := Label.new()
	clock_icon.name = "ClockIcon"
	clock_icon.text = "⏱"
	clock_icon.add_theme_font_size_override("font_size", 18)
	clock_icon.add_theme_color_override("font_color", COL_TEXT)
	clock_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock_icon.set_position(Vector2(vp_w / 2 - 82, 0))
	clock_icon.set_size(Vector2(24, HUD_HEIGHT))
	panel.add_child(clock_icon)

	# ── DERECHA: Puntos de frutas + barra de vida ─────────────────────────────
	var right_section_x := vp_w - 200

	# Puntos de frutas
	_fruit_label = Label.new()
	_fruit_label.name = "FruitLabel"
	_fruit_label.text = "🍎 0"
	_fruit_label.add_theme_font_size_override("font_size", 16)
	_fruit_label.add_theme_color_override("font_color", COL_FRUIT)
	_fruit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fruit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fruit_label.set_position(Vector2(right_section_x, 0))
	_fruit_label.set_size(Vector2(180, HUD_HEIGHT / 2))
	panel.add_child(_fruit_label)

	# Barra de vida (fondo + relleno)
	var hp_bg := ColorRect.new()
	hp_bg.name = "HPBarBG"
	hp_bg.color = COL_HP_BG
	hp_bg.set_position(Vector2(right_section_x, HUD_HEIGHT / 2 + 4))
	hp_bg.set_size(Vector2(180, 10))
	panel.add_child(hp_bg)

	_hp_bar = hp_bg  # guardamos referencia del BG para calcular ancho fill

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.name = "HPBarFill"
	_hp_bar_fill.color = COL_HP_FG
	_hp_bar_fill.set_position(Vector2(0, 0))
	_hp_bar_fill.set_size(Vector2(180, 10))
	hp_bg.add_child(_hp_bar_fill)

	# Separador visual entre secciones
	_add_separator(panel, vp_w / 2 - 110, 4, HUD_HEIGHT - 8)
	_add_separator(panel, right_section_x - 12, 4, HUD_HEIGHT - 8)

func _add_separator(parent: Node, x: float, y: float, h: float) -> void:
	var sep := ColorRect.new()
	sep.color = COL_SEPARATOR
	sep.set_position(Vector2(x, y))
	sep.set_size(Vector2(2, h))
	parent.add_child(sep)

# ─────────────────────────────────────────────────────────────────────────────
#  Búsqueda de jugador
# ─────────────────────────────────────────────────────────────────────────────
func find_player() -> void:
	if player != null:
		return
	# Buscar el primer nodo en el grupo "player" con player_index == 1
	for node in get_tree().get_nodes_in_group("player"):
		if node is CharacterBody2D:
			if node.get("player_index") == 1 or node.get("player_index") == null:
				player = node
				return
	# Fallback: cualquier CharacterBody2D en el árbol
	var node = get_tree().get_first_node_in_group("player")
	if node is CharacterBody2D:
		player = node

# ─────────────────────────────────────────────────────────────────────────────
#  Timer
# ─────────────────────────────────────────────────────────────────────────────
func _tick_timer(delta: float) -> void:
	if not _timer_running or _dead_by_timer:
		return

	_timer_left -= delta
	if _timer_left <= 0.0:
		_timer_left = 0.0
		_timer_running = false
		_kill_all_players()

func _kill_all_players() -> void:
	if _dead_by_timer:
		return
	_dead_by_timer = true
	for node in get_tree().get_nodes_in_group("player"):
		if node.has_method("die"):
			node.die()

# Reinicia el timer (llamable desde LevelManager al cargar nivel)
func reset_timer() -> void:
	_timer_left = TIMER_SECONDS
	_timer_running = true
	_dead_by_timer = false

# ─────────────────────────────────────────────────────────────────────────────
#  Actualización de UI cada frame
# ─────────────────────────────────────────────────────────────────────────────
func _update_ui() -> void:
	# ── Timer ─────────────────────────────────────────────────────────────────
	if _timer_label:
		var secs := int(_timer_left)
		var mins := secs / 60
		var s    := secs % 60
		_timer_label.text = "%d:%02d" % [mins, s]
		if _timer_left <= LOW_TIME_WARN:
			# Parpadeo rojo
			_blink_acc += get_process_delta_time()
			var blink_on := int(_blink_acc / 0.35) % 2 == 0
			_timer_label.add_theme_color_override("font_color",
				COL_TIME_LOW if blink_on else Color(1, 1, 1, 0.3))
		else:
			_blink_acc = 0.0
			_timer_label.add_theme_color_override("font_color", COL_TIME_OK)

	# ── Puntos de frutas ──────────────────────────────────────────────────────
	if _fruit_label:
		_fruit_label.text = "🍎 %d" % GeneralRules.total_fruit_points

	# ── Barra de vida ─────────────────────────────────────────────────────────
	if _hp_bar_fill and player and not player.is_queued_for_deletion():
		var hp_pct := clampf(float(player.health) / 100.0, 0.0, 1.0)
		_hp_bar_fill.set_size(Vector2(_hp_bar.size.x * hp_pct, _hp_bar.size.y))
		# Cambia color según salud: verde → amarillo → rojo
		if hp_pct > 0.5:
			_hp_bar_fill.color = COL_HP_FG
		elif hp_pct > 0.25:
			_hp_bar_fill.color = Color(1.0, 0.75, 0.10)
		else:
			_hp_bar_fill.color = Color(0.9, 0.15, 0.15)

	# ── Íconos de vida ────────────────────────────────────────────────────────
	_refresh_life_icons()

func _refresh_life_icons() -> void:
	var current_lives := clampi(GeneralRules.lives, 0, MAX_ICON_LIVES)
	for i in _life_icons.size():
		var icon := _life_icons[i]
		if i < current_lives:
			icon.modulate = Color(1, 1, 1, 1.0)    # Vivo: brillante
		else:
			icon.modulate = Color(0.3, 0.3, 0.3, 0.4)  # Perdido: gris tenue
