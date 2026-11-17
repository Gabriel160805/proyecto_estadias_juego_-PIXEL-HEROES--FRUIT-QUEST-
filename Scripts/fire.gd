extends Node2D

@export var off_time: float = 2.5       # Tiempo que permanece apagado
@export var heating_time: float = 1.0   # Tiempo que tarda en calentarse (advertencia)
@export var on_time: float = 2.0        # Tiempo que permanece encendido con fuego (daño activo)
@export var start_delay: float = 0.0    # Retardo inicial opcional para desincronizar varios lanzallamas

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_collision: CollisionShape2D = $damage_zone/CollisionShape2D
@onready var damage_zone: Area2D = $damage_zone

func _ready() -> void:
	# Aseguramos que inicie apagado y sin hacer daño
	set_damage_active(false)
	animated_sprite.play("off")
	start_fire_cycle()

func start_fire_cycle() -> void:
	# Retardo inicial si se desea desfasar entre varios lanzallamas
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout

	while is_inside_tree():
		# 1. ESTADO APAGADO (OFF)
		set_damage_active(false)
		animated_sprite.play("off")
		await get_tree().create_timer(off_time).timeout
		if not is_inside_tree():
			break

		# 2. ESTADO CALENTÁNDOSE (HIT / ADVERTENCIA)
		set_damage_active(false)
		animated_sprite.play("hit")
		await get_tree().create_timer(heating_time).timeout
		if not is_inside_tree():
			break

		# 3. ESTADO ENCENDIDO (ON / DAÑO ACTIVO)
		set_damage_active(true)
		animated_sprite.play("on")
		await get_tree().create_timer(on_time).timeout
		if not is_inside_tree():
			break

func set_damage_active(is_active: bool) -> void:
	# Activamos o desactivamos la colisión y monitorización de damage_zone
	damage_collision.set_deferred("disabled", not is_active)
	damage_zone.set_deferred("monitoring", is_active)
	damage_zone.set_deferred("monitorable", is_active)
