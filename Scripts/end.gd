extends Node2D

# Ruta de la siguiente escena. Cámbiala por el path de tu siguiente nivel.
@export_file("*.tscn") var next_level: String = ""

var player_inside: bool = false

func _ready() -> void:
	# Conectamos señales por código
	$activation_area.body_entered.connect(_on_activation_area_body_entered)
	$activation_area.body_exited.connect(_on_activation_area_body_exited)
	$AnimatedSprite2D.animation_finished.connect(_on_animation_finished)

	$AnimatedSprite2D.play("idle")


func _on_activation_area_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	player_inside = true
	# Reproducimos moving SIN loop para que dispare animation_finished al terminar
	$AnimatedSprite2D.sprite_frames.set_animation_loop("moving", false)
	$AnimatedSprite2D.play("moving")


func _on_activation_area_body_exited(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	player_inside = false
	# Si el jugador sale antes de que termine, volvemos a idle y restauramos el loop
	if $AnimatedSprite2D.animation == "moving" and $AnimatedSprite2D.is_playing():
		$AnimatedSprite2D.sprite_frames.set_animation_loop("moving", true)
		$AnimatedSprite2D.play("idle")


func _on_animation_finished() -> void:
	# Solo actuamos si la animación que terminó es "moving"
	if $AnimatedSprite2D.animation != "moving":
		return

	if next_level != "":
		GeneralRules.transition_to_scene(next_level)
	else:
		GeneralRules.advance_level()
