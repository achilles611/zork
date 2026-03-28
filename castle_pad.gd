extends Node2D

const CASTLE_MINION_SCENE = preload("res://CastleMinion.tscn")

const MAX_ENERGY := 20
const MAX_HP := 50
const SPAWN_INTERVAL := 3.0
const PAD_SIZE := 340.0

var owner_player_id := 0
var owner_owner_id := ""
var owner_nickname := ""
var entity_id := ""
var energy_stored := 0
var hp := MAX_HP
var castle_built := false
var spawn_timer := SPAWN_INTERVAL
var network_proxy := false

var square_fill: Polygon2D = null
var square_outline: Line2D = null
var castle_root: Node2D = null
var timer_ring: Line2D = null
var energy_label: Label = null

@onready var deposit_area = $DepositArea
@onready var castle_hurtbox = $CastleHurtbox

func _ready() -> void:
	add_to_group("castle_pads")
	create_visuals()
	update_visual_state()
	set_network_proxy(network_proxy)

func _process(delta: float) -> void:
	if network_proxy:
		update_timer_ring()
		update_label()
		return

	if !castle_built:
		process_deposits()
	else:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_timer += SPAWN_INTERVAL
			spawn_castle_minion()

	update_timer_ring()
	update_label()

func create_visuals() -> void:
	var half := PAD_SIZE * 0.5
	var square_points := PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])

	square_fill = Polygon2D.new()
	square_fill.polygon = square_points
	square_fill.color = Color(0.04, 0.04, 0.04, 0.65)
	add_child(square_fill)

	square_outline = Line2D.new()
	square_outline.closed = true
	square_outline.width = 12.0
	square_outline.default_color = Color(1.0, 1.0, 1.0, 0.95)
	square_outline.points = square_points
	add_child(square_outline)

	energy_label = Label.new()
	energy_label.top_level = true
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_label.add_theme_font_size_override("font_size", 88)
	energy_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(energy_label)

	castle_root = Node2D.new()
	add_child(castle_root)

	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-170, 90),
		Vector2(170, 90),
		Vector2(170, -20),
		Vector2(-170, -20)
	])
	base.color = Color(0.9, 0.9, 0.92, 0.95)
	castle_root.add_child(base)

	for x in [-120.0, 0.0, 120.0]:
		var tower := Polygon2D.new()
		tower.polygon = PackedVector2Array([
			Vector2(x - 48, -20),
			Vector2(x + 48, -20),
			Vector2(x + 48, -160),
			Vector2(x - 48, -160)
		])
		tower.color = Color(0.95, 0.95, 0.97, 0.98)
		castle_root.add_child(tower)

		var battlement := Polygon2D.new()
		battlement.polygon = PackedVector2Array([
			Vector2(x - 60, -160),
			Vector2(x + 60, -160),
			Vector2(x + 60, -190),
			Vector2(x - 60, -190)
		])
		battlement.color = Color(0.95, 0.95, 0.97, 0.98)
		castle_root.add_child(battlement)

	timer_ring = Line2D.new()
	timer_ring.width = 18.0
	timer_ring.default_color = Color(0.06, 0.06, 0.06, 0.95)
	timer_ring.z_index = 4
	add_child(timer_ring)

func process_deposits() -> void:
	for body in get_tree().get_nodes_in_group("combat_players"):
		if body == null or !is_instance_valid(body):
			continue
		if int(body.player_id) != owner_player_id:
			continue
		if !is_player_inside_deposit_zone(body):
			continue
		if !body.has_method("deposit_all_energy"):
			continue
		var deposited := int(body.call("deposit_all_energy"))
		if deposited <= 0:
			continue
		energy_stored = mini(energy_stored + deposited, MAX_ENERGY)
		if energy_stored >= MAX_ENERGY:
			build_castle()
		break

func is_player_inside_deposit_zone(player: Node2D) -> bool:
	var local_position := to_local(player.global_position)
	var half_size := PAD_SIZE * 0.5
	return absf(local_position.x) <= half_size and absf(local_position.y) <= half_size

func build_castle() -> void:
	castle_built = true
	energy_stored = MAX_ENERGY
	hp = MAX_HP
	spawn_timer = SPAWN_INTERVAL
	update_visual_state()

func destroy_castle() -> void:
	castle_built = false
	energy_stored = 0
	hp = MAX_HP
	spawn_timer = SPAWN_INTERVAL
	update_visual_state()

func spawn_castle_minion() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var minions_node := current_scene.get_node_or_null("Minions")
	if minions_node == null:
		return
	var minion = CASTLE_MINION_SCENE.instantiate()
	minion.entity_id = "%s_minion_%d" % [entity_id, Time.get_ticks_usec()]
	minion.owner_player_id = owner_player_id
	minion.owner_owner_id = owner_owner_id
	minion.owner_nickname = owner_nickname
	minion.global_position = global_position + Vector2(0, -220)
	minions_node.add_child(minion)

func update_visual_state() -> void:
	if castle_root != null:
		castle_root.visible = castle_built
	if castle_hurtbox != null:
		castle_hurtbox.monitoring = castle_built and !network_proxy
		castle_hurtbox.monitorable = castle_built and !network_proxy
		var shape := castle_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null:
			shape.disabled = !castle_built or network_proxy

func update_label() -> void:
	if energy_label == null:
		return
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := Vector2.ONE
	if camera != null:
		camera_zoom = camera.zoom
	energy_label.scale = Vector2.ONE / camera_zoom
	energy_label.text = "%d/%d energy" % [energy_stored, MAX_ENERGY]
	var label_size: Vector2 = energy_label.size * energy_label.scale
	energy_label.global_position = global_position + Vector2(-label_size.x * 0.5, -520.0)

func update_timer_ring() -> void:
	if timer_ring == null:
		return
	if !castle_built:
		timer_ring.visible = false
		return
	timer_ring.visible = true
	var progress := 1.0 - (spawn_timer / SPAWN_INTERVAL)
	var point_count := maxi(2, int(48.0 * progress))
	var points := PackedVector2Array()
	for i in range(point_count + 1):
		var angle := -PI * 0.5 + (TAU * progress * float(i) / float(max(point_count, 1)))
		points.append(Vector2(cos(angle), sin(angle)) * 250.0)
	timer_ring.points = points

func hit_by_player(player: Node2D) -> void:
	if !castle_built:
		return
	var amount := 10
	if player != null and player.has_method("get_attack_power"):
		amount = int(player.call("get_attack_power"))
	take_damage(amount)

func take_damage(amount: int) -> void:
	if !castle_built:
		return
	hp -= amount
	if hp <= 0:
		destroy_castle()

func get_team_id() -> int:
	return owner_player_id

func is_attackable() -> bool:
	return castle_built

func set_network_proxy(enabled: bool) -> void:
	network_proxy = enabled
	deposit_area.monitoring = !enabled
	deposit_area.monitorable = !enabled
	var deposit_shape := deposit_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if deposit_shape != null:
		deposit_shape.disabled = enabled
	update_visual_state()

func get_snapshot() -> Dictionary:
	return {
		"entity_id": entity_id,
		"owner_player_id": owner_player_id,
		"owner_owner_id": owner_owner_id,
		"owner_nickname": owner_nickname,
		"position": [global_position.x, global_position.y],
		"energy_stored": energy_stored,
		"hp": hp,
		"castle_built": castle_built,
		"spawn_timer": spawn_timer,
	}

func apply_network_snapshot(data: Dictionary) -> void:
	entity_id = str(data.get("entity_id", entity_id))
	owner_player_id = int(data.get("owner_player_id", owner_player_id))
	owner_owner_id = str(data.get("owner_owner_id", owner_owner_id))
	owner_nickname = str(data.get("owner_nickname", owner_nickname))
	var position_data = data.get("position", [global_position.x, global_position.y])
	if position_data is Array and position_data.size() >= 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	energy_stored = int(data.get("energy_stored", energy_stored))
	hp = int(data.get("hp", hp))
	castle_built = bool(data.get("castle_built", castle_built))
	spawn_timer = float(data.get("spawn_timer", spawn_timer))
	update_visual_state()
	update_timer_ring()
	update_label()
