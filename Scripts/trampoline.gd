extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _on_activation_area_body_entered(body: Node2D) -> void:
	# Verificamos que el body tenga velocity (es un CharacterBody2D) antes de modificarla.
	if not body is CharacterBody2D:
		return
	$animaciones_trampolin.play("launch")
	body.velocity.y = -900
