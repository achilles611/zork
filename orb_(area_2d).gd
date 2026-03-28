extends Area2D

enum OrbType { WHITE, BLUE, RED }

@export var orb_type: OrbType = OrbType.WHITE

const WANDER_SPEED := 110.0
const DIRECTION_CHANGE_TIME_MIN := 0.8
const DIRECTION_CHANGE_TIME_MAX := 1.9
const ARENA_MARGIN := 220.0

var move_direction := Vector2.RIGHT
var direction_timer := 0.0
var arena_center := Vector2.ZERO
var arena_radius := 0.0
var entity_id := ""
var network_proxy := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	initialize_arena_bounds()
	pick_new_direction()
	update_visual()

func _physics_process(delta: float) -> void:
	if network_proxy:
		return
	if arena_radius <= 0.0:
		return

	direction_timer -= delta
	if direction_timer <= 0.0:
		pick_new_direction()

	var to_center: Vector2 = arena_center - global_position
	var distance_from_center: float = global_position.distance_to(arena_center)
	var safe_radius: float = maxf(arena_radius - ARENA_MARGIN, 0.0)
	if distance_from_center > safe_radius and to_center != Vector2.ZERO:
		move_direction = move_direction.lerp(to_center.normalized(), 0.12).normalized()

	global_position += move_direction * WANDER_SPEED * delta

	var max_radius: float = maxf(arena_radius - 120.0, 0.0)
	if distance_from_center > max_radius and to_center != Vector2.ZERO:
		global_position = arena_center - to_center.normalized() * max_radius
		move_direction = to_center.normalized()

func _on_body_entered(body: Node) -> void:
	print("Orb touched by: ", body.name)

	if !body.has_method("gain_energy"):
		return

	if bool(body.call("gain_energy", 1)):
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

func initialize_arena_bounds() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	if scene.has_method("get_arena_center"):
		arena_center = scene.call("get_arena_center")
	if scene.has_method("get_arena_radius"):
		arena_radius = float(scene.call("get_arena_radius"))

func pick_new_direction() -> void:
	var random_direction := Vector2.from_angle(randf() * TAU)
	if random_direction == Vector2.ZERO:
		random_direction = Vector2.RIGHT

	if arena_radius > 0.0:
		var to_center: Vector2 = (arena_center - global_position).normalized()
		if to_center != Vector2.ZERO:
			random_direction = random_direction.lerp(to_center, 0.25).normalized()

	move_direction = random_direction
	direction_timer = randf_range(DIRECTION_CHANGE_TIME_MIN, DIRECTION_CHANGE_TIME_MAX)

func set_network_proxy(enabled: bool) -> void:
	network_proxy = enabled
	monitoring = !enabled
	monitorable = !enabled
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = enabled

func get_snapshot() -> Dictionary:
	return {
		"entity_id": entity_id,
		"position": [global_position.x, global_position.y],
		"orb_type": int(orb_type),
	}

func apply_network_snapshot(data: Dictionary) -> void:
	entity_id = str(data.get("entity_id", entity_id))
	orb_type = int(data.get("orb_type", int(orb_type)))
	var position_data = data.get("position", [global_position.x, global_position.y])
	if position_data is Array and position_data.size() >= 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	update_visual()
