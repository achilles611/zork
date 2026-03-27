extends Area2D

enum OrbType { WHITE, BLUE, RED }

@export var orb_type: OrbType = OrbType.WHITE

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	update_visual()

func _on_body_entered(body: Node) -> void:
	print("Orb touched by: ", body.name)

	if !body.has_method("gain_white_orb"):
		return

	match orb_type:
		OrbType.WHITE:
			body.gain_white_orb()
		OrbType.BLUE:
			body.gain_blue_orb()
		OrbType.RED:
			body.gain_red_orb()

	queue_free()

func update_visual() -> void:
	if has_node("Sprite2D"):
		var sprite = $Sprite2D
		match orb_type:
			OrbType.WHITE:
				sprite.modulate = Color.WHITE
			OrbType.BLUE:
				sprite.modulate = Color(0.3, 0.6, 1.0)
			OrbType.RED:
				sprite.modulate = Color(1.0, 0.2, 0.2)
