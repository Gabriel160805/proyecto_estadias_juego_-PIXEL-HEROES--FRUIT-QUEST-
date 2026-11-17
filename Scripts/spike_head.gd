@tool
extends CharacterBody2D

enum Direction { LEFT, RIGHT, UP, DOWN }

@export var attack_direction: Direction = Direction.LEFT:
	set(value):
		attack_direction = value
		update_direction()

@export var attack_speed: float = 400.0      # Velocidad de embestida
@export var return_speed: float = 120.0      # Velocidad de regreso a su posición original
@export var hit_pause_time: float = 0.8      # Tiempo de descanso tras chocar contra la pared

enum State { IDLE, ATTACKING, HIT, RETURNING }
var current_state: State = State.IDLE

var dir_vector: Vector2 = Vector2.LEFT
var hit_anim: String = "left_hit"
var start_position: Vector2
var player_in_detection: bool = false

func _ready() -> void:
	update_direction()

	if Engine.is_editor_hint():
		return

	start_position = global_position

	# Asegurar que las zonas detecten al jugador (capa 5 / valor 16)
	$detected_zone.collision_mask = 16
	$action_zone.collision_mask = 16

	# Conectar señales por código
	$detected_zone.body_entered.connect(_on_detected_zone_body_entered)
	$detected_zone.body_exited.connect(_on_detected_zone_body_exited)
	$action_zone.body_entered.connect(_on_action_zone_body_entered)

	$AnimatedSprite2D.play("idle")

func update_direction() -> void:
	if not has_node("detected_zone") or not has_node("action_zone") or not has_node("ray_cast_wall_detection"):
		return

	var det_col = $detected_zone.get_node_or_null("CollisionShape2D")
	var act_col = $action_zone.get_node_or_null("CollisionShape2D")
	var ray: RayCast2D = $ray_cast_wall_detection

	if det_col == null or act_col == null or ray == null:
		return

	match attack_direction:
		Direction.LEFT:
			dir_vector = Vector2.LEFT
			hit_anim = "left_hit"
			det_col.position = Vector2(-37.25, 0)
			det_col.rotation = 0.0
			act_col.position = Vector2(-29.5, 0)
			act_col.rotation = 0.0
			ray.target_position = Vector2(-17.5, 0)

		Direction.RIGHT:
			dir_vector = Vector2.RIGHT
			hit_anim = "right_hit"
			det_col.position = Vector2(37.25, 0)
			det_col.rotation = 0.0
			act_col.position = Vector2(29.5, 0)
			act_col.rotation = 0.0
			ray.target_position = Vector2(17.5, 0)

		Direction.UP:
			dir_vector = Vector2.UP
			hit_anim = "top_hit"
			det_col.position = Vector2(0, -37.25)
			det_col.rotation = deg_to_rad(90.0)
			act_col.position = Vector2(0, -29.5)
			act_col.rotation = deg_to_rad(90.0)
			ray.target_position = Vector2(0, -17.5)

		Direction.DOWN:
			dir_vector = Vector2.DOWN
			hit_anim = "bottom_hit"
			det_col.position = Vector2(0, 37.25)
			det_col.rotation = deg_to_rad(90.0)
			act_col.position = Vector2(0, 29.5)
			act_col.rotation = deg_to_rad(90.0)
			ray.target_position = Vector2(0, 17.5)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	match current_state:
		State.ATTACKING:
			velocity = dir_vector * attack_speed
			move_and_slide()

			# Detectar choque con pared, suelo o techo
			if $ray_cast_wall_detection.is_colliding() or is_on_wall() or is_on_floor() or is_on_ceiling():
				on_wall_hit()

		State.RETURNING:
			var to_start = start_position - global_position
			if to_start.length() <= 3.0:
				global_position = start_position
				velocity = Vector2.ZERO
				current_state = State.IDLE
				if player_in_detection:
					$AnimatedSprite2D.play("blink")
				else:
					$AnimatedSprite2D.play("idle")
			else:
				velocity = to_start.normalized() * return_speed
				move_and_slide()

func start_attack() -> void:
	current_state = State.ATTACKING
	$AnimatedSprite2D.play("blink")

func on_wall_hit() -> void:
	current_state = State.HIT
	velocity = Vector2.ZERO
	$AnimatedSprite2D.play(hit_anim)

	await get_tree().create_timer(hit_pause_time).timeout
	if not is_inside_tree():
		return

	current_state = State.RETURNING
	if player_in_detection:
		$AnimatedSprite2D.play("blink")
	else:
		$AnimatedSprite2D.play("idle")

func _on_detected_zone_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	player_in_detection = true
	if current_state == State.IDLE:
		$AnimatedSprite2D.play("blink")

func _on_detected_zone_body_exited(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	player_in_detection = false
	if current_state == State.IDLE:
		$AnimatedSprite2D.play("idle")

func _on_action_zone_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	if current_state == State.IDLE:
		start_attack()
