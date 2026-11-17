extends Control

# ── Recursos ──────────────────────────────────────────────────────────────────
const BG_TEXTURE = preload("res://Assets/Background/Blue.png")
const PLAY_TEX   = preload("res://Assets/Menu/Buttons/Play.png")
const CLOSE_TEX  = preload("res://Assets/Menu/Buttons/Close.png")

const SCREEN_W := 1152.0
const SCREEN_H := 648.0

const BTN_SCALE_HOVER  = Vector2(1.06, 1.06)
const BTN_SCALE_NORMAL = Vector2(1.0,  1.0)
const TITLE_FLOAT_AMP  = 5.0
const TITLE_FLOAT_SPD  = 1.8

var _title_container: VBoxContainer
var _title_base_y: float
var _menu_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = Vector2(SCREEN_W, SCREEN_H)
	_build_ui()
	_start_title_float()
	_grab_initial_focus.call_deferred()


func _grab_initial_focus() -> void:
	if not _menu_buttons.is_empty() and is_instance_valid(_menu_buttons[0]):
		_menu_buttons[0].grab_focus()


func _input(event: InputEvent) -> void:
	# Confirmación con mando (Botón A, X, Start)
	var is_confirm := false
	if event is InputEventJoypadButton and event.is_pressed():
		if event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_X or event.button_index == JOY_BUTTON_START:
			is_confirm = true
	elif event.is_action_pressed("ui_accept") and not (event is InputEventKey):
		is_confirm = true

	if is_confirm:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner == null and not _menu_buttons.is_empty():
			_grab_initial_focus()
			focus_owner = get_viewport().gui_get_focus_owner()

		if focus_owner is BaseButton and not focus_owner.disabled:
			get_viewport().set_input_as_handled()
			focus_owner.pressed.emit()
			return

	# Si no hay foco en ningún botón y el usuario interactúa con la cruceta o stick, reenfocar
	if get_viewport().gui_get_focus_owner() == null and not _menu_buttons.is_empty():
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or \
		   event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_grab_initial_focus()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	# ── Fondo en mosaico ──────────────────────────────────────────────────────
	var bg := TextureRect.new()
	bg.texture        = BG_TEXTURE
	bg.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode   = TextureRect.STRETCH_TILE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ── CenterContainer general ───────────────────────────────────────────────
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 24)
	center.add_child(main_vbox)

	# ── Título estilizado con subtítulo ───────────────────────────────────────
	_title_container = VBoxContainer.new()
	_title_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_container.add_theme_constant_override("separation", 2)
	main_vbox.add_child(_title_container)

	var main_title := Label.new()
	main_title.text = "PIXEL HEROES"
	main_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_title.add_theme_font_size_override("font_size", 54)
	main_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
	main_title.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.0, 0.9))
	main_title.add_theme_constant_override("shadow_offset_x", 4)
	main_title.add_theme_constant_override("shadow_offset_y", 4)
	_title_container.add_child(main_title)

	var sub_title := Label.new()
	sub_title.text = "— FRUIT QUEST —"
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_title.add_theme_font_size_override("font_size", 20)
	sub_title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	sub_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.1, 0.2, 0.8))
	sub_title.add_theme_constant_override("shadow_offset_x", 2)
	sub_title.add_theme_constant_override("shadow_offset_y", 2)
	_title_container.add_child(sub_title)

	# Separador vertical
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	main_vbox.add_child(spacer)

	# ── Contenedor de botones de menú ─────────────────────────────────────────
	var btn_vbox := VBoxContainer.new()
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_vbox.add_theme_constant_override("separation", 14)
	main_vbox.add_child(btn_vbox)

	var btn_play  := _add_menu_button(btn_vbox, "JUGAR", PLAY_TEX, _on_play_pressed, Color(0.2, 0.8, 0.4))
	var btn_multi := _add_menu_button(btn_vbox, "MULTIJUGADOR", PLAY_TEX, _on_multiplayer_pressed, Color(0.3, 0.6, 1.0))
	var btn_exit  := _add_menu_button(btn_vbox, "SALIR", CLOSE_TEX, _on_exit_pressed, Color(0.9, 0.35, 0.35))

	_menu_buttons = [btn_play, btn_multi, btn_exit]

	# Navegación entre botones para mando y teclado
	btn_play.focus_neighbor_top = btn_exit.get_path()
	btn_play.focus_neighbor_bottom = btn_multi.get_path()

	btn_multi.focus_neighbor_top = btn_play.get_path()
	btn_multi.focus_neighbor_bottom = btn_exit.get_path()

	btn_exit.focus_neighbor_top = btn_multi.get_path()
	btn_exit.focus_neighbor_bottom = btn_play.get_path()


# ── Creador de botón con ícono a la izquierda y texto a la derecha ──────────
func _add_menu_button(parent: Control, label_text: String, icon_tex: Texture2D, callback: Callable, accent_color: Color) -> Button:
	var btn_size := Vector2(280, 52)

	# Envoltura con CenterContainer para pivotar la escala en el centro
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = btn_size

	var panel := PanelContainer.new()
	panel.custom_minimum_size = btn_size
	panel.pivot_offset        = btn_size / 2.0

	# Estilo del panel (fondo oscuro tipo arcade retro con borde acentuado)
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color             = Color(0.08, 0.1, 0.15, 0.88)
	style_normal.border_color         = accent_color.lerp(Color.WHITE, 0.2)
	style_normal.border_width_left    = 2
	style_normal.border_width_top     = 2
	style_normal.border_width_right   = 2
	style_normal.border_width_bottom  = 4  # Efecto botón 3D biselado
	style_normal.corner_radius_top_left     = 6
	style_normal.corner_radius_top_right    = 6
	style_normal.corner_radius_bottom_left  = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.content_margin_left   = 16
	style_normal.content_margin_right  = 16
	style_normal.content_margin_top    = 8
	style_normal.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style_normal)

	# Contenedor horizontal: [Icono]  [Texto]
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# Ícono del botón (TextureRect pixel-art nítido, no estirado ni tapado)
	var icon_rect := TextureRect.new()
	icon_rect.texture        = icon_tex
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(28, 28)
	icon_rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_rect)

	# Etiqueta de texto (a la derecha del ícono)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	# Botón interactivo para procesar clicks y foco de control / teclado
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_btn.focus_mode = Control.FOCUS_ALL
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_child(click_btn)

	wrap.add_child(panel)
	parent.add_child(wrap)

	# Señales de hover, foco y click
	click_btn.pressed.connect(callback)
	click_btn.focus_entered.connect(_on_btn_hover.bind(panel, style_normal, accent_color, true))
	click_btn.focus_exited.connect(_on_btn_hover.bind(panel, style_normal, accent_color, false))
	click_btn.mouse_entered.connect(func():
		click_btn.grab_focus()
	)

	return click_btn


# ── Efecto Hover / Foco ───────────────────────────────────────────────────────
func _on_btn_hover(panel: PanelContainer, style: StyleBoxFlat, accent_color: Color, entering: bool) -> void:
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var target_scale := BTN_SCALE_HOVER if entering else BTN_SCALE_NORMAL
	tw.tween_property(panel, "scale", target_scale, 0.12)

	# Resaltar borde y fondo en foco / hover
	if entering:
		style.border_color = Color.WHITE
		style.bg_color     = Color(0.14, 0.18, 0.26, 0.95)
	else:
		style.border_color = accent_color.lerp(Color.WHITE, 0.2)
		style.bg_color     = Color(0.08, 0.1, 0.15, 0.88)


# ── Animación flotante del título ──────────────────────────────────────────────
func _start_title_float() -> void:
	await get_tree().process_frame
	_title_base_y = _title_container.position.y
	var tw := create_tween().set_loops()
	tw.tween_method(_apply_float, 0.0, TAU, 1.0 / TITLE_FLOAT_SPD)


func _apply_float(t: float) -> void:
	if is_instance_valid(_title_container):
		_title_container.position.y = _title_base_y + sin(t) * TITLE_FLOAT_AMP


# ── Navegación ────────────────────────────────────────────────────────────────
func _on_play_pressed() -> void:
	GeneralRules.is_multiplayer = false
	get_tree().change_scene_to_file("res://Scenes/Screens/character_select.tscn")


func _on_multiplayer_pressed() -> void:
	GeneralRules.is_multiplayer = true
	get_tree().change_scene_to_file("res://Scenes/Screens/character_select.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
