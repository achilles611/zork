extends Node2D

const PLAYER_SCENE = preload("res://Player.tscn")
const ORB_SCENE = preload("res://orb.tscn")
const CRYSTAL_CLUSTER_SCENE = preload("res://CrystalCluster.tscn")
const BORDER_THICKNESS := 120.0
const BORDER_INSET := 10.0
const MAP_SCALE_FACTOR := 3.0
const CAMERA_ZOOM_SMOOTHNESS := 8.0
const CRYSTAL_CLUSTER_SCALE := 1.4
const STAR_COUNT := 180
const ADMIN_LASER_SOUND_MIX_RATE := 22050.0
const ADMIN_LASER_SOUND_DURATION := 0.55
const ADMIN_LASER_SOUND_VOLUME_DB := -4.0

@onready var background_node = $Background
@onready var players_node = $Players
@onready var orbs_node = $Orbs
@onready var crystals_node = $Crystals
@onready var camera = $Camera2D
@onready var borders_node = $Borders
@onready var border_glow_outer = $BorderGlowOuter
@onready var border_glow_inner = $BorderGlowInner
@onready var border_core = $BorderCore
@onready var console_layer = $CanvasLayer
@onready var console_panel = $CanvasLayer/ConsolePanel
@onready var console_log = $CanvasLayer/ConsolePanel/ConsoleLog
@onready var console_input = $CanvasLayer/ConsolePanel/ConsoleInput
@onready var mobile_controls = $CanvasLayer/MobileControls

var arena_size: Vector2
var base_camera_zoom: Vector2
var player_one: Node2D = null
var space_was_pressed := false
var console_open := false

func get_camera_world_size() -> Vector2:
	var viewport_size = get_viewport_rect().size
	var zoom = camera.zoom
	return viewport_size / zoom

func _ready() -> void:
	randomize()

	base_camera_zoom = camera.zoom
	arena_size = get_camera_world_size() * MAP_SCALE_FACTOR
	camera.position = arena_size / 2.0
	camera.enabled = true

	print("Arena size: ", arena_size)
	print("Camera position: ", camera.position)
	print("Camera zoom: ", camera.zoom)

	setup_background()
	setup_camera_limits()
	setup_arena_border()
	spawn_players()
	spawn_crystal_clusters()
	spawn_orbs()
	setup_console()
	setup_mobile_controls()
	update_camera()

	print("Total players spawned: ", players_node.get_child_count())
	print("Total orbs spawned: ", orbs_node.get_child_count())

func spawn_players() -> void:
	if players_node.get_child_count() > 0:
		print("spawn_players skipped: players already exist")
		return

	var horizontal_margin := 300.0
	var center_y := arena_size.y / 2.0

	var positions = [
		Vector2(horizontal_margin, center_y),
		Vector2(arena_size.x - horizontal_margin, center_y)
	]

	print("Spawning players...")

	for i in range(2):
		var p = PLAYER_SCENE.instantiate()
		p.position = positions[i]
		p.player_id = i + 1
		players_node.add_child(p)
		if i == 0:
			player_one = p
		print("Spawned player ", i + 1, " at ", p.position)

func spawn_orbs() -> void:
	if orbs_node.get_child_count() > 0:
		print("spawn_orbs skipped: orbs already exist")
		return

	print("Spawning orbs...")
	spawn_orb_batch(100, 0) # white
	spawn_orb_batch(50, 1)  # blue
	spawn_orb_batch(50, 2)  # red

func spawn_orb_batch(count: int, orb_type: int) -> void:
	var margin := 100.0

	for i in range(count):
		var orb = ORB_SCENE.instantiate()
		orb.position = Vector2(
			randf_range(margin, arena_size.x - margin),
			randf_range(margin, arena_size.y - margin)
		)
		orb.orb_type = orb_type
		orbs_node.add_child(orb)

	print("Spawned ", count, " orbs of type ", orb_type)

func spawn_crystal_clusters() -> void:
	if crystals_node.get_child_count() > 0:
		return

	var players = players_node.get_children()
	var offsets = [
		Vector2(1800, -150),
		Vector2(-1800, -150)
	]

	var cluster_count: int = mini(players.size(), offsets.size())
	for i in range(cluster_count):
		var cluster = CRYSTAL_CLUSTER_SCENE.instantiate()
		cluster.position = players[i].position + offsets[i]
		cluster.scale = Vector2.ONE * CRYSTAL_CLUSTER_SCALE
		crystals_node.add_child(cluster)

func setup_background() -> void:
	for child in background_node.get_children():
		child.queue_free()

	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(arena_size.x, 0),
		Vector2(arena_size.x, arena_size.y),
		Vector2(0, arena_size.y)
	])
	backdrop.color = Color(0.01, 0.01, 0.03, 1.0)
	background_node.add_child(backdrop)

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	for i in range(STAR_COUNT):
		var star := Polygon2D.new()
		var star_radius: float = rng.randf_range(3.0, 11.0)
		star.polygon = make_circle_points(star_radius, 10)
		star.position = Vector2(
			rng.randf_range(120.0, arena_size.x - 120.0),
			rng.randf_range(120.0, arena_size.y - 120.0)
		)

		if rng.randf() < 0.28:
			star.color = Color(0.55, 0.72, 1.0, rng.randf_range(0.65, 0.95))
		else:
			star.color = Color(0.95, 0.98, 1.0, rng.randf_range(0.45, 0.9))
		background_node.add_child(star)

		if rng.randf() < 0.14:
			var flare := Line2D.new()
			flare.width = rng.randf_range(2.0, 4.0)
			flare.default_color = Color(0.8, 0.9, 1.0, 0.3)
			var flare_size: float = star_radius * rng.randf_range(3.0, 5.5)
			flare.points = PackedVector2Array([
				Vector2(-flare_size, 0),
				Vector2(flare_size, 0),
				Vector2.ZERO,
				Vector2(0, -flare_size),
				Vector2(0, flare_size)
			])
			flare.position = star.position
			background_node.add_child(flare)

func make_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func setup_arena_border() -> void:
	for child in borders_node.get_children():
		child.queue_free()

	var half_thickness := BORDER_THICKNESS / 2.0
	var top_size := Vector2(arena_size.x + BORDER_THICKNESS, BORDER_THICKNESS)
	var side_size := Vector2(BORDER_THICKNESS, arena_size.y + BORDER_THICKNESS)

	create_border("TopBorder", Vector2(arena_size.x / 2.0, -half_thickness), top_size)
	create_border("BottomBorder", Vector2(arena_size.x / 2.0, arena_size.y + half_thickness), top_size)
	create_border("LeftBorder", Vector2(-half_thickness, arena_size.y / 2.0), side_size)
	create_border("RightBorder", Vector2(arena_size.x + half_thickness, arena_size.y / 2.0), side_size)

	var border_points := PackedVector2Array([
		Vector2(BORDER_INSET, BORDER_INSET),
		Vector2(arena_size.x - BORDER_INSET, BORDER_INSET),
		Vector2(arena_size.x - BORDER_INSET, arena_size.y - BORDER_INSET),
		Vector2(BORDER_INSET, arena_size.y - BORDER_INSET),
		Vector2(BORDER_INSET, BORDER_INSET)
	])

	border_glow_outer.points = border_points
	border_glow_inner.points = border_points
	border_core.points = border_points

func create_border(border_name: String, position: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = border_name
	body.position = position

	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle

	body.add_child(shape)
	borders_node.add_child(body)

func _process(delta: float) -> void:
	handle_input()
	update_camera(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and !event.echo:
		if event.keycode == KEY_QUOTELEFT or event.keycode == KEY_ASCIITILDE:
			toggle_console()
			get_viewport().set_input_as_handled()
			return

		if console_open and event.keycode == KEY_ESCAPE:
			toggle_console(false)
			get_viewport().set_input_as_handled()

func update_camera(delta: float = 1.0) -> void:
	if player_one == null or !is_instance_valid(player_one):
		return

	camera.global_position = player_one.global_position
	var target_zoom: Vector2 = base_camera_zoom / max(player_one.scale.x, 1.0)
	var weight: float = clampf(delta * CAMERA_ZOOM_SMOOTHNESS, 0.0, 1.0)
	camera.zoom = camera.zoom.lerp(target_zoom, weight)

func setup_camera_limits() -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(arena_size.x)
	camera.limit_bottom = int(arena_size.y)

func handle_input() -> void:
	if console_open:
		if player_one != null and is_instance_valid(player_one):
			player_one.set_input(Vector2.ZERO)
			player_one.set_burning(false)
		space_was_pressed = false
		return

	var players = players_node.get_children()
	var space_pressed: bool = Input.is_key_pressed(KEY_SPACE)

	if players.size() > 0 and is_instance_valid(players[0]):
		var keyboard_input: Vector2 = Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
		var mobile_input: Vector2 = Vector2.ZERO
		if mobile_controls != null and mobile_controls.visible:
			mobile_input = mobile_controls.get_move_vector()
		players[0].set_input((keyboard_input + mobile_input).limit_length())
		var mobile_burn: bool = mobile_controls != null and mobile_controls.visible and mobile_controls.is_burn_active()
		players[0].set_burning(Input.is_key_pressed(KEY_SHIFT) or mobile_burn)
		if space_pressed and !space_was_pressed:
			players[0].fire_green_satellites(players)

	if players.size() > 1 and is_instance_valid(players[1]):
		players[1].set_input(get_npc_input(players[1]))

	space_was_pressed = space_pressed

func get_npc_input(npc: Node2D) -> Vector2:
	if player_one == null or !is_instance_valid(player_one):
		return Vector2.ZERO

	return (player_one.global_position - npc.global_position).normalized()

func setup_console() -> void:
	console_panel.visible = false
	console_layer.layer = 10
	console_input.text_submitted.connect(_on_console_command_submitted)
	append_console_log("Admin console ready. Type `help`.")

func setup_mobile_controls() -> void:
	if mobile_controls == null:
		return

	mobile_controls.visible = should_show_mobile_controls()
	mobile_controls.fire_requested.connect(_on_mobile_fire_requested)

func should_show_mobile_controls() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()

func _on_mobile_fire_requested() -> void:
	if console_open:
		return

	var players = players_node.get_children()
	if players.size() > 0 and is_instance_valid(players[0]):
		players[0].fire_green_satellites(players)

func toggle_console(force_open: Variant = null) -> void:
	if force_open == null:
		console_open = !console_open
	else:
		console_open = bool(force_open)

	console_panel.visible = console_open

	if console_open:
		console_input.editable = true
		console_input.grab_focus()
		console_input.caret_column = console_input.text.length()
	else:
		console_input.release_focus()

func _on_console_command_submitted(text: String) -> void:
	var command := text.strip_edges()
	if command.is_empty():
		return

	append_console_log("> %s" % command)
	console_input.clear()
	run_console_command(command)
	if console_open:
		console_input.grab_focus()

func run_console_command(command: String) -> void:
	match command.to_lower():
		"help":
			append_console_log("Commands: help, clear, god")
		"clear":
			console_log.clear()
		"god":
			run_god_command()
		_:
			append_console_log("Unknown command.")

func run_god_command() -> void:
	var source := player_one
	var target := get_first_opponent_player()

	if source == null or !is_instance_valid(source):
		append_console_log("No player1 found.")
		return

	if target == null:
		append_console_log("No opponent to smite.")
		return

	fire_admin_laser(source.global_position, target.global_position)
	play_admin_laser_sound(source.global_position)
	target.call("kill_instantly")
	append_console_log("Opponent deleted by divine laser.")

func get_first_opponent_player() -> Node2D:
	for candidate in players_node.get_children():
		var node := candidate as Node2D
		if node != null and node != player_one and is_instance_valid(node):
			return node
	return null

func fire_admin_laser(origin: Vector2, target: Vector2) -> void:
	var beam := Line2D.new()
	beam.top_level = true
	beam.z_index = 50
	beam.width = 54.0
	beam.default_color = Color(0.7, 0.95, 1.0, 0.95)
	beam.points = PackedVector2Array([origin, target])
	add_child(beam)

	var core := Line2D.new()
	core.top_level = true
	core.z_index = 51
	core.width = 18.0
	core.default_color = Color(1.0, 1.0, 1.0, 1.0)
	core.points = PackedVector2Array([origin, target])
	add_child(core)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(beam, "modulate:a", 0.0, 0.22)
	tween.tween_property(beam, "width", 110.0, 0.22)
	tween.tween_property(core, "modulate:a", 0.0, 0.16)
	tween.tween_property(core, "width", 2.0, 0.16)
	tween.chain().tween_callback(beam.queue_free)
	tween.chain().tween_callback(core.queue_free)

func play_admin_laser_sound(position: Vector2) -> void:
	var player := AudioStreamPlayer2D.new()
	player.top_level = true
	player.global_position = position
	player.max_distance = 100000.0
	player.volume_db = ADMIN_LASER_SOUND_VOLUME_DB

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = ADMIN_LASER_SOUND_MIX_RATE
	stream.buffer_length = ADMIN_LASER_SOUND_DURATION
	player.stream = stream
	add_child(player)
	player.play()

	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		player.queue_free()
		return

	var frame_count: int = int(ADMIN_LASER_SOUND_MIX_RATE * ADMIN_LASER_SOUND_DURATION)
	for i in range(frame_count):
		var t: float = float(i) / ADMIN_LASER_SOUND_MIX_RATE
		var decay: float = exp(-4.2 * t)
		var sweep_hz: float = 2200.0 - (1600.0 * (t / ADMIN_LASER_SOUND_DURATION))
		var scream: float = sin(TAU * sweep_hz * t) * 0.26 * decay
		var bass: float = sin(TAU * 120.0 * t) * 0.16 * decay
		var crackle: float = (randf() * 2.0 - 1.0) * 0.09 * decay
		var sample: float = scream + bass + crackle
		playback.push_frame(Vector2(sample, sample))

	var timer := get_tree().create_timer(ADMIN_LASER_SOUND_DURATION + 0.05)
	timer.timeout.connect(player.queue_free)

func append_console_log(line: String) -> void:
	console_log.append_text(line + "\n")
	console_log.scroll_to_line(max(console_log.get_line_count() - 1, 0))
