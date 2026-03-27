extends Area2D

var owner_player: Node = null

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if owner_player == null:
		return

	var other_player = area.get_parent()
	if other_player == null or other_player == owner_player:
		return

	if other_player.has_method("hit_by_player"):
		other_player.hit_by_player(owner_player)
		return

	# Match the player hurtbox by capability instead of an editor-assigned node name.
	if other_player.has_method("take_damage") and other_player.has_method("register_hit"):
		print("Tip hit: ", owner_player.name, " -> ", other_player.name)
		owner_player.resolve_combat(other_player)
