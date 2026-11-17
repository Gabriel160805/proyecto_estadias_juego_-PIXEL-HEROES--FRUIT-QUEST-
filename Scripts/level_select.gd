extends Control

# ─────────────────────────────────────────────────────────────────────────────
#  level_select.gd
#  Pantalla de selección de nivel por mundos (4 mundos × 3 niveles cada uno).
#  • Muestra el estado desbloqueado/bloqueado según el guardado en GeneralRules.
#  • Soporte completo para mando (gamepad), teclado y ratón.
#  • Cambio de mundo con botones de flecha o con [LB] / [RB] en mando.
# ─────────────────────────────────────────────────────────────────────────────

const SCREEN_W := 1152.0
const SCREEN_H := 648.0

const BACK_TEX  = preload("res://Assets/Menu/Buttons/Back.png")
const PLAY_TEX  = preload("res://Assets/Menu/Buttons/Play.png")
const PREV_TEX  = preload("res://Assets/Menu/Buttons/Previous.png")
const NEXT_TEX  = preload("res://Assets/Menu/Buttons/Next.png")

var _selected_world: int = 1
var _bg_rect: TextureRect
var _world_title_label: Label
var _prev_world_btn: Button
var _next_world_btn: Button
var _back_btn: Button
var _level_buttons: Array[Button] = []
var _level_cards: Array[PanelContainer] = []
var _cards_data: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = Vector2(SCREEN_W, SCREEN_H)
	# Comenzar en el mundo desbloqueado actual más alto
	_selected_world = clampi(GeneralRules.max_unlocked_world, 1, GeneralRules.MAX_WORLDS)
	_build_ui()
	_update_display()
	_grab_initial_focus.call_deferred()

func _grab_initial_focus() -> void:
	# Enfocar el primer nivel desbloqueado disponible en este mundo
	for btn in _level_buttons:
		if not btn.disabled:
			btn.grab_focus()
			return
	if is_instance_valid(_back_btn):
		_back_btn.grab_focus()

func _input(event: InputEvent) -> void:
	# Volver con botón B o Escape
	if event.is_action_pressed("ui_cancel") or \
	   (event is InputEventJoypadButton and event.is_pressed() and event.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return

	# Cambiar de mundo con botones superiores (LB / RB)
	if event is InputEventJoypadButton and event.is_pressed():
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			get_viewport().set_input_as_handled()
			_prev_world()
			return
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			get_viewport().set_input_as_handled()
			_next_world()
			return

	# Confirmar con botón A del mando
	if event is InputEventJoypadButton and event.is_pressed() and event.button_index == JOY_BUTTON_A:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is BaseButton and not focus_owner.disabled:
			get_viewport().set_input_as_handled()
			focus_owner.pressed.emit()
			return

	# Si se pierde el foco, reenfocar al tocar stick o cruceta
	if get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or \
		   event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_grab_initial_focus()
			get_viewport().set_input_as_handled()

# ─────────────────────────────────────────────────────────────────────────────
#  Construcción de la interfaz
# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# ── Fondo Dinámico según el mundo ─────────────────────────────────────────
	_bg_rect = TextureRect.new()
	_bg_rect.name = "Background"
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_rect.stretch_mode = TextureRect.STRETCH_TILE
	add_child(_bg_rect)

	# Capa de oscurecimiento para legibilidad
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.04, 0.04, 0.08, 0.75)
	add_child(overlay)

	# ── Contenedor Principal Vertical ─────────────────────────────────────────
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 16)
	add_child(main_vbox)

	# Margen superior
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(SCREEN_W, 20)
	main_vbox.add_child(top_spacer)

	# ── Título y Subtítulo ───────────────────────────────────────────────────
	var title_lbl := Label.new()
	title_lbl.text = "SELECCIÓN DE NIVEL"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 34)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title_lbl.add_theme_constant_override("shadow_offset_y", 3)
	main_vbox.add_child(title_lbl)

	# Información de personaje y récord
	var info_lbl := Label.new()
	var p1_name: String = GeneralRules.CHARACTER_NAMES.get(GeneralRules.selected_character, "Héroe")
	var score_text := "Jugador: %s  |  🏆 Récord: %d pts" % [p1_name, GeneralRules.high_score]
	if GeneralRules.is_multiplayer and GeneralRules.selected_character_p2 != "":
		var p2_name: String = GeneralRules.CHARACTER_NAMES.get(GeneralRules.selected_character_p2, "P2")
		score_text = "P1: %s  •  P2: %s  |  🏆 Récord: %d pts" % [p1_name, p2_name, GeneralRules.high_score]
	info_lbl.text = score_text
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 16)
	info_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	main_vbox.add_child(info_lbl)

	# ── Barra de Selección de Mundo (Pestañas / Flechas) ───────────────────────
	var world_bar := HBoxContainer.new()
	world_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	world_bar.add_theme_constant_override("separation", 24)
	main_vbox.add_child(world_bar)

	_prev_world_btn = _create_icon_button(PREV_TEX, "Mundo anterior")
	_prev_world_btn.pressed.connect(_prev_world)
	world_bar.add_child(_prev_world_btn)

	var world_panel := PanelContainer.new()
	var wp_style := StyleBoxFlat.new()
	wp_style.bg_color = Color(0.12, 0.12, 0.22, 0.9)
	wp_style.set_corner_radius_all(10)
	wp_style.set_border_width_all(2)
	wp_style.border_color = Color(0.35, 0.65, 1.0, 0.8)
	wp_style.content_margin_left = 32
	wp_style.content_margin_right = 32
	wp_style.content_margin_top = 10
	wp_style.content_margin_bottom = 10
	world_panel.add_theme_stylebox_override("panel", wp_style)
	world_bar.add_child(world_panel)

	_world_title_label = Label.new()
	_world_title_label.text = "MUNDO 1: BOSQUE DE VERANO"
	_world_title_label.add_theme_font_size_override("font_size", 20)
	_world_title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_world_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world_panel.add_child(_world_title_label)

	_next_world_btn = _create_icon_button(NEXT_TEX, "Siguiente mundo")
	_next_world_btn.pressed.connect(_next_world)
	world_bar.add_child(_next_world_btn)

	# Indicador de mando (LB / RB)
	var bumper_hint := Label.new()
	bumper_hint.text = "[LB] Anterior   •   [RB] Siguiente"
	bumper_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bumper_hint.add_theme_font_size_override("font_size", 13)
	bumper_hint.add_theme_color_override("font_color", Color(0.65, 0.70, 0.85, 0.7))
	main_vbox.add_child(bumper_hint)

	# Espaciador central
	var mid_spacer := Control.new()
	mid_spacer.custom_minimum_size = Vector2(SCREEN_W, 10)
	main_vbox.add_child(mid_spacer)

	# ── Contenedor de Tarjetas de Nivel (3 Niveles) ──────────────────────────
	var cards_hbox := HBoxContainer.new()
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 36)
	main_vbox.add_child(cards_hbox)

	for level_idx in range(1, GeneralRules.LEVELS_PER_WORLD + 1):
		var card := _build_level_card(level_idx)
		cards_hbox.add_child(card)
		_level_cards.append(card)

	# ── Barra Inferior: Botón ATRÁS y Guía de Controles ───────────────────────
	var bottom_margin := Control.new()
	bottom_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(bottom_margin)

	var bottom_bar := HBoxContainer.new()
	bottom_bar.custom_minimum_size = Vector2(SCREEN_W - 80, 50)
	bottom_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	main_vbox.add_child(bottom_bar)

	var left_pad := Control.new()
	left_pad.custom_minimum_size = Vector2(40, 1)
	bottom_bar.add_child(left_pad)

	_back_btn = Button.new()
	_back_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_back_btn.custom_minimum_size = Vector2(130, 44)
	_back_btn.text = " ATRÁS"
	_back_btn.icon = BACK_TEX
	_back_btn.expand_icon = true
	_back_btn.add_theme_font_size_override("font_size", 16)
	_apply_button_styles(_back_btn, Color(0.20, 0.20, 0.28, 0.9), Color(0.85, 0.35, 0.35, 1.0))
	_back_btn.pressed.connect(_on_back_pressed)
	bottom_bar.add_child(_back_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(spacer)

	var help_lbl := Label.new()
	help_lbl.text = "[A] / Enter: Jugar    [B] / Esc: Volver    [D-Pad]: Moverse "
	help_lbl.add_theme_font_size_override("font_size", 14)
	help_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85, 0.8))
	bottom_bar.add_child(help_lbl)

	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(40, 1)
	bottom_bar.add_child(right_pad)

	var btm_space := Control.new()
	btm_space.custom_minimum_size = Vector2(SCREEN_W, 16)
	main_vbox.add_child(btm_space)

# ── Construcción de una Tarjeta de Nivel ──────────────────────────────────────
func _build_level_card(level_num: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 240)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.15, 0.92)
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = Color(0.35, 0.45, 0.65, 0.8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Número de nivel
	var num_lbl := Label.new()
	num_lbl.name = "LevelNum"
	num_lbl.text = "NIVEL %d" % level_num
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_lbl.add_theme_font_size_override("font_size", 24)
	num_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(num_lbl)

	# Código de escena (e.g. "1-1")
	var code_lbl := Label.new()
	code_lbl.name = "LevelCode"
	code_lbl.text = "%d - %d" % [_selected_world, level_num]
	code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_lbl.add_theme_font_size_override("font_size", 38)
	code_lbl.add_theme_color_override("font_color", Color(0.35, 0.80, 1.0))
	vbox.add_child(code_lbl)

	# Estado (Desbloqueado / Bloqueado)
	var status_lbl := Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.text = "DESBLOQUEADO"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status_lbl)

	# Botón de acción
	var play_btn := Button.new()
	play_btn.name = "PlayButton"
	play_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	play_btn.custom_minimum_size = Vector2(180, 40)
	play_btn.text = " JUGAR"
	play_btn.icon = PLAY_TEX
	play_btn.expand_icon = true
	_apply_button_styles(play_btn, Color(0.18, 0.40, 0.22, 0.95), Color(0.30, 0.90, 0.45, 1.0))

	var current_idx := level_num
	play_btn.pressed.connect(func(): _on_level_selected(current_idx))
	vbox.add_child(play_btn)
	_level_buttons.append(play_btn)

	var card_data := {
		"panel": panel,
		"style": style,
		"num_lbl": num_lbl,
		"code_lbl": code_lbl,
		"status_lbl": status_lbl,
		"btn": play_btn
	}
	_cards_data.append(card_data)

	return panel

# ─────────────────────────────────────────────────────────────────────────────
#  Actualización de Vista
# ─────────────────────────────────────────────────────────────────────────────
func _update_display() -> void:
	# Actualizar textura de fondo según el mundo
	var bg_path: String = GeneralRules.WORLD_BACKGROUNDS.get(_selected_world, "res://Assets/Background/Green.png")
	if ResourceLoader.exists(bg_path):
		_bg_rect.texture = load(bg_path)

	# Actualizar título del mundo
	var world_name: String = GeneralRules.WORLD_NAMES.get(_selected_world, "MUNDO %d" % _selected_world)
	_world_title_label.text = "MUNDO %d: %s" % [_selected_world, world_name]

	# Habilitar o atenuar flechas según límites
	_prev_world_btn.disabled = (_selected_world <= 1)
	_next_world_btn.disabled = (_selected_world >= GeneralRules.MAX_WORLDS)
	_prev_world_btn.modulate.a = 0.4 if _prev_world_btn.disabled else 1.0
	_next_world_btn.modulate.a = 0.4 if _next_world_btn.disabled else 1.0

	# Actualizar cada tarjeta de nivel
	for i in range(GeneralRules.LEVELS_PER_WORLD):
		var level_num := i + 1
		var data: Dictionary = _cards_data[i]
		var card: PanelContainer = data["panel"]
		var btn: Button = data["btn"]
		var code_lbl: Label = data["code_lbl"]
		var status_lbl: Label = data["status_lbl"]
		var panel_style: StyleBoxFlat = data["style"]

		code_lbl.text = "%d - %d" % [_selected_world, level_num]

		var is_unlocked := GeneralRules.is_level_unlocked(_selected_world, level_num)
		var scene_path := GeneralRules.get_level_scene_path(_selected_world, level_num)
		var exists := ResourceLoader.exists(scene_path)

		if not is_unlocked:
			# Bloqueado
			status_lbl.text = "🔒 BLOQUEADO"
			status_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70, 0.6))
			btn.text = "BLOQUEADO"
			btn.disabled = true
			btn.focus_mode = Control.FOCUS_NONE
			card.modulate = Color(0.6, 0.6, 0.65, 0.65)
			if panel_style:
				panel_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
		elif not exists:
			# Desbloqueado pero escena no creada aún
			status_lbl.text = "🛠 EN CONSTRUCCIÓN"
			status_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.20))
			btn.text = "PRÓXIMAMENTE"
			btn.disabled = true
			btn.focus_mode = Control.FOCUS_NONE
			card.modulate = Color(0.85, 0.85, 0.90, 0.85)
			if panel_style:
				panel_style.border_color = Color(0.7, 0.5, 0.2, 0.8)
		else:
			# Desbloqueado y disponible para jugar
			status_lbl.text = "✓ DESBLOQUEADO"
			status_lbl.add_theme_color_override("font_color", Color(0.30, 0.90, 0.45))
			btn.text = " JUGAR"
			btn.disabled = false
			btn.focus_mode = Control.FOCUS_ALL
			card.modulate = Color(1.0, 1.0, 1.0, 1.0)
			if panel_style:
				panel_style.border_color = Color(0.35, 0.80, 1.0, 0.9)

	_setup_focus_navigation()

# ── Configuración de Navegación de Foco ───────────────────────────────────────
func _setup_focus_navigation() -> void:
	# Vecinos entre las 3 tarjetas de nivel
	var available_btns: Array[Button] = []
	for btn in _level_buttons:
		if not btn.disabled:
			available_btns.append(btn)

	for i in range(_level_buttons.size()):
		var btn := _level_buttons[i]
		if btn.disabled:
			continue
		var prev_btn = _level_buttons[(i - 1 + _level_buttons.size()) % _level_buttons.size()]
		var next_btn = _level_buttons[(i + 1) % _level_buttons.size()]
		btn.focus_neighbor_left = prev_btn.get_path()
		btn.focus_neighbor_right = next_btn.get_path()
		btn.focus_neighbor_bottom = _back_btn.get_path()
		btn.focus_neighbor_top = _prev_world_btn.get_path() if not _prev_world_btn.disabled else _next_world_btn.get_path()

	# Vecinos de flechas de mundo
	_prev_world_btn.focus_neighbor_right = _next_world_btn.get_path()
	_next_world_btn.focus_neighbor_left = _prev_world_btn.get_path()
	if not available_btns.is_empty():
		_prev_world_btn.focus_neighbor_bottom = available_btns[0].get_path()
		_next_world_btn.focus_neighbor_bottom = available_btns[0].get_path()

	_back_btn.focus_neighbor_top = available_btns[0].get_path() if not available_btns.is_empty() else _prev_world_btn.get_path()

# ─────────────────────────────────────────────────────────────────────────────
#  Navegación de Mundos
# ─────────────────────────────────────────────────────────────────────────────
func _prev_world() -> void:
	if _selected_world > 1:
		_selected_world -= 1
		_update_display()
		_grab_initial_focus()

func _next_world() -> void:
	if _selected_world < GeneralRules.MAX_WORLDS:
		_selected_world += 1
		_update_display()
		_grab_initial_focus()

# ─────────────────────────────────────────────────────────────────────────────
#  Acciones
# ─────────────────────────────────────────────────────────────────────────────
func _on_level_selected(level_num: int) -> void:
	GeneralRules.reset_run()
	GeneralRules.go_to_level(_selected_world, level_num)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Screens/character_select.tscn")

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers de Estilos de Botones
# ─────────────────────────────────────────────────────────────────────────────
func _create_icon_button(tex: Texture2D, tooltip: String) -> Button:
	var btn := Button.new()
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.custom_minimum_size = Vector2(48, 48)
	btn.icon = tex
	btn.expand_icon = true
	btn.tooltip_text = tooltip
	_apply_button_styles(btn, Color(0.15, 0.15, 0.25, 0.9), Color(0.40, 0.70, 1.0, 1.0))
	return btn

func _apply_button_styles(btn: Button, bg_col: Color, border_col: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_col
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(2)
	normal.border_color = border_col * 0.7

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_col.lightened(0.15)
	hover.set_corner_radius_all(8)
	hover.set_border_width_all(2)
	hover.border_color = border_col

	var focus := StyleBoxFlat.new()
	focus.bg_color = bg_col.lightened(0.2)
	focus.set_corner_radius_all(8)
	focus.set_border_width_all(3)
	focus.border_color = Color(1.0, 0.90, 0.30, 1.0) # Borde dorado al tener foco de control

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.1, 0.1, 0.15, 0.5)
	disabled.set_corner_radius_all(8)
	disabled.set_border_width_all(1)
	disabled.border_color = Color(0.3, 0.3, 0.35, 0.4)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", disabled)
