extends Area2D

const DAMAGE := 10
const ORBIT_RADIUS := 560.0
const ORBIT_SPEED := 2.8
const PROJECTILE_SPEED := 5200.0
const PROJECTILE_HIT_RADIUS := 120.0

var owner_player: Node2D = null
var consumed := false
var launched := false
var velocity: Vector2 = Vector2.ZERO
var launch_target: Node2D = null

func _ready() -> void:
	top_level = true
	area_entered.connect(_on_area_entered)
	create_visuals()

func _physics_process(delta: float) -> void:
	if consumed:
		return

	if launched:
		global_position += velocity * delta
		rotation += delta * 10.0
		check_projectile_hit()
		return

	if owner_player == null or !is_instance_valid(owner_player):
		queue_free()
		return

	var count: int = int(owner_player.call("get_green_satellite_count"))
	if count <= 0:
		queue_free()
		return

	var index: int = int(owner_player.call("get_green_satellite_index", self))
	if index < 0:
		queue_free()
		return

	var orbit_angle: float = (Time.get_ticks_msec() / 1000.0 * ORBIT_SPEED) + (TAU * float(index) / float(count))
	global_position = owner_player.global_position + Vector2(ORBIT_RADIUS * owner_player.scale.x, 0).rotated(orbit_angle)
	rotation += delta * 4.0

func _on_area_entered(area: Area2D) -> void:
	if consumed or owner_player == null or !is_instance_valid(owner_player):
		return

	var target = area.get_parent()
	if target == null or target == owner_player:
		return

	if target.has_method("take_damage") and target.has_method("register_hit"):
		consumed = true
		target.call("take_damage", DAMAGE)
		if owner_player != null and is_instance_valid(owner_player):
			owner_player.call("remove_green_satellite", self)
		else:
			queue_free()

func launch_at(target: Node2D) -> void:
	if target == null or !is_instance_valid(target) or consumed:
		return

	if owner_player != null and is_instance_valid(owner_player):
		owner_player.call("release_green_satellite", self)

	var direction: Vector2 = (target.global_position - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	launched = true
	velocity = direction * PROJECTILE_SPEED
	launch_target = target
	owner_player = null

func check_projectile_hit() -> void:
	if consumed or launch_target == null or !is_instance_valid(launch_target):
		return

	var hit_radius_scaled: float = PROJECTILE_HIT_RADIUS * max(launch_target.scale.x, 1.0)
	if global_position.distance_to(launch_target.global_position) <= hit_radius_scaled:
		consumed = true
		launch_target.call("take_damage", DAMAGE)
		queue_free()

func create_visuals() -> void:
	var aura := Polygon2D.new()
	aura.polygon = make_circle_points(34.0, 18)
	aura.color = Color(0.35, 1.0, 0.35, 0.2)
	add_child(aura)

	var orb := Polygon2D.new()
	orb.polygon = make_circle_points(20.0, 16)
	orb.color = Color(0.45, 1.0, 0.55, 0.95)
	add_child(orb)

	var gem := Polygon2D.new()
	gem.polygon = PackedVector2Array([
		Vector2(0, -18),
		Vector2(12, -4),
		Vector2(8, 16),
		Vector2(-8, 16),
		Vector2(-12, -4)
	])
	gem.color = Color(0.85, 1.0, 0.9, 0.95)
	add_child(gem)

func make_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
