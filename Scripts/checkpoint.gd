extends Node2D

var is_activated: bool = false
var spawn_point: Vector2

func _ready() -> void:
	# Conectamos las señales por código
	$activation_area.body_entered.connect(_on_activation_area_body_entered)
	$AnimatedSprite2D.animation_finished.connect(_on_animation_finished)

	# Punto donde reaparecerá el personaje al usar este checkpoint
	spawn_point = global_position

	# Animación inicial sin bandera
	$AnimatedSprite2D.play("no_flag")


func _on_activation_area_body_entered(body: Node2D) -> void:
	if not (body is CharacterBody2D) and not body.is_in_group("player"):
		return

	# Actualizamos el checkpoint de todos los jugadores activos en la partida
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("set_checkpoint"):
			p.set_checkpoint(spawn_point)
		elif "respawn_position" in p:
			p.respawn_position = spawn_point

	# Asegurar actualización en el cuerpo entrante directamente
	if body.has_method("set_checkpoint"):
		body.set_checkpoint(spawn_point)
	elif "respawn_position" in body:
		body.respawn_position = spawn_point

	# Solo se reproduce la animación de sacar bandera la primera vez que se activa
	if not is_activated:
		is_activated = true
		$AnimatedSprite2D.sprite_frames.set_animation_loop("flag_out", false)
		$AnimatedSprite2D.play("flag_out")


func _on_animation_finished() -> void:
	# Cuando termina de salir la bandera, pasa a idle (ondeando) en loop
	if $AnimatedSprite2D.animation == "flag_out":
		$AnimatedSprite2D.play("idle")
