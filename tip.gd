extends Area2D

var owner_player: Node = null
var arm_index := 0

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if owner_player == null:
		return
	if owner_player.has_method("is_arm_active") and !bool(owner_player.call("is_arm_active", arm_index)):
		return

	var other_target := area.get_parent()
	if other_target == null or other_target == owner_player:
		return

	if owner_player.has_method("get_team_id") and other_target.has_method("get_team_id"):
		if int(owner_player.call("get_team_id")) == int(other_target.call("get_team_id")):
			return

	if area.get("owner_player") != null:
		var other_owner = area.get("owner_player")
		if other_owner != null and other_owner.has_method("is_arm_active"):
			if !bool(other_owner.call("is_arm_active", int(area.get("arm_index")))):
				return
		if owner_player.has_method("handle_arm_clash"):
			owner_player.handle_arm_clash(other_target, arm_index, int(area.get("arm_index")))
		return

	if other_target.has_method("is_body_hurtbox"):
		if bool(other_target.call("is_body_hurtbox", area)):
			if owner_player.has_method("deal_tip_damage"):
				owner_player.deal_tip_damage(other_target)
			return

	if other_target.has_method("hit_by_player"):
		other_target.hit_by_player(owner_player)
		return
