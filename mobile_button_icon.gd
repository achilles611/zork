extends Control

@export_enum("fire", "burn") var icon_type := "fire":
	set(value):
		icon_type = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if icon_type == "burn":
		draw_burn_icon()
	else:
		draw_fire_icon()

func draw_fire_icon() -> void:
	var body_color := Color(0.58, 1.0, 0.72, 1.0)
	var glow_color := Color(0.28, 1.0, 0.56, 0.22)
	var outline_color := Color(0.9, 1.0, 0.95, 0.92)
	var flame_outer := Color(1.0, 0.82, 0.32, 0.95)
	var flame_inner := Color(1.0, 0.45, 0.16, 0.95)

	var orb_center: Vector2 = size * Vector2(0.58, 0.48)
	var orb_radius: float = min(size.x, size.y) * 0.17
	draw_circle(orb_center, orb_radius * 1.7, glow_color)

	var rocket_points := PackedVector2Array([
		size * Vector2(0.12, 0.50),
		size * Vector2(0.34, 0.38),
		size * Vector2(0.34, 0.62),
	])
	draw_colored_polygon(rocket_points, Color.WHITE)

	var flame_outer_points := PackedVector2Array([
		size * Vector2(0.06, 0.50),
		size * Vector2(0.16, 0.42),
		size * Vector2(0.16, 0.58),
	])
	var flame_inner_points := PackedVector2Array([
		size * Vector2(0.11, 0.50),
		size * Vector2(0.17, 0.45),
		size * Vector2(0.17, 0.55),
	])
	draw_colored_polygon(flame_outer_points, flame_outer)
	draw_colored_polygon(flame_inner_points, flame_inner)

	var connector_width: float = max(4.0, size.x * 0.018)
	draw_line(size * Vector2(0.33, 0.50), size * Vector2(0.46, 0.50), outline_color, connector_width, true)

	draw_circle(orb_center, orb_radius, body_color)
	draw_arc(orb_center, orb_radius * 1.08, -PI * 0.9, PI * 0.9, 40, outline_color, max(4.0, size.x * 0.018), true)
	draw_arc(orb_center, orb_radius * 0.58, -PI * 0.88, PI * 0.88, 24, Color(1, 1, 1, 0.95), max(2.0, size.x * 0.012), true)

	var sparkle_center: Vector2 = orb_center + size * Vector2(0.14, -0.14)
	var sparkle_radius: float = orb_radius * 0.25
	draw_circle(sparkle_center, sparkle_radius * 1.8, Color(0.82, 1.0, 0.9, 0.18))
	draw_circle(sparkle_center, sparkle_radius, Color(1, 1, 1, 0.95))

func draw_burn_icon() -> void:
	var glow_color := Color(0.28, 1.0, 0.54, 0.2)
	var outer_color := Color(0.62, 1.0, 0.72, 0.98)
	var inner_color := Color(1.0, 1.0, 1.0, 0.96)
	var core_color := Color(0.15, 0.55, 0.2, 0.16)

	var center: Vector2 = size * 0.5
	var points := PackedVector2Array([
		size * Vector2(0.50, 0.12),
		size * Vector2(0.63, 0.39),
		size * Vector2(0.88, 0.50),
		size * Vector2(0.63, 0.61),
		size * Vector2(0.50, 0.88),
		size * Vector2(0.37, 0.61),
		size * Vector2(0.12, 0.50),
		size * Vector2(0.37, 0.39),
	])

	var glow_points := PackedVector2Array()
	for point in points:
		glow_points.append(center + (point - center) * 1.12)
	draw_colored_polygon(glow_points, glow_color)
	draw_colored_polygon(points, core_color)

	var outer_width: float = max(7.0, size.x * 0.04)
	var inner_width: float = max(3.0, size.x * 0.018)
	for i in points.size():
		var from: Vector2 = points[i]
		var to: Vector2 = points[(i + 1) % points.size()]
		draw_line(from, to, outer_color, outer_width, true)
		draw_line(from, to, inner_color, inner_width, true)
