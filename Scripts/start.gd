extends Node2D

var spawn_point: Vector2

func _ready() -> void:
	# Conectamos las señales por código para no depender del editor
	$activation_area.body_entered.connect(_on_activation_area_body_entered)
	$activation_area.body_exited.connect(_on_activation_area_body_exited)

	# Calculamos el borde superior del object_collision como punto de spawn
	var collision_shape: CollisionShape2D = $object_collision/CollisionShape2D
	var shape := collision_shape.shape as RectangleShape2D
	var shape_center: Vector2 = $object_collision.global_position + collision_shape.position
	spawn_point = shape_center + Vector2(0, -shape.size.y / 2.0)

	# Empezamos en idle
	$AnimatedSprite2D.play("idle")


func _on_activation_area_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		$AnimatedSprite2D.play("moving")


func _on_activation_area_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		$AnimatedSprite2D.play("idle")
