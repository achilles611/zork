extends Area2D

@export var owner_path: NodePath
var owner_player

func _ready() -> void:
	owner_player = get_node(owner_path)
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if !owner_player:
		return

	if area.name == "Hurtbox":
		var other_player = area.get_parent()
		if other_player != owner_player:
			owner_player.resolve_combat(other_player)
