extends Control

# ─────────────────────────────────────────────────────────────────────────────
#  character_select.gd
#  Pantalla de selección de personajes ajustada a 1152x648 con soporte total
#  para mando (gamepad / joystick), teclado y ratón.
#  • Modo 1-jugador : selección de P1 y enfoque automático en "¡A JUGAR!".
#  • Modo 2-jugadores: primer clic/A → P1, segundo clic/A → P2, luego "¡A JUGAR!".
#  • Botón B / Cancelar: deselecciona personaje o regresa al menú principal.
# ─────────────────────────────────────────────────────────────────────────────

const BACK_TEX   = preload("res://Assets/Menu/Buttons/Back.png")
const PLAY_TEX   = preload("res://Assets/Menu/Buttons/Play.png")
const BG_TEXTURE = preload("res://Assets/Background/Purple.png")

const SCREEN_W := 1152.0
const SCREEN_H := 648.0

const CHARACTER_KEYS: Array = ["ninja_frog", "pink_man", "mask_dude", "virtual_guy"]

var _sel_p1: String = ""
var _sel_p2: String = ""

var _card_nodes: Dictionary = {}  # key → { "style": StyleBoxFlat, "badge": Label, "panel": Control, "btn": Button }
var _card_buttons: Array[Button] = []
var _play_panel: PanelContainer
var _play_click_btn: Button
var _back_click_btn: Button
var _status_label: Label

const BTN_SCALE_HOVER  = Vector2(1.06, 1.06)
const BTN_SCALE_NORMAL = Vector2(1.0,  1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = Vector2(SCREEN_W, SCREEN_H)
	_build_ui()
	_grab_initial_focus.call_deferred()


func _grab_initial_focus() -> void:
	if not _card_buttons.is_empty() and is_instance_valid(_card_buttons[0]):
		_card_buttons[0].grab_focus()


func _input(event: InputEvent) -> void:
	# Botón B del mando o tecla Escape / Cancelar
	if event.is_action_pressed("ui_cancel") or \
	   (event is InputEventJoypadButton and event.is_pressed() and event.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
		_handle_cancel()
		return

	# Confirmación con mando (Botón A, X, Start)
	var is_confirm := false
	if event is InputEventJoypadButton and event.is_pressed():
		if event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_X or event.button_index == JOY_BUTTON_START:
			is_confirm = true
	elif event.is_action_pressed("ui_accept") and not (event is InputEventKey):
		is_confirm = true

	if is_confirm:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner == null and not _card_buttons.is_empty():
			_grab_initial_focus()
			focus_owner = get_viewport().gui_get_focus_owner()

		if focus_owner is BaseButton and not focus_owner.disabled:
			get_viewport().set_input_as_handled()
			focus_owner.pressed.emit()
			return

	# Si se pierde el foco y el usuario usa el stick o cruceta, reenfocar
	if get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or \
		   event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_grab_initial_focus()
			get_viewport().set_input_as_handled()


func _handle_cancel() -> void:
	if GeneralRules.is_multiplayer:
		if _sel_p2 != "":
			_sel_p2 = ""
			_refresh_cards()
			_refresh_status()
			_refresh_play_button()
			_focus_card_by_key(_sel_p1)
		elif _sel_p1 != "":
			_sel_p1 = ""
			_refresh_cards()
			_refresh_status()
			_refresh_play_button()
			_focus_card_by_key("ninja_frog")
		else:
			_on_back_pressed()
	else:
		if _sel_p1 != "":
			_sel_p1 = ""
			_refresh_cards()
			_refresh_status()
			_refresh_play_button()
			_focus_card_by_key("ninja_frog")
		else:
			_on_back_pressed()


func _focus_card_by_key(key: String) -> void:
	var d: Dictionary = _card_nodes.get(key, {})
	if not d.is_empty() and is_instance_valid(d["btn"]):
		d["btn"].grab_focus()


func _build_ui() -> void:
	# ── Fondo en mosaico ──────────────────────────────────────────────────────
	var bg := TextureRect.new()
	bg.texture        = BG_TEXTURE
	bg.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode   = TextureRect.STRETCH_TILE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ── CenterContainer para centrar todo el bloque en 1152x648 ───────────────
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# ── Contenedor vertical principal ─────────────────────────────────────────
	var root_vbox := VBoxContainer.new()
	root_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_theme_constant_override("separation", 18)
	center.add_child(root_vbox)

	# ── Título ────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "ELIGE TU PERSONAJE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
	title.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	root_vbox.add_child(title)

	# ── Instrucción dinámica ──────────────────────────────────────────────────
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	root_vbox.add_child(_status_label)

	# Espacio intermedio
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	root_vbox.add_child(spacer)

	# ── Fila de tarjetas de personajes ────────────────────────────────────────
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	root_vbox.add_child(hbox)

	_card_buttons.clear()
	for key in CHARACTER_KEYS:
		_build_card(hbox, key)

	# Espacio inferior
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 14)
	root_vbox.add_child(spacer2)

	# ── Fila de botones de acción ─────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 36)
	root_vbox.add_child(btn_row)

	_back_click_btn = _add_action_button(btn_row, "ATRÁS", BACK_TEX, _on_back_pressed, Color(0.9, 0.4, 0.4))
	_play_click_btn = _add_play_button(btn_row, "¡A JUGAR!", PLAY_TEX, _on_play_pressed, Color(0.2, 0.85, 0.45))

	_refresh_cards()
	_refresh_status()
	_refresh_play_button()


# ── Tarjeta de personaje ──────────────────────────────────────────────────────
func _build_card(parent: Control, key: String) -> void:
	var card_size := Vector2(140, 200)

	var card_wrap := CenterContainer.new()
	card_wrap.custom_minimum_size = card_size

	var panel := PanelContainer.new()
	panel.custom_minimum_size = card_size
	panel.pivot_offset        = card_size / 2.0

	var style := StyleBoxFlat.new()
	style.bg_color             = Color(0.06, 0.06, 0.12, 0.88)
	style.border_width_left    = 3
	style.border_width_top     = 3
	style.border_width_right   = 3
	style.border_width_bottom  = 3
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	style.border_color         = Color(0.2, 0.25, 0.35, 0.6)
	style.content_margin_left   = 8
	style.content_margin_right  = 8
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var scene_path: String = GeneralRules.CHARACTER_SCENES[key]
	var packed: PackedScene = load(scene_path)
	var state = packed.instantiate()
	var original_anim: AnimatedSprite2D = state.get_node("animaciones")

	var anim := AnimatedSprite2D.new()
	anim.sprite_frames  = original_anim.sprite_frames
	anim.play("idle")
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	state.queue_free()

	var sprite_container := Control.new()
	sprite_container.custom_minimum_size = Vector2(124, 110)
	sprite_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anim.position = Vector2(62, 65)
	anim.scale    = Vector2(3.0, 3.0)
	sprite_container.add_child(anim)
	vbox.add_child(sprite_container)

	var name_lbl := Label.new()
	name_lbl.text = GeneralRules.CHARACTER_NAMES[key]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var badge := Label.new()
	badge.text = ""
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color(0.3, 1, 0.4))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(badge)

	# Botón interactivo para clicks y navegación de control
	var click_area := Button.new()
	click_area.flat = true
	click_area.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	click_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_area.focus_mode = Control.FOCUS_ALL
	click_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_child(click_area)

	card_wrap.add_child(panel)
	parent.add_child(card_wrap)

	_card_nodes[key] = {
		"style": style,
		"badge": badge,
		"panel": panel,
		"btn": click_area
	}
	_card_buttons.append(click_area)

	click_area.pressed.connect(_on_character_selected.bind(key))
	click_area.focus_entered.connect(_on_card_focus.bind(key, true))
	click_area.focus_exited.connect(_on_card_focus.bind(key, false))
	click_area.mouse_entered.connect(func():
		click_area.grab_focus()
	)


# ── Botones de acción inferiores ──────────────────────────────────────────────
func _add_action_button(parent: Control, label_text: String, icon_tex: Texture2D, callback: Callable, accent_color: Color) -> Button:
	var btn_size := Vector2(190, 48)

	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = btn_size

	var panel := PanelContainer.new()
	panel.custom_minimum_size = btn_size
	panel.pivot_offset        = btn_size / 2.0

	var style := StyleBoxFlat.new()
	style.bg_color             = Color(0.08, 0.1, 0.15, 0.88)
	style.border_color         = accent_color.lerp(Color.WHITE, 0.2)
	style.border_width_left    = 2
	style.border_width_top     = 2
	style.border_width_right   = 2
	style.border_width_bottom  = 4
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = 14
	style.content_margin_right  = 14
	style.content_margin_top    = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	var icon_rect := TextureRect.new()
	icon_rect.texture        = icon_tex
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(24, 24)
	icon_rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_rect)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_btn.focus_mode = Control.FOCUS_ALL
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_child(click_btn)

	wrap.add_child(panel)
	parent.add_child(wrap)

	click_btn.pressed.connect(callback)
	click_btn.focus_entered.connect(_on_btn_hover.bind(panel, style, accent_color, true))
	click_btn.focus_exited.connect(_on_btn_hover.bind(panel, style, accent_color, false))
	click_btn.mouse_entered.connect(func():
		click_btn.grab_focus()
	)

	return click_btn


func _add_play_button(parent: Control, label_text: String, icon_tex: Texture2D, callback: Callable, accent_color: Color) -> Button:
	var btn_size := Vector2(210, 48)

	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = btn_size

	_play_panel = PanelContainer.new()
	_play_panel.custom_minimum_size = btn_size
	_play_panel.pivot_offset        = btn_size / 2.0

	var style := StyleBoxFlat.new()
	style.bg_color             = Color(0.08, 0.1, 0.15, 0.88)
	style.border_color         = accent_color.lerp(Color.WHITE, 0.2)
	style.border_width_left    = 2
	style.border_width_top     = 2
	style.border_width_right   = 2
	style.border_width_bottom  = 4
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = 16
	style.content_margin_right  = 16
	style.content_margin_top    = 6
	style.content_margin_bottom = 6
	_play_panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_panel.add_child(hbox)

	var icon_rect := TextureRect.new()
	icon_rect.texture        = icon_tex
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(24, 24)
	icon_rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_rect)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	_play_click_btn = Button.new()
	_play_click_btn.flat = true
	_play_click_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_play_click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_play_click_btn.focus_mode = Control.FOCUS_ALL
	_play_click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_play_panel.add_child(_play_click_btn)

	wrap.add_child(_play_panel)
	parent.add_child(wrap)

	_play_click_btn.pressed.connect(callback)
	_play_click_btn.focus_entered.connect(_on_btn_hover.bind(_play_panel, style, accent_color, true))
	_play_click_btn.focus_exited.connect(_on_btn_hover.bind(_play_panel, style, accent_color, false))
	_play_click_btn.mouse_entered.connect(func():
		if not _play_click_btn.disabled:
			_play_click_btn.grab_focus()
	)

	return _play_click_btn


# ── Foco y Hover en Tarjetas ──────────────────────────────────────────────────
func _on_card_focus(key: String, entering: bool) -> void:
	var d: Dictionary = _card_nodes.get(key, {})
	if d.is_empty():
		return
	var panel: Control = d["panel"]
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(panel, "scale", BTN_SCALE_HOVER if entering else BTN_SCALE_NORMAL, 0.12)
	_refresh_cards()


func _get_focused_card_key() -> String:
	for key in CHARACTER_KEYS:
		var d: Dictionary = _card_nodes.get(key, {})
		if not d.is_empty() and is_instance_valid(d["btn"]) and d["btn"].has_focus():
			return key
	return ""


func _on_btn_hover(panel: PanelContainer, style: StyleBoxFlat, accent_color: Color, entering: bool) -> void:
	if panel == _play_panel and _play_click_btn.disabled:
		return
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(panel, "scale", BTN_SCALE_HOVER if entering else BTN_SCALE_NORMAL, 0.12)

	if entering:
		style.border_color = Color.WHITE
		style.bg_color     = Color(0.14, 0.18, 0.26, 0.95)
	else:
		style.border_color = accent_color.lerp(Color.WHITE, 0.2)
		style.bg_color     = Color(0.08, 0.1, 0.15, 0.88)


# ── Selección de personajes ───────────────────────────────────────────────────
func _on_character_selected(key: String) -> void:
	if not GeneralRules.is_multiplayer:
		_sel_p1 = key
		_sel_p2 = ""
		_refresh_cards()
		_refresh_status()
		_refresh_play_button()
		# Enfoque inmediato en el botón de Jugar al tener seleccionado el personaje
		if is_instance_valid(_play_click_btn) and not _play_click_btn.disabled:
			_play_click_btn.grab_focus()
	else:
		if _sel_p1 == "":
			_sel_p1 = key
		elif _sel_p2 == "":
			_sel_p2 = key
			_refresh_cards()
			_refresh_status()
			_refresh_play_button()
			if is_instance_valid(_play_click_btn) and not _play_click_btn.disabled:
				_play_click_btn.grab_focus()
			return
		else:
			_sel_p1 = key
			_sel_p2 = ""

		_refresh_cards()
		_refresh_status()
		_refresh_play_button()


func _refresh_cards() -> void:
	var focused_key := _get_focused_card_key()

	for key in CHARACTER_KEYS:
		var d: Dictionary = _card_nodes[key]
		var style: StyleBoxFlat = d["style"]
		var badge: Label        = d["badge"]
		var is_focused: bool    = (key == focused_key)

		if key == _sel_p1 and key == _sel_p2:
			style.border_color = Color(1.0, 0.85, 0.0)
			badge.text         = "P1 + P2"
			badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
		elif key == _sel_p1:
			style.border_color = Color(0.25, 0.65, 1.0)
			badge.text         = "P1" if GeneralRules.is_multiplayer else "✓"
			badge.add_theme_color_override("font_color", Color(0.25, 0.65, 1.0))
		elif key == _sel_p2:
			style.border_color = Color(1.0, 0.35, 0.35)
			badge.text         = "P2"
			badge.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		else:
			badge.text = ""
			if is_focused:
				style.border_color = Color(0.9, 0.95, 1.0)
			else:
				style.border_color = Color(0.2, 0.25, 0.35, 0.6)


func _refresh_status() -> void:
	if not GeneralRules.is_multiplayer:
		_status_label.text = "Selecciona tu personaje para comenzar" if _sel_p1 == "" else \
				"¡%s listo para la aventura!" % GeneralRules.CHARACTER_NAMES[_sel_p1]
	else:
		if _sel_p1 == "":
			_status_label.text = "Jugador 1: elige tu personaje"
		elif _sel_p2 == "":
			_status_label.text = "Jugador 2: elige tu personaje"
		else:
			_status_label.text = "P1: %s  |  P2: %s" % [
				GeneralRules.CHARACTER_NAMES[_sel_p1],
				GeneralRules.CHARACTER_NAMES[_sel_p2]
			]


func _refresh_play_button() -> void:
	if not is_instance_valid(_play_panel) or not is_instance_valid(_play_click_btn):
		return
	var ready := _sel_p1 != "" and (not GeneralRules.is_multiplayer or _sel_p2 != "")
	_play_click_btn.disabled   = not ready
	_play_click_btn.focus_mode = Control.FOCUS_ALL if ready else Control.FOCUS_NONE
	_play_panel.modulate.a     = 1.0 if ready else 0.45

	_setup_focus_navigation(ready)


# ── Configuración de Vecinos de Foco (Mando / Teclado) ────────────────────────
func _setup_focus_navigation(ready: bool) -> void:
	if _card_buttons.size() < 4 or not is_instance_valid(_back_click_btn) or not is_instance_valid(_play_click_btn):
		return

	# Navegación horizontal en bucle entre las 4 tarjetas
	for i in range(4):
		var left_idx: int  = (i - 1 + 4) % 4
		var right_idx: int = (i + 1) % 4
		_card_buttons[i].focus_neighbor_left  = _card_buttons[left_idx].get_path()
		_card_buttons[i].focus_neighbor_right = _card_buttons[right_idx].get_path()

	# Tarjetas 0 y 1 van a "ATRÁS"
	_card_buttons[0].focus_neighbor_bottom = _back_click_btn.get_path()
	_card_buttons[0].focus_neighbor_top    = _back_click_btn.get_path()
	_card_buttons[1].focus_neighbor_bottom = _back_click_btn.get_path()
	_card_buttons[1].focus_neighbor_top    = _back_click_btn.get_path()

	# Tarjetas 2 y 3 van a "¡A JUGAR!" (si está listo) o a "ATRÁS"
	var target_btn: Button = _play_click_btn if ready else _back_click_btn
	_card_buttons[2].focus_neighbor_bottom = target_btn.get_path()
	_card_buttons[2].focus_neighbor_top    = target_btn.get_path()
	_card_buttons[3].focus_neighbor_bottom = target_btn.get_path()
	_card_buttons[3].focus_neighbor_top    = target_btn.get_path()

	# Navegación del botón "ATRÁS"
	_back_click_btn.focus_neighbor_top    = _card_buttons[0].get_path()
	_back_click_btn.focus_neighbor_bottom = _card_buttons[0].get_path()
	if ready:
		_back_click_btn.focus_neighbor_right = _play_click_btn.get_path()
		_back_click_btn.focus_neighbor_left  = _play_click_btn.get_path()

		_play_click_btn.focus_neighbor_left   = _back_click_btn.get_path()
		_play_click_btn.focus_neighbor_right  = _back_click_btn.get_path()
		_play_click_btn.focus_neighbor_top    = _card_buttons[2].get_path()
		_play_click_btn.focus_neighbor_bottom = _card_buttons[2].get_path()
	else:
		_back_click_btn.focus_neighbor_right = _card_buttons[0].get_path()
		_back_click_btn.focus_neighbor_left  = _card_buttons[3].get_path()


# ── Navegación entre Escenas ──────────────────────────────────────────────────
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Screens/main_menu.tscn")


func _on_play_pressed() -> void:
	GeneralRules.selected_character    = _sel_p1
	GeneralRules.selected_character_p2 = _sel_p2 if GeneralRules.is_multiplayer else ""
	get_tree().change_scene_to_file("res://Scenes/Screens/level_select.tscn")
