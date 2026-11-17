extends CharacterBody2D

var health: int = 100
var fruitCount: int = 0
const SPEED = 300.0
const JUMP_VELOCITY = -400.0
const KNOCKBACK_FORCE_X = 260.0
const KNOCKBACK_FORCE_Y = -240.0

# ── Efectos de superficie ──────────────────────────────────────────────────────
# Hielo: resbala en suelo Y mantiene inercia en aire al saltar
# Arena: salta menos y se mueve más lento en el suelo
const ICE_ACCELERATION:  float = 280.0   # px/s² de aceleración en hielo en suelo
const ICE_FRICTION:      float = 70.0    # px/s² de desaceleración en hielo en suelo
const ICE_AIR_ACCEL:     float = 180.0   # px/s² de control horizontal en aire tras saltar desde hielo
const SAND_JUMP_MULT:    float = 0.50    # Multiplicador de salto en arena (50 % del normal)
const SAND_SPEED_MULT:   float = 0.65    # Multiplicador de velocidad horizontal en arena (65 % del normal)

var _on_ice:         bool = false  # True si el suelo bajo el jugador es del grupo "hielo"
var _on_sand:        bool = false  # True si el suelo bajo el jugador es del grupo "arena"
var _jumped_from_ice: bool = false  # True mientras está en el aire tras saltar desde hielo

var wait_animation: bool = false
var leaved_floor: bool = false
var had_jump: bool = false
var max_jumps: int = 2
var count_jumps: int = 0
var ray_cast_dimension = 12
var direction
var stuck_on_wall: bool = false
var is_invulnerable: bool = false  # Flag de invulnerabilidad tras recibir daño
var is_in_knockback: bool = false  # Bloquea temporalmente el control de movimiento
var is_dead: bool = false          # Evita procesar inputs o múltiples muertes
var respawn_position: Vector2 = Vector2.ZERO

@export var fall_limit_y: float = 800.0  # Límite vertical para detectar caída al vacío

# ── Soporte multijugador y controles ──────────────────────────────────────────
# 1 = Jugador 1 (WASD / flechas / Mando 1) | 2 = Jugador 2 (teclas alt / Mando 2)
var player_index: int = 1

# Acciones de input por jugador
var _action_left:  String = "ui_left"
var _action_right: String = "ui_right"
var _action_jump:  String = "ui_accept"

# Estado de botones de mando para detectar 'just pressed'
var _joy_jump_prev: bool = false

func set_player_index(index: int) -> void:
	player_index = index
	if index == 2:
		_action_left  = "p2_left"
		_action_right = "p2_right"
		_action_jump  = "p2_jump"
	else:
		_action_left  = "ui_left"
		_action_right = "ui_right"
		_action_jump  = "ui_accept"

# Obtiene la dirección horizontal combinando teclado y control (mando/joypad)
func _get_move_direction() -> float:
	var dir: float = Input.get_axis(_action_left, _action_right)

	# Leer mando (joypad) asignado
	var joy_id := _get_assigned_joy_id()
	if joy_id >= 0:
		var stick_x := Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X)
		if abs(stick_x) > 0.2:
			dir = stick_x
		elif Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_LEFT):
			dir = -1.0
		elif Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_RIGHT):
			dir = 1.0

	return clampf(dir, -1.0, 1.0)

# Detecta si se presionó saltar en teclado o en el mando
func _is_jump_just_pressed() -> bool:
	var action_pressed := Input.is_action_just_pressed(_action_jump)

	var joy_id := _get_assigned_joy_id()
	var joy_just_pressed := false
	if joy_id >= 0:
		var joy_down: bool = (
			Input.is_joy_button_pressed(joy_id, JOY_BUTTON_A) or
			Input.is_joy_button_pressed(joy_id, JOY_BUTTON_B) or
			Input.is_joy_button_pressed(joy_id, JOY_BUTTON_X) or
			Input.is_joy_button_pressed(joy_id, JOY_BUTTON_Y) or
			Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_UP)
		)
		joy_just_pressed = joy_down and not _joy_jump_prev
		_joy_jump_prev = joy_down
	else:
		_joy_jump_prev = false

	return action_pressed or joy_just_pressed

# Determina qué mando corresponde a este jugador
func _get_assigned_joy_id() -> int:
	var joysticks := Input.get_connected_joypads()
	if joysticks.is_empty():
		return -1

	if player_index == 1:
		return joysticks[0]
	else:
		if joysticks.size() >= 2:
			return joysticks[1]
		return -1

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# ── Detectar el tipo de superficie bajo el jugador ────────────────────────────
# Usa un raycast desde los pies del jugador hacia abajo. Se prueba con
# collision_mask = 0xFFFFFFFF para detectar cualquier capa, luego se filtra
# por grupo. TileMapLayer en Godot 4.4+ se devuelve directamente como colisionador.
func _update_surface_type() -> void:
	_on_ice  = false
	_on_sand = false
	if not is_on_floor():
		return

	var space := get_world_2d().direct_space_state

	# Origen: pies del personaje.
	# CapsuleShape2D: radius=8, height=23, offset y=3.5, escala 2x
	# → pie en y = (3.5 + 11.5) * 2 = 30 px bajo el origen del nodo
	var feet: Vector2 = global_position + Vector2(0.0, 30.0)
	var query := PhysicsRayQueryParameters2D.create(
		feet,
		feet + Vector2(0.0, 12.0),
		0xFFFFFFFF,      # todas las capas para no depender del collision_mask del jugador
		[get_rid()]
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return

	# Buscar el nodo o su padre en los grupos de superficie
	var hit: Object = result.get("collider")
	if _node_or_parent_in_group(hit, "hielo"):
		_on_ice = true
	elif _node_or_parent_in_group(hit, "arena"):
		_on_sand = true

	# Al aterrizar en suelo que NO es hielo, se pierde la inercia de hielo
	if not _on_ice:
		_jumped_from_ice = false


# Revisa si el nodo (o algún ancestro) pertenece al grupo dado.
# Necesario porque Godot 4 puede devolver un cuerpo físico interno en lugar
# del nodo TileMap/TileMapLayer que lo contiene.
func _node_or_parent_in_group(obj: Object, group: String) -> bool:
	if obj == null:
		return false
	var node := obj as Node
	while node != null:
		if node.is_in_group(group):
			return true
		node = node.get_parent()
	return false

func _ready() -> void:
	$animaciones.animation_finished.connect(_on_animaciones_animation_finished)
	$animaciones.play("appear")
	$rayCast_walljump.target_position.x = ray_cast_dimension
	respawn_position = global_position

	# Si la cámara tiene un límite inferior configurado, ajustamos el límite de caída
	if has_node("Camera2D"):
		var cam: Camera2D = $Camera2D
		if cam.limit_bottom != 10000000 and cam.limit_bottom > 0:
			fall_limit_y = cam.limit_bottom + 50.0

func _physics_process(delta: float) -> void:
	# Si el personaje está muerto, no responde a inputs ni gravedad normal
	if is_dead:
		return

	# Chequear si cayó fuera de los límites del nivel
	if global_position.y > fall_limit_y:
		die()
		return

	if is_on_floor():
		leaved_floor = false
		had_jump = false
		count_jumps = 0

	if not is_on_floor():
		if not leaved_floor:
			$coyote_timer.start()
			leaved_floor = true
		velocity.y += gravity * delta

	# Efecto visual de parpadeo durante invulnerabilidad
	if is_invulnerable:
		modulate.a = 0.4 if int(Time.get_ticks_msec() / 80) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0

	# Daño continuo si el personaje se queda tocando pinchos u otra zona de daño
	if not is_invulnerable and not is_in_knockback:
		check_continuous_damage()

	# Durante el retroceso (knockback), desacelera horizontalmente sin leer controles
	if is_in_knockback:
		velocity.x = move_toward(velocity.x, 0, 700.0 * delta)
	else:
		if _is_jump_just_pressed() and right_to_jump():
			if count_jumps == 1:
				wait_animation = false
				$animaciones.play("double_jump")
			count_jumps += 1
			# Registrar si el salto viene desde hielo (para conservar inercia en aire)
			if _on_ice:
				_jumped_from_ice = true
			# En arena el salto es más bajo
			var jump_vel: float = JUMP_VELOCITY * (SAND_JUMP_MULT if _on_sand else 1.0)
			velocity.y = jump_vel

		direction = _get_move_direction()

		if _on_ice:
			# ── Hielo (en suelo): aceleración y frenado suaves ──
			if direction:
				velocity.x = move_toward(velocity.x, direction * SPEED, ICE_ACCELERATION * delta)
			else:
				velocity.x = move_toward(velocity.x, 0.0, ICE_FRICTION * delta)

		elif not is_on_floor() and _jumped_from_ice:
			# ── Aire tras saltar desde hielo: control suave, velocidad se conserva ──
			if direction:
				velocity.x = move_toward(velocity.x, direction * SPEED, ICE_AIR_ACCEL * delta)
			# Sin dirección: NO frena (inercia pura en aire)

		elif _on_sand:
			# ── Arena (en suelo): misma respuesta inmediata pero a menor velocidad máx. ──
			if direction:
				velocity.x = direction * SPEED * SAND_SPEED_MULT
			else:
				velocity.x = move_toward(velocity.x, 0, SPEED)

		else:
			# ── Suelo normal / aire normal ──
			if direction:
				velocity.x = direction * SPEED
			else:
				velocity.x = move_toward(velocity.x, 0, SPEED)

	if $rayCast_walljump.get_collider():
		if $rayCast_walljump.get_collider().is_in_group("wall_jump"):
			if velocity.y > 0:
				count_jumps = 0
				velocity.y = 0
				stuck_on_wall = true
		else:
			stuck_on_wall = false
	else:
		stuck_on_wall = false

	move_and_slide()
	_update_surface_type()   # Actualizar tras move_and_slide (usa colisiones del frame actual)
	decide_animation()

func decide_animation() -> void:
	if is_dead:
		return

	if direction < 0:
		$rayCast_walljump.target_position.x = -ray_cast_dimension
		$animaciones.flip_h = true
	elif direction > 0:
		$rayCast_walljump.target_position.x = ray_cast_dimension
		$animaciones.flip_h = false

	if not wait_animation:
		return

	if stuck_on_wall:
		$animaciones.play("wall_jump")
	else:
		if velocity.y > 0:
			$animaciones.play("jump_down")
		elif velocity.y < 0:
			$animaciones.play("jump_up")
		elif velocity.x == 0:
			$animaciones.play("idle")
		else:
			$animaciones.play("run")

# Retorna true si el jugador tiene permitido saltar, false en caso contrario.
func right_to_jump() -> bool:
	if is_in_knockback:
		return false
	if had_jump:
		return count_jumps < max_jumps
	if is_on_floor() or stuck_on_wall:
		had_jump = true
		return true
	elif not $coyote_timer.is_stopped():
		had_jump = true
		return true
	return false

func collectFruit(fruitType: String) -> void:
	var auxString = fruitType + "Points"
	var gainedPoints = GeneralRules[auxString]
	fruitCount += gainedPoints
	GeneralRules.add_fruit_points(gainedPoints)
	print(fruitCount)

func set_checkpoint(new_position: Vector2) -> void:
	respawn_position = new_position
	print("Checkpoint guardado en: ", new_position)

func check_continuous_damage() -> void:
	var overlapping = $damage_detection.get_overlapping_areas()
	if not overlapping.is_empty():
		var damage_source = overlapping[0]
		apply_damage(10, damage_source.global_position)

func apply_damage(amount: int, source_position: Vector2) -> void:
	if is_invulnerable or is_dead:
		return

	health -= amount
	print("Vida actual: ", health)

	if health <= 0:
		die()
		return

	# Activar invulnerabilidad temporal
	is_invulnerable = true
	$invulnerability_timer.start()

	# Calcular dirección del retroceso (empujar alejándose de la fuente del daño)
	var knockback_dir: float = sign(global_position.x - source_position.x)
	if knockback_dir == 0.0:
		knockback_dir = -1.0 if not $animaciones.flip_h else 1.0

	velocity.x = knockback_dir * KNOCKBACK_FORCE_X
	velocity.y = KNOCKBACK_FORCE_Y

	# Reproducir animación hit
	is_in_knockback = true
	wait_animation = false
	if $animaciones.sprite_frames.has_animation("hit"):
		$animaciones.play("hit")

	# Control restaurado tras 0.25 segundos
	var timer = get_tree().create_timer(0.25)
	timer.timeout.connect(func():
		is_in_knockback = false
	)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_in_knockback = false
	modulate.a = 1.0
	velocity = Vector2.ZERO
	health = 0

	# Reproducir animación de desaparecer si existe
	if $animaciones.sprite_frames.has_animation("dissappear"):
		wait_animation = false
		$animaciones.play("dissappear")
		await $animaciones.animation_finished
	else:
		await get_tree().create_timer(0.4).timeout

	# ── Sistema de Vidas ───────────────────────────────────────────────────────
	# Solo el jugador 1 controla las vidas globales para no decrementar doble
	if player_index == 1:
		GeneralRules.lives -= 1
		if GeneralRules.lives <= 0:
			GeneralRules.start_game()
			return

	respawn()

func respawn() -> void:
	health = 100
	velocity = Vector2.ZERO
	global_position = respawn_position
	is_dead = false
	is_in_knockback = false
	is_invulnerable = true
	modulate.a = 1.0
	$invulnerability_timer.start()

	wait_animation = false
	if $animaciones.sprite_frames.has_animation("appear"):
		$animaciones.play("appear")
	else:
		$animaciones.play("idle")

func _on_animaciones_animation_finished() -> void:
	wait_animation = true

func _on_coyote_timer_timeout() -> void:
	pass

func _on_invulnerability_timer_timeout() -> void:
	is_invulnerable = false
	modulate.a = 1.0
	if not is_dead and not is_in_knockback:
		check_continuous_damage()

func _on_damage_detection_area_shape_entered(area_rid: RID, area: Area2D, area_shape_index: int, local_shape_index: int) -> void:
	var source_pos = area.global_position if area else global_position
	apply_damage(10, source_pos)
