extends CharacterBody2D

# ─────────────────────────────────────────────────────────────────────────────
#  boss_mimic.gd
#  Lógica del jefe Cofre Mimic (Boss Mimic):
#  • Inicia visible en la sala en su forma de cofre cerrado ("idle_closed").
#  • Por defecto mira hacia la IZQUIERDA (los sprites originales miran a la derecha).
#  • Permanece inactivo hasta que el jugador se acerca a su rango de detección.
#  • Al acercarse el jugador:
#    1. Se abre ("opening").
#    2. Tras abrirse, se transforma ("transform").
#    3. Ya transformado, comienza a moverse y combatir ("walk", "attack_1", "attack_2").
#  • COMBATE:
#    - Se mueve persiguiendo al jugador por el suelo.
#    - Ejecuta ataques cuando está en rango (mordisco / lengüetazo con áreas de daño).
#    - DAÑO POR CONTACTO: Si el jugador choca contra su cuerpo sin aplastarlo, recibe daño.
#    - APLASTARLO (STOMP): Saltando sobre su cabeza se le inflige daño y rebota
#      limpiamente sin parpadeos ni daño al jugador.
#  • DERROTA: Al quedarse sin vida reproduce "death", otorga 50 puntos y desbloquea la sala.
# ─────────────────────────────────────────────────────────────────────────────

signal boss_defeated

@export var max_health: int = 5
@export var walk_speed: float = 110.0
@export var wake_distance: float = 190.0
@export var attack_range: float = 110.0
@export var attack_cooldown_time: float = 2.5

enum State {
	CLOSED_IDLE,    # Cofre cerrado esperando que el jugador se acerque
	OPENING,        # Abriéndose al detectar al jugador
	TRANSFORMING,   # Transformándose en monstruo
	COMBAT_WALK,    # Moviéndose y persiguiendo al jugador
	COMBAT_IDLE,    # Pausa breve entre movimientos
	ATTACK_1,       # Ataque 1 (Mordisco)
	ATTACK_2,       # Ataque 2 (Lengüetazo)
	HURT,           # Al recibir daño
	DEATH           # Secuencia de muerte
}

var state: State = State.CLOSED_IDLE
var health: int = 5
var is_invulnerable: bool = true
var direction: float = -1.0 # Mirando a la izquierda por defecto
var _attack_cooldown: float = 1.5
var _spawn_position: Vector2 = Vector2.ZERO

var _orig_atk1_pos: Vector2 = Vector2.ZERO
var _orig_atk2_pos: Vector2 = Vector2.ZERO

# Referencias a nodos hijos existentes en la escena
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var damage_attack_1_zone: Area2D = $damage_attack_1_zone
@onready var damage_attack_1_shape: CollisionShape2D = $damage_attack_1_zone/CollisionShape2D
@onready var damage_attack_2_zone: Area2D = $damage_attack_2_zone
@onready var damage_attack_2_shape: CollisionShape2D = $damage_attack_2_zone/CollisionShape2D

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _hp_bar: ProgressBar
var _stomp_area: Area2D
var _stomp_shape: CollisionShape2D
var _body_damage_area: Area2D
var _body_damage_shape: CollisionShape2D

func _ready() -> void:
	add_to_group("boss")
	_spawn_position = global_position
	health = max_health

	# Guardar posiciones originales de las áreas de ataque
	if damage_attack_1_zone:
		_orig_atk1_pos = damage_attack_1_zone.position
	if damage_attack_2_zone:
		_orig_atk2_pos = damage_attack_2_zone.position

	# Configurar animaciones que no deben repetirse en bucle
	if anim and anim.sprite_frames:
		anim.sprite_frames.set_animation_loop("opening", false)
		anim.sprite_frames.set_animation_loop("transform", false)
		anim.sprite_frames.set_animation_loop("attack_1", false)
		anim.sprite_frames.set_animation_loop("attack_2", false)
		anim.sprite_frames.set_animation_loop("hurt", false)
		anim.sprite_frames.set_animation_loop("death", false)

		anim.animation_finished.connect(_on_animation_finished)
		anim.frame_changed.connect(_on_anim_frame_changed)

	# Crear áreas de detección de aplastamiento y daño por contacto
	_create_stomp_area()
	_create_body_damage_area()
	_create_health_bar()

	# Iniciar como cofre cerrado mirando a la izquierda
	_set_closed_idle()

func _physics_process(delta: float) -> void:
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y += gravity * delta

	# 1. Estado cofre cerrado: vigilar distancia del jugador
	if state == State.CLOSED_IDLE:
		velocity.x = 0
		move_and_slide()

		var player := _get_nearest_player()
		if player != null:
			var dist: float = global_position.distance_to(player.global_position)
			if dist <= wake_distance:
				_wake_up()
		return

	# 2. Estados de apertura y transformación: no se mueve horizontalmente
	if state == State.OPENING or state == State.TRANSFORMING:
		velocity.x = 0
		move_and_slide()
		return

	# 3. Estado de muerte: se detiene
	if state == State.DEATH:
		velocity.x = move_toward(velocity.x, 0, 300.0 * delta)
		move_and_slide()
		return

	# 4. Estado de daño: retroceso breve
	if state == State.HURT:
		velocity.x = move_toward(velocity.x, 0, 400.0 * delta)
		move_and_slide()
		return

	# Control de enfriamiento de ataque
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	# 5. Estados de combate
	match state:
		State.COMBAT_WALK:
			_process_combat_walk(delta)
		State.COMBAT_IDLE:
			velocity.x = move_toward(velocity.x, 0, 300.0 * delta)
			move_and_slide()
		State.ATTACK_1, State.ATTACK_2:
			velocity.x = move_toward(velocity.x, 0, 500.0 * delta)
			move_and_slide()

# ─────────────────────────────────────────────────────────────────────────────
#  Despertar: Apertura y Transformación
# ─────────────────────────────────────────────────────────────────────────────
func _wake_up() -> void:
	if state != State.CLOSED_IDLE:
		return

	state = State.OPENING
	is_invulnerable = true

	# Orientarse hacia el jugador al abrirse
	var player := _get_nearest_player()
	if player != null:
		if player.global_position.x < global_position.x:
			direction = -1.0
		elif player.global_position.x > global_position.x:
			direction = 1.0
	_update_facing()

	anim.play("opening")

func _start_transforming() -> void:
	state = State.TRANSFORMING
	anim.play("transform")

func _finish_transformation() -> void:
	state = State.COMBAT_WALK
	is_invulnerable = false

	# Activar sistemas de combate
	_set_body_damage_active(true)
	if _stomp_area:
		_stomp_area.set_deferred("monitoring", true)
	if _hp_bar:
		_hp_bar.visible = true

	anim.play("walk")

# ─────────────────────────────────────────────────────────────────────────────
#  Movimiento en Combate (Walk) y Ataques
# ─────────────────────────────────────────────────────────────────────────────
func _process_combat_walk(_delta: float) -> void:
	var player := _get_nearest_player()

	if player != null:
		var diff_x: float = player.global_position.x - global_position.x
		var abs_diff_x: float = abs(diff_x)

		# Orientarse hacia el jugador
		if abs_diff_x > 15.0:
			direction = sign(diff_x)

		# Comprobar si puede atacar
		if abs_diff_x <= attack_range and _attack_cooldown <= 0.0 and is_on_floor():
			_choose_and_start_attack()
			return
	else:
		if is_on_wall():
			direction *= -1.0

	velocity.x = direction * walk_speed
	_update_facing()

	if anim.animation != "walk":
		anim.play("walk")

	move_and_slide()

func _choose_and_start_attack() -> void:
	# Alternar entre ataque 1 (mordisco) y ataque 2 (lengüetazo)
	var use_attack_2: bool = (randf() > 0.5)
	if use_attack_2:
		_start_attack_2()
	else:
		_start_attack_1()

func _start_attack_1() -> void:
	state = State.ATTACK_1
	velocity.x = 0
	_update_facing()
	_set_attack_zones_active(false)
	anim.play("attack_1")

func _start_attack_2() -> void:
	state = State.ATTACK_2
	velocity.x = 0
	_update_facing()
	_set_attack_zones_active(false)
	anim.play("attack_2")

# ─────────────────────────────────────────────────────────────────────────────
#  Orientación (Mirando a la izquierda por defecto)
# ─────────────────────────────────────────────────────────────────────────────
func _update_facing() -> void:
	if direction < 0:
		# Mirar a la izquierda (flip_h = true porque los sprites originales miran a la derecha)
		anim.flip_h = true
		if damage_attack_1_zone:
			damage_attack_1_zone.position.x = -abs(_orig_atk1_pos.x)
			damage_attack_1_zone.scale.x = -1.0
		if damage_attack_2_zone:
			damage_attack_2_zone.position.x = -abs(_orig_atk2_pos.x)
			damage_attack_2_zone.scale.x = -1.0
	elif direction > 0:
		# Mirar a la derecha (flip_h = false)
		anim.flip_h = false
		if damage_attack_1_zone:
			damage_attack_1_zone.position.x = abs(_orig_atk1_pos.x)
			damage_attack_1_zone.scale.x = 1.0
		if damage_attack_2_zone:
			damage_attack_2_zone.position.x = abs(_orig_atk2_pos.x)
			damage_attack_2_zone.scale.x = 1.0

# ─────────────────────────────────────────────────────────────────────────────
#  Sincronización por fotograma de las zonas de ataque
# ─────────────────────────────────────────────────────────────────────────────
func _on_anim_frame_changed() -> void:
	var f := anim.frame
	if state == State.ATTACK_1 and anim.animation == "attack_1":
		# attack_1 (Mordisco): activo del fotograma 9 al 13
		if f >= 9 and f <= 13:
			_set_attack_1_zone_active(true)
		else:
			_set_attack_1_zone_active(false)

	elif state == State.ATTACK_2 and anim.animation == "attack_2":
		# attack_2 (Lengüetazo): activo del fotograma 6 al 10
		if f >= 6 and f <= 10:
			_set_attack_2_zone_active(true)
		else:
			_set_attack_2_zone_active(false)

func _set_attack_zones_active(active: bool) -> void:
	_set_attack_1_zone_active(active)
	_set_attack_2_zone_active(active)

func _set_attack_1_zone_active(active: bool) -> void:
	if damage_attack_1_zone:
		damage_attack_1_zone.monitoring = active
	if damage_attack_1_shape:
		damage_attack_1_shape.set_deferred("disabled", not active)

func _set_attack_2_zone_active(active: bool) -> void:
	if damage_attack_2_zone:
		damage_attack_2_zone.monitoring = active
	if damage_attack_2_shape:
		damage_attack_2_shape.set_deferred("disabled", not active)

# ─────────────────────────────────────────────────────────────────────────────
#  Daño por Contacto Corporal
# ─────────────────────────────────────────────────────────────────────────────
func _create_body_damage_area() -> void:
	_body_damage_area = Area2D.new()
	_body_damage_area.name = "BodyContactDamage"
	_body_damage_area.collision_layer = 0   # No activar damage_detection del jugador automáticamente
	_body_damage_area.collision_mask = 16   # Detecta "damage_detection" del jugador
	_body_damage_area.monitoring = true

	_body_damage_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	_body_damage_shape.shape = circle
	_body_damage_shape.position = Vector2(0, 3)

	_body_damage_area.add_child(_body_damage_shape)
	add_child(_body_damage_area)

	_body_damage_area.area_entered.connect(_on_body_damage_area_entered)
	_body_damage_area.body_entered.connect(_on_body_damage_body_entered)

func _set_body_damage_active(active: bool) -> void:
	if _body_damage_area:
		_body_damage_area.monitoring = active
	if _body_damage_shape:
		_body_damage_shape.set_deferred("disabled", not active)

func _on_body_damage_area_entered(area: Area2D) -> void:
	if state == State.CLOSED_IDLE or state == State.OPENING or state == State.TRANSFORMING or state == State.DEATH or is_invulnerable:
		return
	var player := _extract_player(area)
	if player == null:
		return

	if player.has_method("apply_damage"):
		player.apply_damage(10, global_position)

func _on_body_damage_body_entered(body: Node2D) -> void:
	if state == State.CLOSED_IDLE or state == State.OPENING or state == State.TRANSFORMING or state == State.DEATH or is_invulnerable:
		return
	var player := _extract_player(body)
	if player == null:
		return

	if player.has_method("apply_damage"):
		player.apply_damage(10, global_position)

# ─────────────────────────────────────────────────────────────────────────────
#  Detector de Aplastamiento en la Cabeza (Stomp / Salto sobre el Jefe)
# ─────────────────────────────────────────────────────────────────────────────
func _create_stomp_area() -> void:
	_stomp_area = Area2D.new()
	_stomp_area.name = "StompDetector"
	_stomp_area.collision_layer = 0
	_stomp_area.collision_mask = 0xFFFFFFFF

	_stomp_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 6)
	_stomp_shape.shape = rect
	# Posicionado exclusivamente en la cima de la cabeza
	_stomp_shape.position = Vector2(0, -11)

	_stomp_area.add_child(_stomp_shape)
	add_child(_stomp_area)

	_stomp_area.body_entered.connect(_on_stomp_node_entered)
	_stomp_area.area_entered.connect(_on_stomp_node_entered)

func _extract_player(node: Node) -> CharacterBody2D:
	if node is CharacterBody2D and node.is_in_group("player"):
		return node
	if node != null and node.get_parent() is CharacterBody2D and node.get_parent().is_in_group("player"):
		return node.get_parent()
	return null

func _is_valid_stomp(player: CharacterBody2D) -> bool:
	if player == null:
		return false
	# No es pisotón si el jugador camina sobre el suelo (chocar de frente hace daño)
	if player.is_on_floor():
		return false
	# Debe estar cayendo en el aire
	if player.velocity.y <= 10.0:
		return false
	# Debe estar claramente por encima de la cima del cofre
	if player.global_position.y >= (global_position.y - 6.0):
		return false
	return true

func _trigger_stomp(player: CharacterBody2D) -> void:
	if state == State.CLOSED_IDLE or state == State.OPENING or state == State.TRANSFORMING or state == State.DEATH or is_invulnerable:
		return

	# 1. El jugador rebota con fuerza hacia arriba
	player.velocity.y = -480.0
	if "had_jump" in player:
		player.had_jump = true
	if "count_jumps" in player:
		player.count_jumps = 1

	# Asegurar que el personaje conserve su apariencia normal sin parpadear
	if "modulate" in player:
		player.modulate.a = 1.0

	# 2. Desactivar temporalmente el daño por contacto del cuerpo y zonas de ataque durante el rebote
	_set_body_damage_active(false)
	_set_attack_zones_active(false)
	get_tree().create_timer(0.4).timeout.connect(func():
		if state != State.DEATH and state != State.CLOSED_IDLE and state != State.OPENING and state != State.TRANSFORMING:
			_set_body_damage_active(true)
	)

	# 3. Dañar al jefe
	take_damage(1)

func _on_stomp_node_entered(node: Node2D) -> void:
	if state == State.CLOSED_IDLE or state == State.OPENING or state == State.TRANSFORMING or state == State.DEATH or is_invulnerable:
		return

	var player := _extract_player(node)
	if player == null:
		return

	if _is_valid_stomp(player):
		_trigger_stomp(player)

# ─────────────────────────────────────────────────────────────────────────────
#  Daño y Derrota del Mimic
# ─────────────────────────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if state == State.DEATH or is_invulnerable or state == State.CLOSED_IDLE or state == State.OPENING or state == State.TRANSFORMING:
		return

	health -= amount
	_update_health_bar()
	_set_attack_zones_active(false)

	if health <= 0:
		_die()
		return

	state = State.HURT
	is_invulnerable = true
	anim.play("hurt")

	# Efecto de parpadeo rojo al recibir daño el jefe
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 0.2, 0.2, 0.8), 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	tween.tween_property(self, "modulate", Color(1.0, 0.2, 0.2, 0.8), 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)

	var inv_timer := get_tree().create_timer(0.6)
	inv_timer.timeout.connect(func():
		is_invulnerable = false
		modulate = Color.WHITE
	)

func _die() -> void:
	state = State.DEATH
	is_invulnerable = true
	velocity = Vector2.ZERO
	_set_attack_zones_active(false)
	_set_body_damage_active(false)

	if body_shape:
		body_shape.set_deferred("disabled", true)
	if _stomp_area:
		_stomp_area.set_deferred("monitoring", false)
	if _hp_bar:
		_hp_bar.visible = false

	# Reproducir la animación de muerte
	anim.play("death")

	# Notificar a las reglas globales y desbloquear la sala del jefe
	_notify_boss_defeated()
	GeneralRules.add_fruit_points(50)
	boss_defeated.emit()

	# Esperar a que la animación de muerte concluya
	if anim.is_playing() and anim.animation == "death":
		await anim.animation_finished
	else:
		await get_tree().create_timer(0.9).timeout

	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.8)
	fade_tween.tween_callback(queue_free)

func _notify_boss_defeated() -> void:
	var parent_node = get_parent()
	while parent_node != null:
		if parent_node.has_method("unlock_boss_zone"):
			parent_node.unlock_boss_zone()
			return
		parent_node = parent_node.get_parent()

	get_tree().call_group("boss_zone_controller", "unlock_boss_zone")

# ─────────────────────────────────────────────────────────────────────────────
#  Barra de Vida Flotante
# ─────────────────────────────────────────────────────────────────────────────
func _create_health_bar() -> void:
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "BossHealthBar"
	_hp_bar.custom_minimum_size = Vector2(32, 4)
	_hp_bar.position = Vector2(-16, -20)
	_hp_bar.max_value = max_health
	_hp_bar.value = health
	_hp_bar.show_percentage = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	bg_style.set_corner_radius_all(2)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.85, 0.35, 1.0)
	fill_style.set_corner_radius_all(2)

	_hp_bar.add_theme_stylebox_override("background", bg_style)
	_hp_bar.add_theme_stylebox_override("fill", fill_style)
	add_child(_hp_bar)

func _update_health_bar() -> void:
	if _hp_bar:
		_hp_bar.value = health
		var fill: StyleBoxFlat = _hp_bar.get_theme_stylebox("fill")
		if fill:
			if health <= 2:
				fill.bg_color = Color(0.9, 0.2, 0.2)
			elif health <= 3:
				fill.bg_color = Color(1.0, 0.75, 0.15)
			else:
				fill.bg_color = Color(0.2, 0.85, 0.35)

# ─────────────────────────────────────────────────────────────────────────────
#  Manejo de Fin de Animaciones
# ─────────────────────────────────────────────────────────────────────────────
func _on_animation_finished() -> void:
	match state:
		State.OPENING:
			# Al terminar de abrirse, se transforma
			_start_transforming()
		State.TRANSFORMING:
			# Al terminar de transformarse, comienza a moverse y atacar
			_finish_transformation()
		State.ATTACK_1, State.ATTACK_2:
			_set_attack_zones_active(false)
			_attack_cooldown = attack_cooldown_time
			state = State.COMBAT_WALK
			anim.play("walk")
		State.HURT:
			state = State.COMBAT_WALK
			anim.play("walk")

# ─────────────────────────────────────────────────────────────────────────────
#  Activación y Reinicio
# ─────────────────────────────────────────────────────────────────────────────
func activate_boss() -> void:
	# boss_zone puede llamar a activate_boss cuando el jugador entra al cuarto
	# Si ya está abierto o transformándose, no hace nada
	if state == State.CLOSED_IDLE:
		# Si el jugador ya está cerca, despierta inmediatamente
		var player := _get_nearest_player()
		if player != null and global_position.distance_to(player.global_position) <= wake_distance:
			_wake_up()

func reset_boss() -> void:
	if state == State.DEATH:
		return
	global_position = _spawn_position
	velocity = Vector2.ZERO
	health = max_health
	modulate = Color.WHITE
	_update_health_bar()
	_set_closed_idle()

func _set_closed_idle() -> void:
	state = State.CLOSED_IDLE
	visible = true
	is_invulnerable = true
	direction = -1.0 # Mirando a la izquierda por defecto
	_update_facing()

	_set_attack_zones_active(false)
	_set_body_damage_active(false)

	if body_shape:
		body_shape.set_deferred("disabled", false)
	if _stomp_area:
		_stomp_area.set_deferred("monitoring", false)
	if _hp_bar:
		_hp_bar.visible = false

	if anim:
		anim.play("idle_closed")

# ─────────────────────────────────────────────────────────────────────────────
#  Búsqueda de Jugador
# ─────────────────────────────────────────────────────────────────────────────
func _get_nearest_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	var nearest: Node2D = null
	var min_dist: float = INF

	for p in players:
		if p is CharacterBody2D:
			var dead: bool = p.get("is_dead") if "is_dead" in p else false
			if dead:
				continue
			var d: float = global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				nearest = p

	return nearest
