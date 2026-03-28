extends CharacterBody2D

const SPEED := 1320.0
const MAX_HP := 10
const DAMAGE := 5
const ATTACK_RANGE := 120.0
const BODY_RADIUS := 72.0
const STAR_SPIN_SPEED := 11.0

var owner_player_id := 0
var owner_owner_id := ""
var owner_nickname := ""
var entity_id := ""
var hp := MAX_HP
var alive := true
var network_proxy := false
var visual_root: Node2D = null

@onready var hurtbox = $Hurtbox

func _ready() -> void:
	add_to_group("castle_minions")
	create_visuals()
	set_network_proxy(network_proxy)

func _physics_process(_delta: float) -> void:
	if !alive or network_proxy:
		return

	if visual_root != null:
		visual_root.rotation += STAR_SPIN_SPEED * _delta

	var target := find_target()
	if target == null:
		velocity = Vector2.ZERO
		return

	var to_target := target.global_position - global_position
	if to_target.length() <= ATTACK_RANGE:
		attack_target(target)
		return

	rotation = to_target.angle()
	velocity = to_target.normalized() * SPEED
	move_and_slide()

func create_visuals() -> void:
	visual_root = Node2D.new()
	add_child(visual_root)

	var aura := Polygon2D.new()
	aura.polygon = make_circle_points(110.0, 20)
	aura.color = Color(0.22, 0.22, 0.22, 0.16)
	visual_root.add_child(aura)

	for i in range(3):
		var point := Polygon2D.new()
		point.polygon = PackedVector2Array([
			Vector2(0, -28),
			Vector2(150, 0),
			Vector2(0, 28),
			Vector2(42, 0)
		])
		point.color = Color(0.95, 0.95, 0.95, 0.95)
		point.rotation = TAU * float(i) / 3.0
		visual_root.add_child(point)

func make_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func set_network_proxy(enabled: bool) -> void:
	network_proxy = enabled
	var body_shape := $CollisionShape2D as CollisionShape2D
	var hurtbox_shape := $Hurtbox/CollisionShape2D as CollisionShape2D
	if body_shape != null:
		body_shape.disabled = enabled
	hurtbox.monitoring = !enabled
	hurtbox.monitorable = !enabled
	if hurtbox_shape != null:
		hurtbox_shape.disabled = enabled

func is_body_hurtbox(area: Area2D) -> bool:
	return area == hurtbox

func can_hit(_target: Node) -> bool:
	return alive

func register_hit(_target: Node) -> void:
	return

func can_clash(_target: Node) -> bool:
	return alive

func register_clash(_target: Node) -> void:
	return

func get_team_id() -> int:
	return owner_player_id

func get_attack_power() -> int:
	return DAMAGE

func apply_knockback(direction: Vector2, distance: float = 180.0) -> void:
	global_position += direction.normalized() * distance

func take_damage(amount: int) -> void:
	if !alive:
		return
	hp -= amount
	if hp <= 0:
		kill_instantly()

func hit_by_player(player: Node2D) -> void:
	var amount := DAMAGE
	if player != null and player.has_method("get_attack_power"):
		amount = int(player.call("get_attack_power"))
	take_damage(amount)

func attack_target(target: Node2D) -> void:
	if target == null or !is_instance_valid(target):
		return
	if target.has_method("damage_nearest_arm"):
		target.call("damage_nearest_arm", DAMAGE, global_position)
	elif target.has_method("take_damage"):
		target.call("take_damage", DAMAGE)
	kill_instantly()

func kill_instantly() -> void:
	if !alive:
		return
	alive = false
	queue_free()

func find_target() -> Node2D:
	var nearest := find_nearest_group_target("castle_minions")
	if nearest != null:
		return nearest
	nearest = find_nearest_group_target("combat_players")
	if nearest != null:
		return nearest
	return find_nearest_group_target("castle_pads")

func find_nearest_group_target(group_name: String) -> Node2D:
	var nodes = get_tree().get_nodes_in_group(group_name)
	var best_target: Node2D = null
	var best_distance_sq := INF
	for candidate in nodes:
		var node := candidate as Node2D
		if node == null or node == self or !is_instance_valid(node):
			continue
		if node.has_method("get_team_id") and int(node.call("get_team_id")) == owner_player_id:
			continue
		if node.has_method("is_attackable") and !bool(node.call("is_attackable")):
			continue
		var distance_sq := global_position.distance_squared_to(node.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_target = node
	return best_target

func get_snapshot() -> Dictionary:
	return {
		"entity_id": entity_id,
		"owner_player_id": owner_player_id,
		"owner_owner_id": owner_owner_id,
		"owner_nickname": owner_nickname,
		"position": [global_position.x, global_position.y],
		"rotation": rotation,
		"hp": hp,
		"alive": alive,
	}

func apply_network_snapshot(data: Dictionary) -> void:
	entity_id = str(data.get("entity_id", entity_id))
	owner_player_id = int(data.get("owner_player_id", owner_player_id))
	owner_owner_id = str(data.get("owner_owner_id", owner_owner_id))
	owner_nickname = str(data.get("owner_nickname", owner_nickname))
	var position_data = data.get("position", [global_position.x, global_position.y])
	if position_data is Array and position_data.size() >= 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	rotation = float(data.get("rotation", rotation))
	hp = int(data.get("hp", hp))
	alive = bool(data.get("alive", alive))

func is_attackable() -> bool:
	return alive
