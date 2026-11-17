extends Control

# ─────────────────────────────────────────────────────────────────────────────
#  level_transition.gd
#  Pantalla de transición entre niveles estilo arcade / plataformas retro.
#  Muestra el Mundo (1 a 4), el Nivel (1 a 3), la animación del personaje
#  y realiza un fade suave hacia el siguiente nivel.
#  Soporta mando (Botón A / Start), teclado (Espacio / Enter) y ratón para
#  continuar de inmediato o esperar la cuenta regresiva (~2.2 s).
# ─────────────────────────────────────────────────────────────────────────────

const SCREEN_W := 1152.0
const SCREEN_H := 648.0
const TRANSITION_DURATION := 2.2

var _world_num: int = 1
var _level_num: int = 1
var _target_path: String = ""
var _is_transitioning: bool = false
var _level_exists: bool = true

var _fade_overlay: ColorRect
var _progress_bar: ProgressBar
var _prompt_label: Label
var _time_elapsed: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = Vector2(SCREEN_W, SCREEN_H)

	_target_path = GeneralRules.target_scene_path
	if _target_path.is_empty():
		_target_path = GeneralRules.get_level_scene_path(GeneralRules.current_world, GeneralRules.current_level)

	_target_path = GeneralRules.resolve_scene_path(_target_path)

	# Extraer mundo y nivel precisos desde la ruta destino
	var coords := GeneralRules.extract_world_and_level(_target_path)
	if coords.x > 0 and coords.y > 0:
		_world_num = coords.x
		_level_num = coords.y
		GeneralRules.current_world = _world_num
		GeneralRules.current_level = _level_num
	else:
		_world_num = GeneralRules.current_world
		_level_num = GeneralRules.current_level

	_level_exists = ResourceLoader.exists(_target_path) and _world_num <= GeneralRules.MAX_WORLDS

	_build_ui()
	_play_fade_in()


func _process(delta: float) -> void:
	if _is_transitioning or not _level_exists:
		return

	_time_elapsed += delta
	if is_instance_valid(_progress_bar):
		_progress_bar.value = clampf((_time_elapsed / TRANSITION_DURATION) * 100.0, 0.0, 100.0)

	if _time_elapsed >= TRANSITION_DURATION:
		_start_level()


func _input(event: InputEvent) -> void:
	if _is_transitioning:
		return

	# Si el nivel no existe, la tecla de escape o B regresa al menú
	if not _level_exists:
		if event.is_action_pressed("ui_cancel") or \
		   (event is InputEventJoypadButton and event.is_pressed() and event.button_index == JOY_BUTTON_B):
			get_viewport().set_input_as_handled()
			_on_menu_pressed()
		return

	# Saltar cuenta regresiva con Botón A, Start, Espacio, Enter o clic
	var is_confirm := false
	if event is InputEventJoypadButton and event.is_pressed():
		if event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_X:
			is_confirm = true
	elif event.is_action_pressed("ui_accept"):
		is_confirm = true
	elif event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		is_confirm = true

	if is_confirm:
		get_viewport().set_input_as_handled()
		_start_level()


func _start_level() -> void:
	if _is_transitioning or not _level_exists:
		return
	_is_transitioning = true

	# Fade out hacia negro y carga de la escena
	var tw := create_tween()
	tw.tween_property(_fade_overlay, "modulate:a", 1.0, 0.3)
	tw.finished.connect(func():
		get_tree().change_scene_to_file(_target_path)
	)


func _build_ui() -> void:
	# ── Fondo temático del mundo en mosaico ───────────────────────────────────
	var bg_path: String = GeneralRules.WORLD_BACKGROUNDS.get(_world_num, "res://Assets/Background/Green.png")
	var bg_tex: Texture2D = load(bg_path) if ResourceLoader.exists(bg_path) else preload("res://Assets/Background/Green.png")

	var bg := TextureRect.new()
	bg.texture = bg_tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Velo oscuro para contraste retro
	var tint := ColorRect.new()
	tint.color = Color(0.02, 0.04, 0.08, 0.72)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tint)

	# ── CenterContainer principal ─────────────────────────────────────────────
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 20)
	center.add_child(main_vbox)

	# ── Encabezado: Título de Mundo y Nivel ────────────────────────────────────
	var header_vbox := VBoxContainer.new()
	header_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	header_vbox.add_theme_constant_override("separation", 4)
	main_vbox.add_child(header_vbox)

	if _level_exists:
		var world_title := Label.new()
		world_title.text = "★ MUNDO %d ★" % _world_num
		world_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		world_title.add_theme_font_size_override("font_size", 46)
		world_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
		world_title.add_theme_color_override("font_shadow_color", Color(0.08, 0.04, 0.0, 0.95))
		world_title.add_theme_constant_override("shadow_offset_x", 3)
		world_title.add_theme_constant_override("shadow_offset_y", 3)
		header_vbox.add_child(world_title)

		var world_subtitle := Label.new()
		world_subtitle.text = GeneralRules.WORLD_NAMES.get(_world_num, "TIERRA DESCONOCIDA")
		world_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		world_subtitle.add_theme_font_size_override("font_size", 16)
		world_subtitle.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 0.9))
		world_subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		world_subtitle.add_theme_constant_override("shadow_offset_x", 2)
		world_subtitle.add_theme_constant_override("shadow_offset_y", 2)
		header_vbox.add_child(world_subtitle)

		var level_title := Label.new()
		level_title.text = "NIVEL %d - %d" % [_world_num, _level_num]
		level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_title.add_theme_font_size_override("font_size", 30)
		level_title.add_theme_color_override("font_color", Color.WHITE)
		level_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		level_title.add_theme_constant_override("shadow_offset_x", 2)
		level_title.add_theme_constant_override("shadow_offset_y", 2)
		header_vbox.add_child(level_title)
	else:
		var victory_title := Label.new()
		if _world_num > GeneralRules.MAX_WORLDS:
			victory_title.text = "🏆 ¡HAS COMPLETADO EL JUEGO! 🏆"
		else:
			victory_title.text = "★ MUNDO %d - PRÓXIMAMENTE ★" % _world_num
		victory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		victory_title.add_theme_font_size_override("font_size", 38)
		victory_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
		victory_title.add_theme_color_override("font_shadow_color", Color(0.08, 0.04, 0.0, 0.95))
		victory_title.add_theme_constant_override("shadow_offset_x", 3)
		victory_title.add_theme_constant_override("shadow_offset_y", 3)
		header_vbox.add_child(victory_title)

		var notice := Label.new()
		notice.text = "Este nivel aún se encuentra en construcción."
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice.add_theme_font_size_override("font_size", 18)
		notice.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
		header_vbox.add_child(notice)

	# ── Presentación de Personajes (Sprites animados) ─────────────────────────
	var chars_hbox := HBoxContainer.new()
	chars_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	chars_hbox.add_theme_constant_override("separation", 36)
	main_vbox.add_child(chars_hbox)

	var p1_key := GeneralRules.selected_character
	if p1_key.is_empty():
		p1_key = "ninja_frog"

	if not GeneralRules.is_multiplayer:
		_build_char_badge(chars_hbox, p1_key, "JUGADOR 1", Color(0.25, 0.65, 1.0))
	else:
		var p2_key := GeneralRules.selected_character_p2
		if p2_key.is_empty():
			p2_key = "pink_man"
		_build_char_badge(chars_hbox, p1_key, "JUGADOR 1", Color(0.25, 0.65, 1.0))
		_build_char_badge(chars_hbox, p2_key, "JUGADOR 2", Color(1.0, 0.35, 0.35))

	# ── Barra inferior o botón de retorno ─────────────────────────────────────
	if _level_exists:
		var footer_vbox := VBoxContainer.new()
		footer_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		footer_vbox.add_theme_constant_override("separation", 8)
		main_vbox.add_child(footer_vbox)

		# Barra de progreso de carga
		_progress_bar = ProgressBar.new()
		_progress_bar.custom_minimum_size = Vector2(320, 10)
		_progress_bar.show_percentage = false
		_progress_bar.value = 0.0

		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.1, 0.12, 0.18, 0.8)
		bar_bg.set_corner_radius_all(5)
		var bar_fg := StyleBoxFlat.new()
		bar_fg.bg_color = Color(0.2, 0.85, 0.45)
		bar_fg.set_corner_radius_all(5)
		_progress_bar.add_theme_stylebox_override("background", bar_bg)
		_progress_bar.add_theme_stylebox_override("fill", bar_fg)
		footer_vbox.add_child(_progress_bar)

		# Indicador de salto
		_prompt_label = Label.new()
		_prompt_label.text = "Presiona A o Espacio para continuar ➔"
		_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt_label.add_theme_font_size_override("font_size", 14)
		_prompt_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.75))
		footer_vbox.add_child(_prompt_label)

		# Animación parpadeante en el prompt
		var pulse_tw := create_tween().set_loops()
		pulse_tw.tween_property(_prompt_label, "modulate:a", 0.3, 0.6)
		pulse_tw.tween_property(_prompt_label, "modulate:a", 1.0, 0.6)
	else:
		# Botón para volver al menú si no existe el nivel
		var btn := Button.new()
		btn.text = "VOLVER AL MENÚ"
		btn.custom_minimum_size = Vector2(220, 48)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_on_menu_pressed)
		main_vbox.add_child(btn)
		btn.call_deferred("grab_focus")

	# ── Capa de fade negro ────────────────────────────────────────────────────
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color.BLACK
	_fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_overlay)


# ── Construye la tarjeta animada del personaje ────────────────────────────────
func _build_char_badge(parent: Control, char_key: String, player_label: String, accent_color: Color) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 180)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.88)
	style.border_color = accent_color
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var tag := Label.new()
	tag.text = player_label
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", accent_color)
	vbox.add_child(tag)

	# Instanciar el AnimatedSprite2D del personaje
	var scene_path: String = GeneralRules.CHARACTER_SCENES.get(char_key, "")
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var packed: PackedScene = load(scene_path)
		var inst = packed.instantiate()
		var orig_anim: AnimatedSprite2D = inst.get_node_or_null("animaciones")

		if orig_anim != null:
			var anim := AnimatedSprite2D.new()
			anim.sprite_frames = orig_anim.sprite_frames
			anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			anim.scale = Vector2(3.5, 3.5)
			anim.position = Vector2(70, 55)

			# Reproduce la animación 'run' para darle dinamismo de avance
			if anim.sprite_frames.has_animation("run"):
				anim.play("run")
			else:
				anim.play("idle")

			var sprite_box := Control.new()
			sprite_box.custom_minimum_size = Vector2(140, 95)
			sprite_box.add_child(anim)
			vbox.add_child(sprite_box)

		inst.queue_free()

	var char_name := Label.new()
	char_name.text = GeneralRules.CHARACTER_NAMES.get(char_key, char_key.capitalize())
	char_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_name.add_theme_font_size_override("font_size", 14)
	char_name.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(char_name)

	parent.add_child(panel)


func _play_fade_in() -> void:
	_fade_overlay.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade_overlay, "modulate:a", 0.0, 0.3)


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Screens/main_menu.tscn")
