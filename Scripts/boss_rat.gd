extends CharacterBody2D

# ─────────────────────────────────────────────────────────────────────────────
#  boss_rat.gd
#  Lógica del jefe Rata Gigante (Boss Rat):
#  • Es el jefe MÁS RÁPIDO de todos: corre velozmente por el suelo y realiza
#    embestidas rápidas con mordiscos letales.
#  • Inicia inactivo/oculto hasta que el jugador entra a la zona del jefe.
#  • Al activarse, aparece con la animación "appearing".
#  • COMBATE RÁPIDO:
#    - Velocidad base de carrera de 280.0 px/s (persigue al jugador rápidamente).
#    - Al acercarse realiza un ataque con embestida rápida a 380.0 px/s.
#    - DAÑO POR CONTACTO: Si el jugador choca contra su cuerpo en carrera, recibe daño.
#    - APLASTARLO (STOMP): Saltando en el aire sobre su lomo/cabeza se le inflige
#      daño y el jugador rebota limpiamente sin parpadear.
#  • MUERTE: Al quedarse sin vida reproduce la animación completa de "death",
#    permanece visible un momento en el suelo, otorga 50 puntos y desbloquea la sala.
# ─────────────────────────────────────────────────────────────────────────────

signal boss_defeated

@export var max_health: int = 5
@export var run_speed: float = 280.0
@export var charge_speed: float = 380.0
@export var attack_range: float = 120.0
@export var attack_cooldown_time: float = 2.0
@export var attack_active_frame_start: int = 4
@export var attack_active_frame_end: int = 8

enum State { INACTIVE, APPEARING, RUN, ATTACK, HURT, DEATH }

var state: State = State.INACTIVE
var health: int = 5
var is_invulnerable: bool = false
var direction: float = 1.0
var _attack_cooldown: float = 1.5
var _orig_damage_zone_x: float = 19.33
var _spawn_position: Vector2 = Vector2.ZERO

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
	health = max_health

	if damage_shape:
		_orig_damage_zone_x = abs(damage_shape.position.x)

	if anim and anim.sprite_frames:
		anim.sprite_frames.set_animation_loop("appearing", false)
		anim.sprite_frames.set_animation_loop("attack", false)
		anim.sprite_frames.set_animation_loop("hurt", false)
		anim.sprite_frames.set_animation_loop("death", false)

		anim.animation_finished.connect(_on_animation_finished)
		anim.frame_changed.connect(_on_anim_frame_changed)

	_create_stomp_area()
	_create_body_damage_area()
	_create_health_bar()

	_set_damage_zone_active(false)
	_set_inactive()

	# Si se corre esta escena directamente con F6 en Godot, auto-activar
	if get_parent() == get_tree().root:
		get_tree().create_timer(0.3).timeout.connect(activate_boss)

func _physics_process(delta: float) -> void:
	if state == State.INACTIVE:
		return

	# Aplicar gravedad
	if not is_on_floor():
		velocity.y += gravity * delta

	if state == State.APPEARING:
		velocity.x = 0
		move_and_slide()
		return

	if state == State.DEATH:
		velocity.x = move_toward(velocity.x, 0, 400.0 * delta)
		move_and_slide()
		return

	if state == State.HURT:
		velocity.x = move_toward(velocity.x, 0, 500.0 * delta)
		move_and_slide()
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	match state:
		State.RUN:
			_process_run(delta)
		State.ATTACK:
			# Durante el mordisco se desplaza hacia adelante con la embestida
			velocity.x = move_toward(velocity.x, 0, 350.0 * delta)

	move_and_slide()

# ─────────────────────────────────────────────────────────────────────────────
#  Carrera Rápida y Ataque
# ─────────────────────────────────────────────────────────────────────────────
func _process_run(_delta: float) -> void:
	var player := _get_nearest_player()

	if player != null:
		var diff_x: float = player.global_position.x - global_position.x
		var abs_diff_x: float = abs(diff_x)

		# Orientarse hacia el jugador
		if abs_diff_x > 15.0:
			direction = sign(diff_x)

		# Iniciar ataque rápido de mordisco si está en rango
		if abs_diff_x <= attack_range and _attack_cooldown <= 0.0 and is_on_floor():
			_start_attack()
			return
	else:
		if is_on_wall():
			direction *= -1.0

	velocity.x = direction * run_speed
	_update_facing()

	if anim.animation != "run":
		anim.play("run")

func _start_attack() -> void:
	state = State.ATTACK
	_update_facing()
	_set_damage_zone_active(false)

	# Embestida veloz hacia el frente
	velocity.x = direction * charge_speed
	anim.play("attack")

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
#  Sincronización de Fotogramas de Ataque
# ─────────────────────────────────────────────────────────────────────────────
func _on_anim_frame_changed() -> void:
	if state == State.ATTACK and anim.animation == "attack":
		var f: int = anim.frame
		if f >= attack_active_frame_start and f <= attack_active_frame_end:
			_set_damage_zone_active(true)
		else:
			_set_damage_zone_active(false)

func _set_damage_zone_active(active: bool) -> void:
	if damage_zone:
		damage_zone.monitoring = active
	if damage_shape:
		damage_shape.set_deferred("disabled", not active)

# ─────────────────────────────────────────────────────────────────────────────
#  Daño por Contacto Corporal
# ─────────────────────────────────────────────────────────────────────────────
func _create_body_damage_area() -> void:
	_body_damage_area = Area2D.new()
	_body_damage_area.name = "BodyContactDamage"
	_body_damage_area.collision_layer = 0   # No activar damage_detection automáticamente
	_body_damage_area.collision_mask = 16   # Detecta "damage_detection" del jugador
	_body_damage_area.monitoring = true

	_body_damage_shape = CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5.0
	capsule.height = 24.0
	_body_damage_shape.shape = capsule
	_body_damage_shape.position = Vector2(3, 0)
	_body_damage_shape.rotation = 1.5707964

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
	if state == State.DEATH or is_invulnerable or state == State.INACTIVE or state == State.APPEARING:
		return
	var player := _extract_player(area)
	if player == null:
		return

	if player.has_method("apply_damage"):
		player.apply_damage(10, global_position)

func _on_body_damage_body_entered(body: Node2D) -> void:
	if state == State.DEATH or is_invulnerable or state == State.INACTIVE or state == State.APPEARING:
		return
	var player := _extract_player(body)
	if player == null:
		return

	if player.has_method("apply_damage"):
		player.apply_damage(10, global_position)

# ─────────────────────────────────────────────────────────────────────────────
#  Detector de Aplastamiento en la Cabeza (Stomp)
# ─────────────────────────────────────────────────────────────────────────────
func _create_stomp_area() -> void:
	_stomp_area = Area2D.new()
	_stomp_area.name = "StompDetector"
	_stomp_area.collision_layer = 0
	_stomp_area.collision_mask = 0xFFFFFFFF

	_stomp_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 6)
	_stomp_shape.shape = rect
	# Posicionado exclusivamente en el lomo/cabeza superior
	_stomp_shape.position = Vector2(3, -7)

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
	# Si el jugador está caminando sobre el suelo, NUNCA es un pisotón
	if player.is_on_floor():
		return false
	# Debe estar en el aire cayendo
	if player.velocity.y <= 10.0:
		return false
	# Debe estar por encima de la rata
	if player.global_position.y >= (global_position.y - 6.0):
		return false
	return true

func _trigger_stomp(player: CharacterBody2D) -> void:
	if state == State.DEATH or is_invulnerable or state == State.INACTIVE or state == State.APPEARING:
		return

	# 1. El jugador rebota hacia arriba
	player.velocity.y = -480.0
	if "had_jump" in player:
		player.had_jump = true
	if "count_jumps" in player:
		player.count_jumps = 1

	if "modulate" in player:
		player.modulate.a = 1.0

	# 2. Desactivar temporalmente daño corporal y zona de ataque durante el rebote
	_set_body_damage_active(false)
	_set_damage_zone_active(false)
	get_tree().create_timer(0.4).timeout.connect(func():
		if state != State.DEATH and state != State.INACTIVE and state != State.APPEARING:
			_set_body_damage_active(true)
	)

	# 3. Dañar al jefe
	take_damage(1)

func _on_stomp_node_entered(node: Node2D) -> void:
	if state == State.DEATH or is_invulnerable or state == State.INACTIVE or state == State.APPEARING:
		return

	var player := _extract_player(node)
	if player == null:
		return

	if _is_valid_stomp(player):
		_trigger_stomp(player)

# ─────────────────────────────────────────────────────────────────────────────
#  Daño y Derrota
# ─────────────────────────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if state == State.DEATH or is_invulnerable or state == State.INACTIVE:
		return

	health -= amount
	_update_health_bar()
	_set_damage_zone_active(false)

	if health <= 0:
		_die()
		return

	state = State.HURT
	is_invulnerable = true
	velocity.y = -120.0
	anim.play("hurt")

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
	_set_damage_zone_active(false)
	_set_body_damage_active(false)

	if body_shape:
		body_shape.set_deferred("disabled", true)
	if _stomp_area:
		_stomp_area.set_deferred("monitoring", false)
	if _hp_bar:
		_hp_bar.visible = false

	# 1. Reproducir animación completa de muerte
	anim.play("death")

	# 2. Desbloquear la sala y otorgar puntos
	_notify_boss_defeated()
	GeneralRules.add_fruit_points(50)
	boss_defeated.emit()

	# 3. Esperar a que la animación de muerte termine de reproducirse completamente
	var frame_count: int = anim.sprite_frames.get_frame_count("death") if anim and anim.sprite_frames and anim.sprite_frames.has_animation("death") else 6
	var fps: float = anim.sprite_frames.get_animation_speed("death") if anim and anim.sprite_frames and anim.sprite_frames.has_animation("death") else 7.0
	var dur: float = float(frame_count) / maxf(fps, 1.0)
	await get_tree().create_timer(dur).timeout

	# 4. Dejar el cuerpo visible brevemente antes de desvanecer suavemente
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
		state = State.RUN
		is_invulnerable = false
		if body_shape:
			body_shape.set_deferred("disabled", false)
		if _stomp_area:
			_stomp_area.set_deferred("monitoring", true)
		_set_body_damage_active(true)
		if _hp_bar:
			_hp_bar.visible = true
		anim.play("run")
	elif state == State.ATTACK:
		_set_damage_zone_active(false)
		_attack_cooldown = attack_cooldown_time
		state = State.RUN
		anim.play("run")
	elif state == State.HURT:
		state = State.RUN
		anim.play("run")

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
	if state == State.DEATH:
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
