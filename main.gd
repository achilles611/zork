extends Node2D

const PLAYER_SCENE = preload("res://Player.tscn")
const ORB_SCENE = preload("res://orb.tscn")
const CRYSTAL_CLUSTER_SCENE = preload("res://CrystalCluster.tscn")
const BORDER_THICKNESS := 240.0
const BORDER_INSET := 10.0
const MAP_SCALE_FACTOR := 2.7
const ARENA_RADIUS_FACTOR := 0.44
const BORDER_SEGMENT_COUNT := 72
const CAMERA_ZOOM_SMOOTHNESS := 8.0
const CRYSTAL_CLUSTER_SCALE := 2.05
const STAR_COUNT := 180
const NPC_ATTACK_DELAY := 3.0
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
@onready var round_end_overlay = $CanvasLayer/RoundEndOverlay
@onready var round_end_title = $CanvasLayer/RoundEndOverlay/RoundEndPanel/RoundEndTitle
@onready var round_end_subtitle = $CanvasLayer/RoundEndOverlay/RoundEndPanel/RoundEndSubtitle
@onready var replay_button = $CanvasLayer/RoundEndOverlay/RoundEndPanel/ReplayButton
@onready var quit_button = $CanvasLayer/RoundEndOverlay/RoundEndPanel/QuitButton

var arena_size: Vector2
var arena_center: Vector2
var arena_radius := 0.0
var base_camera_zoom: Vector2
var player_one: Node2D = null
var shift_was_pressed := false
var console_open := false
var round_over := false
var npc_attack_delay_remaining := NPC_ATTACK_DELAY
var mobile_dash_requested := false

func get_camera_world_size() -> Vector2:
	var viewport_size = get_viewport_rect().size
	var zoom = camera.zoom
	return viewport_size / zoom

func _ready() -> void:
	randomize()

	base_camera_zoom = camera.zoom
	arena_size = get_camera_world_size() * MAP_SCALE_FACTOR
	arena_center = arena_size / 2.0
	arena_radius = min(arena_size.x, arena_size.y) * ARENA_RADIUS_FACTOR
	camera.position = arena_center
	camera.enabled = true

	print("Arena size: ", arena_size)
	print("Arena radius: ", arena_radius)
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
	setup_round_end_overlay()
	update_camera()
	npc_attack_delay_remaining = NPC_ATTACK_DELAY

	print("Total players spawned: ", players_node.get_child_count())
	print("Total orbs spawned: ", orbs_node.get_child_count())

func spawn_players() -> void:
	if players_node.get_child_count() > 0:
		print("spawn_players skipped: players already exist")
		return

	var horizontal_offset := arena_radius * 0.72

	var positions = [
		arena_center + Vector2(-horizontal_offset, 0),
		arena_center + Vector2(horizontal_offset, 0)
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
	for i in range(count):
		var orb = ORB_SCENE.instantiate()
		orb.position = random_point_in_arena(180.0)
		orb.orb_type = orb_type
		orbs_node.add_child(orb)

	print("Spawned ", count, " orbs of type ", orb_type)

func spawn_crystal_clusters() -> void:
	if crystals_node.get_child_count() > 0:
		return

	var positions = [
		arena_center + Vector2(-arena_radius * 0.46, -arena_radius * 0.1),
		arena_center + Vector2(arena_radius * 0.46, -arena_radius * 0.1)
	]

	var cluster_count: int = mini(players_node.get_child_count(), positions.size())
	for i in range(cluster_count):
		var cluster = CRYSTAL_CLUSTER_SCENE.instantiate()
		cluster.position = positions[i]
		cluster.scale = Vector2.ONE * CRYSTAL_CLUSTER_SCALE
		crystals_node.add_child(cluster)

func setup_background() -> void:
	for child in background_node.get_children():
		child.queue_free()

	var backdrop := Polygon2D.new()
	backdrop.polygon = make_circle_points(arena_radius, 96)
	backdrop.position = arena_center
	backdrop.color = Color(0.01, 0.01, 0.03, 1.0)
	background_node.add_child(backdrop)

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	for i in range(STAR_COUNT):
		var star := Polygon2D.new()
		var star_radius: float = rng.randf_range(3.0, 11.0)
		star.polygon = make_circle_points(star_radius, 10)
		star.position = random_point_in_arena(140.0)

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

	var border_points := PackedVector2Array()
	var ring_radius := arena_radius - BORDER_INSET
	for i in range(BORDER_SEGMENT_COUNT + 1):
		var angle: float = TAU * float(i) / float(BORDER_SEGMENT_COUNT)
		border_points.append(arena_center + Vector2(cos(angle), sin(angle)) * ring_radius)

	for i in range(BORDER_SEGMENT_COUNT):
		create_border_segment(border_points[i], border_points[i + 1], i)

	border_glow_outer.points = border_points
	border_glow_inner.points = border_points
	border_core.points = border_points

func create_border_segment(from_point: Vector2, to_point: Vector2, index: int) -> void:
	var body := StaticBody2D.new()
	body.name = "BorderSegment%d" % index
	body.position = (from_point + to_point) * 0.5
	body.rotation = (to_point - from_point).angle()

	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(from_point.distance_to(to_point) + BORDER_THICKNESS, BORDER_THICKNESS)
	shape.shape = rectangle

	body.add_child(shape)
	borders_node.add_child(body)

func random_point_in_arena(margin: float = 0.0) -> Vector2:
	var usable_radius: float = maxf(arena_radius - margin, 0.0)
	var angle: float = randf() * TAU
	var distance: float = sqrt(randf()) * usable_radius
	return arena_center + Vector2(cos(angle), sin(angle)) * distance

func get_arena_center() -> Vector2:
	return arena_center

func get_arena_radius() -> float:
	return arena_radius

func _process(delta: float) -> void:
	if npc_attack_delay_remaining > 0.0 and !round_over:
		npc_attack_delay_remaining = maxf(npc_attack_delay_remaining - delta, 0.0)
	handle_input()
	check_round_end()
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
	var zoom_factor := 1.0
	if player_one.has_method("get_camera_zoom_factor"):
		zoom_factor = float(player_one.call("get_camera_zoom_factor"))
	var target_zoom: Vector2 = base_camera_zoom / max(zoom_factor, 1.0)
	var weight: float = clampf(delta * CAMERA_ZOOM_SMOOTHNESS, 0.0, 1.0)
	camera.zoom = camera.zoom.lerp(target_zoom, weight)

func setup_camera_limits() -> void:
	camera.limit_left = int(arena_center.x - arena_radius)
	camera.limit_top = int(arena_center.y - arena_radius)
	camera.limit_right = int(arena_center.x + arena_radius)
	camera.limit_bottom = int(arena_center.y + arena_radius)

func handle_input() -> void:
	if round_over:
		for player in players_node.get_children():
			if is_instance_valid(player):
				player.set_input(Vector2.ZERO)
		shift_was_pressed = false
		mobile_dash_requested = false
		return

	if console_open:
		if player_one != null and is_instance_valid(player_one):
			player_one.set_input(Vector2.ZERO)
		shift_was_pressed = false
		mobile_dash_requested = false
		return

	var players = players_node.get_children()
	var shift_pressed: bool = Input.is_key_pressed(KEY_SHIFT)

	if players.size() > 0 and is_instance_valid(players[0]):
		var keyboard_input: Vector2 = Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
		var mobile_input: Vector2 = Vector2.ZERO
		if mobile_controls != null and mobile_controls.visible:
			mobile_input = mobile_controls.get_move_vector()
		players[0].set_input((keyboard_input + mobile_input).limit_length())

		if (shift_pressed and !shift_was_pressed) or mobile_dash_requested:
			players[0].try_dash_attack()

	if players.size() > 1 and is_instance_valid(players[1]):
		players[1].set_input(get_npc_input(players[1]))

	shift_was_pressed = shift_pressed
	mobile_dash_requested = false

func get_npc_input(npc: Node2D) -> Vector2:
	if player_one == null or !is_instance_valid(player_one):
		return Vector2.ZERO
	if npc_attack_delay_remaining > 0.0:
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
	mobile_controls.dash_requested.connect(_on_mobile_dash_requested)

func setup_round_end_overlay() -> void:
	round_end_overlay.visible = false
	round_end_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	replay_button.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	quit_button.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	replay_button.pressed.connect(_on_replay_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func should_show_mobile_controls() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()

func _on_mobile_dash_requested() -> void:
	if console_open or round_over:
		return

	mobile_dash_requested = true

func check_round_end() -> void:
	if round_over:
		return

	var surviving_players: Array[Node2D] = []
	for candidate in players_node.get_children():
		var node := candidate as Node2D
		if node != null and is_instance_valid(node):
			surviving_players.append(node)

	if surviving_players.size() <= 1:
		var winner: Node2D = surviving_players[0] if surviving_players.size() == 1 else null
		end_round(winner)

func end_round(winner: Node2D) -> void:
	round_over = true
	console_open = false
	console_panel.visible = false
	if mobile_controls != null:
		mobile_controls.visible = false

	for player in players_node.get_children():
		if is_instance_valid(player):
			player.set_input(Vector2.ZERO)

	if winner != null and is_instance_valid(winner):
		round_end_title.text = "Player %d Wins" % int(winner.get("player_id"))
		round_end_subtitle.text = "Only one fighter remains."
	else:
		round_end_title.text = "Round Over"
		round_end_subtitle.text = "No players survived."

	round_end_overlay.visible = true
	get_tree().paused = true

func _on_replay_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()

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
