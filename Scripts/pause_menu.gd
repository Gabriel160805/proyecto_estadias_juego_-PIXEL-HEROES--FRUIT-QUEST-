extends CanvasLayer

# ─────────────────────────────────────────────────────────────────────────────
#  pause_menu.gd
#  Menú de pausa completo con soporte para mando (Start / B / A / D-Pad),
#  teclado (Esc / Enter / Flechas) y ratón.
#  Opciones: Continuar | Reiniciar Nivel | Selector de Niveles | Menú Principal
# ─────────────────────────────────────────────────────────────────────────────

const RESUME_TEX  = preload("res://Assets/Menu/Buttons/Play.png")
const RESTART_TEX = preload("res://Assets/Menu/Buttons/Restart.png")
const LEVELS_TEX  = preload("res://Assets/Menu/Buttons/Levels.png")
const BACK_TEX    = preload("res://Assets/Menu/Buttons/Back.png")

var _root_control: Control
var _resume_btn: Button
var _restart_btn: Button
var _levels_btn: Button
var _menu_btn: Button
var _menu_buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_ui()
	_root_control.visible = false

func _input(event: InputEvent) -> void:
	# Detección de botón Start en mando o Escape en teclado
	var is_pause_toggle := false
	if event.is_action_pressed("ui_cancel") and (event is InputEventKey):
		is_pause_toggle = true
	elif event is InputEventJoypadButton and event.is_pressed():
		if event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_BACK:
			is_pause_toggle = true

	if is_pause_toggle:
		get_viewport().set_input_as_handled()
		if get_tree().paused:
			resume_game()
		else:
			pause_game()
		return

	# Si está en pausa, manejar el botón B para reanudar
	if get_tree().paused:
		if event is InputEventJoypadButton and event.is_pressed() and event.button_index == JOY_BUTTON_B:
			get_viewport().set_input_as_handled()
			resume_game()
			return

		# Confirmar con botón A del mando
		if event is InputEventJoypadButton and event.is_pressed() and event.button_index == JOY_BUTTON_A:
			var focus_owner := get_viewport().gui_get_focus_owner()
			if focus_owner is BaseButton and not focus_owner.disabled:
				get_viewport().set_input_as_handled()
				focus_owner.pressed.emit()
				return

		# Si se pierde el foco, reenfocar al usar D-Pad o stick
		if get_viewport().gui_get_focus_owner() == null:
			if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or \
			   event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
				_resume_btn.grab_focus()
				get_viewport().set_input_as_handled()

# ─────────────────────────────────────────────────────────────────────────────
#  Control de Pausa
# ─────────────────────────────────────────────────────────────────────────────
func pause_game() -> void:
	get_tree().paused = true
	_root_control.visible = true
	_resume_btn.grab_focus.call_deferred()

func resume_game() -> void:
	_root_control.visible = false
	get_tree().paused = false

# ─────────────────────────────────────────────────────────────────────────────
#  Construcción de la Interfaz
# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "PauseRoot"
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root_control)

	# Fondo oscurecido con tinte azul oscuro
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.03, 0.04, 0.08, 0.82)
	_root_control.add_child(overlay)

	# Panel central modal
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_control.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 420)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.16, 0.95)
	panel_style.set_corner_radius_all(16)
	panel_style.set_border_width_all(3)
	panel_style.border_color = Color(0.35, 0.65, 1.0, 0.9)
	panel_style.content_margin_left = 32
	panel_style.content_margin_right = 32
	panel_style.content_margin_top = 28
	panel_style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	# Título "PAUSA"
	var title := Label.new()
	title.text = "PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(title)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(280, 2)
	divider.color = Color(0.35, 0.55, 0.85, 0.5)
	vbox.add_child(divider)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 8)
	vbox.add_child(spacer)

	# Botones del menú
	_resume_btn = _create_menu_button("CONTINUAR", RESUME_TEX, Color(0.18, 0.45, 0.24, 0.9), Color(0.35, 0.90, 0.45, 1.0))
	_resume_btn.pressed.connect(_on_resume_pressed)
	vbox.add_child(_resume_btn)
	_menu_buttons.append(_resume_btn)

	_restart_btn = _create_menu_button("REINICIAR NIVEL", RESTART_TEX, Color(0.18, 0.32, 0.48, 0.9), Color(0.35, 0.70, 1.0, 1.0))
	_restart_btn.pressed.connect(_on_restart_pressed)
	vbox.add_child(_restart_btn)
	_menu_buttons.append(_restart_btn)

	_levels_btn = _create_menu_button("SELECCIÓN DE NIVEL", LEVELS_TEX, Color(0.35, 0.28, 0.15, 0.9), Color(1.0, 0.75, 0.25, 1.0))
	_levels_btn.pressed.connect(_on_levels_pressed)
	vbox.add_child(_levels_btn)
	_menu_buttons.append(_levels_btn)

	_menu_btn = _create_menu_button("MENÚ PRINCIPAL", BACK_TEX, Color(0.38, 0.18, 0.18, 0.9), Color(0.95, 0.35, 0.35, 1.0))
	_menu_btn.pressed.connect(_on_menu_pressed)
	vbox.add_child(_menu_btn)
	_menu_buttons.append(_menu_btn)

	# Configurar navegación de foco vertical en bucle
	for i in range(_menu_buttons.size()):
		var prev_btn = _menu_buttons[(i - 1 + _menu_buttons.size()) % _menu_buttons.size()]
		var next_btn = _menu_buttons[(i + 1) % _menu_buttons.size()]
		_menu_buttons[i].focus_neighbor_top = prev_btn.get_path()
		_menu_buttons[i].focus_neighbor_bottom = next_btn.get_path()

# ─────────────────────────────────────────────────────────────────────────────
#  Acciones de los Botones
# ─────────────────────────────────────────────────────────────────────────────
func _on_resume_pressed() -> void:
	resume_game()

func _on_restart_pressed() -> void:
	resume_game()
	GeneralRules.reset_run()
	get_tree().reload_current_scene()

func _on_levels_pressed() -> void:
	resume_game()
	get_tree().change_scene_to_file("res://Scenes/Screens/level_select.tscn")

func _on_menu_pressed() -> void:
	resume_game()
	get_tree().change_scene_to_file("res://Scenes/Screens/main_menu.tscn")

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers de Botones
# ─────────────────────────────────────────────────────────────────────────────
func _create_menu_button(text: String, icon_tex: Texture2D, bg_col: Color, border_col: Color) -> Button:
	var btn := Button.new()
	btn.text = "  " + text
	btn.icon = icon_tex
	btn.expand_icon = true
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.custom_minimum_size = Vector2(300, 48)
	btn.add_theme_font_size_override("font_size", 16)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_col
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.border_color = border_col * 0.7

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_col.lightened(0.15)
	hover.set_corner_radius_all(10)
	hover.set_border_width_all(2)
	hover.border_color = border_col

	var focus := StyleBoxFlat.new()
	focus.bg_color = bg_col.lightened(0.2)
	focus.set_corner_radius_all(10)
	focus.set_border_width_all(3)
	focus.border_color = Color(1.0, 0.90, 0.30, 1.0) # Borde dorado cuando está enfocado

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", focus)

	return btn
