extends CharacterBody2D

# ─────────────────────────────────────────────────────────────────────────────
#  boss_bat.gd
#  Lógica del jefe Murciélago Volador (Boss Bat):
#  • Inicia inactivo/oculto hasta que el jugador entra a la zona del jefe.
#  • Al activarse, aparece con la animación "appearing".
#  • Vuela por toda el área de combate en un patrón sinusoidal amplio con
#    ataques en picada (swoop) hacia el jugador.
#  • DAÑO POR CONTACTO: Si el jugador choca con su cuerpo, recibe daño.
#  • APLASTARLO (STOMP): La ÚNICA forma de no recibir daño y herirlo es
#    saltando/cayendo sobre su cabeza, lo que hace rebotar al jugador y le resta vida al jefe.
#  • SECUENCIA DE MUERTE: Al morir reproduce en orden estricto:
#    1. "fly-to-fall" (se tambalea en el aire)
#    2. "fall" (cae en picada por gravedad hasta tocar el suelo)
#    3. "death" (impacta y muere en el suelo)
#  • Al morir desbloquea la sala del jefe y otorga 50 puntos.
# ─────────────────────────────────────────────────────────────────────────────

signal boss_defeated

@export var max_health: int = 5
@export var fly_speed: float = 230.0
@export var wave_frequency: float = 2.5
@export var wave_amplitude: float = 85.0
@export var attack_range: float = 220.0
@export var attack_cooldown_time: float = 2.5
@export var attack_active_frame: int = 7

enum State { INACTIVE, APPEARING, FLY, ATTACK, HURT, DEATH_FLY_TO_FALL, DEATH_FALL, DEATH_FINAL }

var state: State = State.INACTIVE
var health: int = 5
var is_invulnerable: bool = false
var direction: float = 1.0
var _attack_cooldown: float = 2.0
var _orig_damage_zone_x: float = 24.67
var _spawn_position: Vector2 = Vector2.ZERO
var _base_altitude_y: float = 0.0
var _flight_time: float = 0.0
var _swoop_target: Vector2 = Vector2.ZERO

# Referencias a nodos hijos existentes
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_zone: Area2D = $damage_zone
@onready var damage_shape: CollisionShape2D = $damage_zone/CollisionShape2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _hp_bar: ProgressBar
var _stomp_area: Area2D
var _stomp_shape: CollisionShape2D
var _body_damage_area: Area2D
var _body_damage_shape: CollisionShape2D

func _ready() -> void:
	add_to_group("boss")
	_spawn_position = global_position
	_base_altitude_y = global_position.y
	health = max_health

	if damage_shape:
		_orig_damage_zone_x = abs(damage_shape.position.x)

	# Configurar animaciones de una sola reproducción
	if anim and anim.sprite_frames:
		anim.sprite_frames.set_animation_loop("appearing", false)
		anim.sprite_frames.set_animation_loop("attack", false)
		anim.sprite_frames.set_animation_loop("hurt", false)
		anim.sprite_frames.set_animation_loop("fly-to-fall", false)
		anim.sprite_frames.set_animation_loop("death", false)
		anim.sprite_frames.set_animation_speed("attack", 10.0)
		anim.animation_finished.connect(_on_animation_finished)
		anim.frame_changed.connect(_on_anim_frame_changed)

	# Crear detector de aplastamiento en la cabeza y daño por contacto
	_create_stomp_area()
	_create_body_damage_area()
	_create_health_bar()

	_set_damage_zone_active(false)
	_set_inactive()

	# Si se prueba directamente con F6 en Godot, auto-activar
	if get_parent() == get_tree().root:
		get_tree().create_timer(0.3).timeout.connect(activate_boss)

func _physics_process(delta: float) -> void:
	if state == State.INACTIVE:
		return

	# Estado de caída durante la secuencia de muerte
	if state == State.DEATH_FALL:
		velocity.y += gravity * delta
		velocity.x = move_toward(velocity.x, 0, 200.0 * delta)
		move_and_slide()
		if is_on_floor():
			_on_hit_floor_dead()
		return

	if state == State.DEATH_FLY_TO_FALL or state == State.DEATH_FINAL:
		velocity = velocity.move_toward(Vector2.ZERO, 300.0 * delta)
		move_and_slide()
		return

	if state == State.APPEARING:
		velocity = Vector2.ZERO
		return

	# Control de enfriamiento de ataque
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	match state:
		State.FLY:
			_process_fly(delta)
		State.ATTACK:
			_process_attack_swoop(delta)
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			move_and_slide()

# ─────────────────────────────────────────────────────────────────────────────
#  Vuelo por toda el área (Fly)
# ─────────────────────────────────────────────────────────────────────────────
func _process_fly(delta: float) -> void:
	_flight_time += delta

	# Movimiento horizontal patrullando el área
	if is_on_wall():
		direction *= -1.0

	velocity.x = direction * fly_speed

	# Movimiento vertical ondulante (vuelo suave)
	var target_y: float = _base_altitude_y + sin(_flight_time * wave_frequency) * wave_amplitude
	velocity.y = (target_y - global_position.y) * 3.2

	_update_facing()

	if anim.animation != "fly":
		anim.play("fly")

	move_and_slide()

	# Chequear si está cerca del jugador para hacer un ataque en picada
	var player := _get_nearest_player()
	if player != null and _attack_cooldown <= 0.0:
		var dist := global_position.distance_to(player.global_position)
		if dist <= attack_range:
			_start_attack(player.global_position)

func _update_facing() -> void:
	if direction < 0:
		anim.flip_h = true
		if damage_shape:
			damage_shape.position.x = -_orig_damage_zone_x
	elif direction > 0:
		anim.flip_h = false
		if damage_shape:
			damage_shape.position.x = _orig_damage_zone_x

# ─────────────────────────────────────────────────────────────────────────────
#  Ataque en picada (Attack Swoop)
#  10 FPS, 11 fotogramas, la zona de daño se activa desde el fotograma 7
# ─────────────────────────────────────────────────────────────────────────────
func _start_attack(target_pos: Vector2) -> void:
	state = State.ATTACK
	_swoop_target = target_pos
	if target_pos.x < global_position.x:
		direction = -1.0
	elif target_pos.x > global_position.x:
		direction = 1.0
	_update_facing()

	# Mantener la zona de daño apagada al inicio (fotogramas 0 a 6 son preparación)
	_set_damage_zone_active(false)
	anim.play("attack")

	# Impulso rápido hacia la posición del jugador
	var dir_to_player := (target_pos - global_position).normalized()
	velocity = dir_to_player * (fly_speed * 1.9)

func _on_anim_frame_changed() -> void:
	if state == State.ATTACK and anim.animation == "attack":
		var f := anim.frame
		# Activar la zona de daño a partir del fotograma 7
		if f >= attack_active_frame:
			_set_damage_zone_active(true)
		else:
			_set_damage_zone_active(false)

func _process_attack_swoop(delta: float) -> void:
	# El murciélago se abalanza hacia el objetivo del ataque
	move_and_slide()
	if is_on_wall() or is_on_floor():
		velocity.x *= -1.0

# ─────────────────────────────────────────────────────────────────────────────
#  Activación y Reinicio
# ─────────────────────────────────────────────────────────────────────────────
func activate_boss() -> void:
	if state != State.INACTIVE:
		return

	state = State.APPEARING
	visible = true
	is_invulnerable = true
	velocity = Vector2.ZERO

	if body_shape:
		body_shape.set_deferred("disabled", false)
	_set_damage_zone_active(false)
	_set_body_damage_active(false)

	if _stomp_area:
		_stomp_area.set_deferred("monitoring", false)

	if anim:
		anim.play("appearing")

func reset_boss() -> void:
	if state >= State.DEATH_FLY_TO_FALL:
		return
	_set_inactive()
	global_position = _spawn_position
	velocity = Vector2.ZERO
	health = max_health
	_update_health_bar()
	modulate = Color.WHITE

func _set_inactive() -> void:
	state = State.INACTIVE
	visible = false
	is_invulnerable = true
	_set_damage_zone_active(false)
	_set_body_damage_active(false)

	if body_shape:
		body_shape.set_deferred("disabled", true)
	if _stomp_area:
		_stomp_area.set_deferred("monitoring", false)
	if _hp_bar:
		_hp_bar.visible = false

# ─────────────────────────────────────────────────────────────────────────────
#  Daño por Contacto Corporal
# ─────────────────────────────────────────────────────────────────────────────
func _create_body_damage_area() -> void:
	_body_damage_area = Area2D.new()
	_body_damage_area.name = "BodyContactDamage"
	_body_damage_area.collision_layer = 0   # No activar damage_detection del jugador directamente
	_body_damage_area.collision_mask = 16   # Detecta "damage_detection" del jugador
	_body_damage_area.monitoring = true

	_body_damage_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	_body_damage_shape.shape = circle
	_body_damage_shape.position = Vector2(0, 11)

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
	if state >= State.DEATH_FLY_TO_FALL or is_invulnerable or state == State.INACTIVE or state == State.APPEARING:
		return
	var player := _extract_player(area)
	if player == null:
		return

	if player.has_method("apply_damage"):
		player.apply_damage(10, global_position)

func _on_body_damage_body_entered(body: Node2D) -> void:
	if state >= State.DEATH_FLY_TO_FALL or is_invulnerable or state == State.INACTIVE or state == State.APPEARING:
		return
	var player := _extract_player(body)
	if player == null:
		return

	if player.has_method("apply_damage"):
		player.apply_damage(10, global_position)

func _set_damage_zone_active(active: bool) -> void:
	if damage_zone:
		damage_zone.monitoring = active
	if damage_shape:
		damage_shape.set_deferred("disabled", not active)

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
	rect.size = Vector2(26, 8)
	_stomp_shape.shape = rect
	# Posicionado exclusivamente en la cima de la cabeza
	_stomp_shape.position = Vector2(0, -7)

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
	# El jugador no puede aplastar si está en el suelo caminando
	if player.is_on_floor():
		return false
	# Debe estar en el aire cayendo (velocidad vertical hacia abajo positiva)
	if player.velocity.y <= 10.0:
		return false
	# Debe estar por encima de la cima del murciélago
	if player.global_position.y >= (global_position.y - 6.0):
		return false
	return true

func _trigger_stomp(player: CharacterBody2D) -> void:
	if state >= State.DEATH_FLY_TO_FALL or is_invulnerable or state == State.INACTIVE or state == State.APPEARING:
		return

	# 1. Rebote potente del jugador
	player.velocity.y = -480.0
	if "had_jump" in player:
		player.had_jump = true
	if "count_jumps" in player:
		player.count_jumps = 1

	# Asegurar que el personaje conserve su apariencia normal sin parpadear
	if "modulate" in player:
		player.modulate.a = 1.0

	# 2. Desactivar temporalmente daño corporal y zona de ataque durante el rebote
	_set_body_damage_active(false)
	_set_damage_zone_active(false)
	get_tree().create_timer(0.4).timeout.connect(func():
		if state < State.DEATH_FLY_TO_FALL and state != State.INACTIVE and state != State.APPEARING:
			_set_body_damage_active(true)
	)

	# 3. Dañar al jefe
	take_damage(1)

func _on_stomp_node_entered(node: Node2D) -> void:
	if state >= State.DEATH_FLY_TO_FALL or is_invulnerable or state == State.INACTIVE or state == State.APPEARING:
		return

	var player := _extract_player(node)
	if player == null:
		return

	if _is_valid_stomp(player):
		_trigger_stomp(player)

# ─────────────────────────────────────────────────────────────────────────────
#  Daño y Secuencia de Muerte en 3 Fases:
#  1. "fly-to-fall" (en el aire)
#  2. "fall" (caída por gravedad hasta tocar el suelo)
#  3. "death" (impacta y muere en el suelo)
# ─────────────────────────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if state >= State.DEATH_FLY_TO_FALL or is_invulnerable or state == State.INACTIVE:
		return

	health -= amount
	_update_health_bar()
	_set_damage_zone_active(false)

	if health <= 0:
		_start_death_sequence()
		return

	state = State.HURT
	is_invulnerable = true
	anim.play("hurt")

	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 0.2, 0.2, 0.8), 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	tween.tween_property(self, "modulate", Color(1.0, 0.2, 0.2, 0.8), 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)

	var inv_timer := get_tree().create_timer(0.7)
	inv_timer.timeout.connect(func():
		is_invulnerable = false
		modulate = Color.WHITE
	)

func _start_death_sequence() -> void:
	_set_damage_zone_active(false)
	_set_body_damage_active(false)

	if _stomp_area:
		_stomp_area.set_deferred("monitoring", false)
	if _hp_bar:
		_hp_bar.visible = false

	# FASE 1: "fly-to-fall" (se desestabiliza en el aire)
	state = State.DEATH_FLY_TO_FALL
	velocity = Vector2(0, -60.0) # Pequeño respingo al perder sustentación

	if anim.sprite_frames.has_animation("fly-to-fall"):
		anim.play("fly-to-fall")
	elif anim.sprite_frames.has_animation("fly to fall"):
		anim.play("fly to fall")
	else:
		_start_falling()

func _start_falling() -> void:
	# FASE 2: "fall" (cae hacia el suelo por gravedad)
	state = State.DEATH_FALL
	velocity.y = 80.0
	if anim.sprite_frames.has_animation("fall"):
		anim.play("fall")
	else:
		_on_hit_floor_dead()

func _on_hit_floor_dead() -> void:
	if state == State.DEATH_FINAL:
		return

	# FASE 3: "death" o "dead" (al chocar contra el suelo)
	state = State.DEATH_FINAL
	velocity = Vector2.ZERO

	if body_shape:
		body_shape.set_deferred("disabled", true)

	var death_anim := "death" if anim.sprite_frames.has_animation("death") else "dead"
	if anim.sprite_frames.has_animation(death_anim):
		anim.play(death_anim)

	# Desbloquear la sala del jefe
	_notify_boss_defeated()
	GeneralRules.add_fruit_points(50)
	boss_defeated.emit()

	var count: int = anim.sprite_frames.get_frame_count(death_anim) if anim.sprite_frames.has_animation(death_anim) else 4
	var fps: float = anim.sprite_frames.get_animation_speed(death_anim) if anim.sprite_frames.has_animation(death_anim) else 7.0
	var dur: float = float(count) / maxf(fps, 1.0)
	await get_tree().create_timer(dur).timeout

	var fade_tween := create_tween()
	fade_tween.tween_interval(0.4)
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.7)
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
#  Barra de Vida
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
#  Fin de Animaciones
# ─────────────────────────────────────────────────────────────────────────────
func _on_animation_finished() -> void:
	if state == State.APPEARING:
		state = State.FLY
		is_invulnerable = false
		if body_shape:
			body_shape.set_deferred("disabled", false)
		if _stomp_area:
			_stomp_area.set_deferred("monitoring", true)
		_set_body_damage_active(true)
		if _hp_bar:
			_hp_bar.visible = true
		anim.play("fly")
	elif state == State.DEATH_FLY_TO_FALL:
		# Pasar de "fly-to-fall" a "fall" cayendo con gravedad
		_start_falling()
	elif state == State.ATTACK:
		_set_damage_zone_active(false)
		_attack_cooldown = attack_cooldown_time
		state = State.FLY
		anim.play("fly")
	elif state == State.HURT:
		state = State.FLY
		anim.play("fly")

# ─────────────────────────────────────────────────────────────────────────────
#  Búsqueda de Jugador
# ─────────────────────────────────────────────────────────────────────────────
func _get_nearest_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	var nearest: Node2D = null
	var min_dist := INF

	for p in players:
		if p is CharacterBody2D:
			var dead: bool = p.get("is_dead") if "is_dead" in p else false
			if dead:
				continue
			var d := global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				nearest = p

	return nearest
