extends Node2D

@export var fall_delay: float = 1.2          # Tiempo que tarda la animación en desacelerar hasta apagarse
@export var gravity: float = 900.0           # Gravedad/velocidad con la que cae al apagarse
@export var can_respawn: bool = true         # Si la plataforma debe volver a aparecer tras caer
@export var respawn_time: float = 2.5        # Tiempo que tarda en reaparecer en su posición original

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var activation_area: Area2D = $activation_area
@onready var collision_shape: CollisionShape2D = $AnimatableBody2D/CollisionShape2D

var start_position: Vector2
var is_triggered: bool = false
var is_falling: bool = false
var fall_velocity: float = 0.0

func _ready() -> void:
	start_position = global_position
	activation_area.body_entered.connect(_on_activation_area_body_entered)
	reset_platform()

func reset_platform() -> void:
	global_position = start_position
	sprite.position = Vector2.ZERO
	is_triggered = false
	is_falling = false
	fall_velocity = 0.0
	sprite.speed_scale = 1.0
	sprite.play("on")
	modulate.a = 1.0
	collision_shape.set_deferred("disabled", false)
	activation_area.set_deferred("monitoring", true)

func _physics_process(delta: float) -> void:
	if is_falling:
		fall_velocity += gravity * delta
		global_position.y += fall_velocity * delta

		# Cuando cae lo suficiente (350 píxeles por debajo de su origen)
		if global_position.y - start_position.y > 350.0:
			is_falling = false
			if can_respawn:
				respawn()
			else:
				queue_free()

func _on_activation_area_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return

	if not is_triggered:
		is_triggered = true
		activation_area.set_deferred("monitoring", false)
		start_decelerating()

func start_decelerating() -> void:
	# La animación de "on" se va haciendo progresivamente más lenta
	var tween = create_tween()
	tween.tween_property(sprite, "speed_scale", 0.15, fall_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Temblor progresivo hacia los lados para dar sensación de inestabilidad
	var shake_tween = create_tween()
	var shake_steps: int = int(fall_delay / 0.08)
	for i in range(shake_steps):
		var offset_x: float = (1.5 if i % 2 == 0 else -1.5) * (float(i) / max(shake_steps, 1))
		shake_tween.tween_property(sprite, "position:x", offset_x, 0.08)
	shake_tween.tween_property(sprite, "position:x", 0.0, 0.05)

	await tween.finished
	turn_off_and_fall()

func turn_off_and_fall() -> void:
	# Pasa a la animación "off" y cae
	sprite.speed_scale = 1.0
	sprite.play("off")
	is_falling = true

func respawn() -> void:
	# Desvanece la plataforma
	collision_shape.set_deferred("disabled", true)
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	await fade_tween.finished

	# Espera el tiempo de reaparición
	await get_tree().create_timer(respawn_time).timeout
	if not is_inside_tree():
		return

	# Reaparece suavemente en su posición original
	reset_platform()
	modulate.a = 0.0
	var appear_tween = create_tween()
	appear_tween.tween_property(self, "modulate:a", 1.0, 0.3)
