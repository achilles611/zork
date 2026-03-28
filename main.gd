extends Node2D

const PLAYER_SCENE = preload("res://Player.tscn")
const ORB_SCENE = preload("res://orb.tscn")
const CRYSTAL_CLUSTER_SCENE = preload("res://CrystalCluster.tscn")
const GREEN_PICKUP_SCENE = preload("res://GreenCrystalPickup.tscn")
const CASTLE_PAD_SCENE = preload("res://CastlePad.tscn")
const CASTLE_MINION_SCENE = preload("res://CastleMinion.tscn")

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
const MAX_LOBBY_SLOTS := 8
const PLAYER_SPAWN_RADIUS_FACTOR := 0.82
const SNAPSHOT_INTERVAL := 0.08
const INPUT_SEND_INTERVAL := 0.05

enum GamePhase {
	TITLE,
	LOBBY,
	ROUND,
	ROUND_END,
}

@onready var background_node = $Background
@onready var players_node = $Players
@onready var orbs_node = $Orbs
@onready var crystals_node = $Crystals
@onready var structures_node = $Structures
@onready var minions_node = $Minions
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
@onready var title_screen = $CanvasLayer/TitleScreen
@onready var title_splash = $CanvasLayer/TitleScreen/Content/VBox/TitleSplash
@onready var quick_play_button = $CanvasLayer/TitleScreen/Content/VBox/MenuButtons/QuickPlayButton
@onready var open_lobby_button = $CanvasLayer/TitleScreen/Content/VBox/MenuButtons/OpenLobbyButton
@onready var quit_title_button = $CanvasLayer/TitleScreen/Content/VBox/MenuButtons/QuitTitleButton
@onready var lobby_screen = $CanvasLayer/LobbyScreen
@onready var lobby_slots_vbox = $CanvasLayer/LobbyScreen/LobbyPanel/LobbyVBox/SlotsScroll/SlotsVBox
@onready var back_to_title_button = $CanvasLayer/LobbyScreen/LobbyPanel/LobbyVBox/LobbyButtons/BackToTitleButton
@onready var start_match_button = $CanvasLayer/LobbyScreen/LobbyPanel/LobbyVBox/LobbyButtons/StartMatchButton
@onready var lobby_subtitle = $CanvasLayer/LobbyScreen/LobbyPanel/LobbyVBox/LobbySubtitle

var arena_size := Vector2.ZERO
var arena_center := Vector2.ZERO
var arena_radius := 0.0
var base_camera_zoom := Vector2.ONE
var player_one: Node2D = null
var shift_was_pressed := false
var console_open := false
var round_over := false
var npc_attack_delay_remaining := NPC_ATTACK_DELAY
var mobile_dash_requested := false
var game_phase := GamePhase.TITLE
var lobby_slots: Array[Dictionary] = []
var lobby_slot_rows: Array[Dictionary] = []
var rematch_votes := {}
var return_to_lobby_requested := false
var local_client_id := ""
var network_host_client_id := ""
var active_participants: Array[Dictionary] = []
var network_enabled := false
var network_round_host := false
var local_quick_play := false
var remote_input_states := {}
var snapshot_accumulator := 0.0
var input_accumulator := 0.0
var local_slot_index := -1
var orb_id_counter := 0
var crystal_id_counter := 0
var last_sent_move := Vector2.ZERO
var pending_dash_send := false

func get_camera_world_size() -> Vector2:
	var viewport_size = get_viewport_rect().size
	return viewport_size / camera.zoom

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	base_camera_zoom = camera.zoom
	arena_size = get_camera_world_size() * MAP_SCALE_FACTOR
	arena_center = arena_size / 2.0
	arena_radius = min(arena_size.x, arena_size.y) * ARENA_RADIUS_FACTOR
	camera.position = arena_center
	camera.enabled = true
	setup_background()
	setup_camera_limits()
	setup_arena_border()
	setup_console()
	setup_mobile_controls()
	setup_round_end_overlay()
	setup_title_screen()
	setup_lobby_screen()
	initialize_lobby_slots()
	populate_lobby_ui()
	setup_networking()
	show_title_screen()

func _process(delta: float) -> void:
	if game_phase == GamePhase.ROUND and npc_attack_delay_remaining > 0.0 and !round_over:
		npc_attack_delay_remaining = maxf(npc_attack_delay_remaining - delta, 0.0)
	handle_input(delta)
	if game_phase == GamePhase.ROUND:
		if !network_enabled or network_round_host or local_quick_play:
			check_round_end()
		if network_enabled and network_round_host:
			snapshot_accumulator += delta
			if snapshot_accumulator >= SNAPSHOT_INTERVAL:
				snapshot_accumulator = 0.0
				NetworkClient.send_message("round_snapshot", build_round_snapshot())
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

func setup_networking() -> void:
	NetworkClient.welcome_received.connect(_on_network_welcome_received)
	NetworkClient.lobby_state_received.connect(_on_network_lobby_state_received)
	NetworkClient.match_started.connect(_on_network_match_started)
	NetworkClient.round_snapshot_received.connect(_on_network_round_snapshot_received)
	NetworkClient.remote_input_received.connect(_on_network_remote_input_received)
	NetworkClient.server_message.connect(_on_network_server_message)
	NetworkClient.connection_state_changed.connect(_on_network_connection_state_changed)
	NetworkClient.connect_to_default_server()

func _on_network_connection_state_changed(state: String) -> void:
	network_enabled = state == "connected"
	update_lobby_subtitle()
	update_start_button_state()

func _on_network_welcome_received(payload: Dictionary) -> void:
	local_client_id = str(payload.get("client_id", ""))
	network_host_client_id = str(payload.get("host_client_id", ""))
	if local_client_id != "":
		NetworkClient.send_message("register", {"nickname": "Player-%s" % local_client_id.substr(0, 4)})

func _on_network_lobby_state_received(payload: Dictionary) -> void:
	network_enabled = true
	network_host_client_id = str(payload.get("host_client_id", network_host_client_id))
	var slots = payload.get("slots", [])
	if slots is Array:
		lobby_slots.clear()
		for slot in slots:
			if slot is Dictionary:
				lobby_slots.append(slot.duplicate(true))
	local_slot_index = get_local_slot_index()
	update_lobby_subtitle()
	populate_lobby_ui()
	if str(payload.get("phase", "lobby")) == "lobby" and game_phase in [GamePhase.ROUND, GamePhase.ROUND_END]:
		show_lobby_screen()

func _on_network_match_started(payload: Dictionary) -> void:
	network_enabled = true
	network_round_host = str(payload.get("host_client_id", "")) == local_client_id
	active_participants.clear()
	var participants = payload.get("participants", [])
	if participants is Array:
		for participant in participants:
			if participant is Dictionary:
				active_participants.append(participant.duplicate(true))
	local_slot_index = get_local_participant_slot_index()
	start_network_round()

func _on_network_round_snapshot_received(payload: Dictionary) -> void:
	if network_round_host:
		return
	apply_round_snapshot(payload)

func _on_network_remote_input_received(payload: Dictionary) -> void:
	var client_id := str(payload.get("client_id", ""))
	if client_id.is_empty():
		return
	remote_input_states[client_id] = {
		"move": payload.get("move", [0.0, 0.0]),
		"dash_pressed": bool(payload.get("dash_pressed", false)),
	}

func _on_network_server_message(message_type: String, payload: Dictionary) -> void:
	if message_type == "admin_set_energy" and network_round_host:
		apply_network_admin_set_energy(payload)

func setup_title_screen() -> void:
	title_splash.texture = load("res://art/title_zork.png")
	quick_play_button.pressed.connect(_on_quick_play_pressed)
	open_lobby_button.pressed.connect(_on_open_lobby_pressed)
	quit_title_button.pressed.connect(_on_quit_title_pressed)

func setup_lobby_screen() -> void:
	back_to_title_button.pressed.connect(_on_back_to_title_pressed)
	start_match_button.pressed.connect(_on_start_match_pressed)

func setup_console() -> void:
	console_panel.visible = false
	console_layer.layer = 10
	console_input.text_submitted.connect(_on_console_command_submitted)
	append_console_log("Admin console ready. Type `help`.")

func setup_mobile_controls() -> void:
	if mobile_controls == null:
		return
	if mobile_controls.has_method("set_controls_active"):
		mobile_controls.call("set_controls_active", false)
	else:
		mobile_controls.visible = false
	mobile_controls.dash_requested.connect(_on_mobile_dash_requested)

func setup_round_end_overlay() -> void:
	round_end_overlay.visible = false
	round_end_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	replay_button.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	quit_button.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	replay_button.text = "Run Again"
	quit_button.text = "Return To Lobby"
	replay_button.pressed.connect(_on_replay_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

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

func setup_camera_limits() -> void:
	camera.limit_left = int(arena_center.x - arena_radius)
	camera.limit_top = int(arena_center.y - arena_radius)
	camera.limit_right = int(arena_center.x + arena_radius)
	camera.limit_bottom = int(arena_center.y + arena_radius)

func update_camera(delta: float = 1.0) -> void:
	if player_one == null or !is_instance_valid(player_one):
		camera.global_position = arena_center
		return
	camera.global_position = player_one.global_position
	var zoom_factor := 1.0
	if player_one.has_method("get_camera_zoom_factor"):
		zoom_factor = float(player_one.call("get_camera_zoom_factor"))
	var target_zoom: Vector2 = base_camera_zoom / max(zoom_factor, 1.0)
	var weight: float = clampf(delta * CAMERA_ZOOM_SMOOTHNESS, 0.0, 1.0)
	camera.zoom = camera.zoom.lerp(target_zoom, weight)
func initialize_lobby_slots() -> void:
	lobby_slots.clear()
	for i in range(MAX_LOBBY_SLOTS):
		lobby_slots.append({
			"nickname": "AI %d" % (i + 1),
			"type": "open",
			"owner_id": null,
		})
	lobby_slots[0] = {
		"nickname": "Player 1",
		"type": "human",
		"owner_id": local_client_id,
	}

func populate_lobby_ui() -> void:
	if lobby_slot_rows.is_empty():
		for i in range(MAX_LOBBY_SLOTS):
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation", 18)
			var slot_label := Label.new()
			slot_label.custom_minimum_size = Vector2(180, 56)
			slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			slot_label.add_theme_font_size_override("font_size", 24)
			slot_label.text = "Slot %d" % (i + 1)
			row.add_child(slot_label)
			var nickname_edit := LineEdit.new()
			nickname_edit.custom_minimum_size = Vector2(760, 56)
			nickname_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nickname_edit.add_theme_font_size_override("font_size", 24)
			nickname_edit.text_changed.connect(_on_slot_nickname_changed.bind(i))
			row.add_child(nickname_edit)
			var type_option := OptionButton.new()
			type_option.custom_minimum_size = Vector2(300, 56)
			type_option.add_theme_font_size_override("font_size", 24)
			type_option.item_selected.connect(_on_slot_type_selected.bind(i))
			row.add_child(type_option)
			lobby_slots_vbox.add_child(row)
			lobby_slot_rows.append({
				"row": row,
				"nickname_edit": nickname_edit,
				"type_option": type_option,
				"actions": [],
			})
	for i in range(mini(MAX_LOBBY_SLOTS, lobby_slots.size())):
		refresh_lobby_slot_row(i)
	update_start_button_state()

func refresh_lobby_slot_row(index: int) -> void:
	if index >= lobby_slot_rows.size() or index >= lobby_slots.size():
		return
	var slot := lobby_slots[index]
	var row_refs: Dictionary = lobby_slot_rows[index]
	var nickname_edit := row_refs["nickname_edit"] as LineEdit
	var type_option := row_refs["type_option"] as OptionButton
	var owner_id := str(slot.get("owner_id", ""))
	var slot_type := str(slot.get("type", "open"))
	var nickname := str(slot.get("nickname", ""))
	var owned_by_local := !local_client_id.is_empty() and owner_id == local_client_id
	var host_local := !local_client_id.is_empty() and local_client_id == network_host_client_id
	var actions: Array[String] = []
	nickname_edit.text = nickname
	nickname_edit.editable = owned_by_local or (host_local and slot_type == "ai")
	nickname_edit.placeholder_text = "Nickname"
	type_option.clear()
	type_option.disabled = false
	if index == 0:
		type_option.add_item("Host")
		type_option.selected = 0
		type_option.disabled = true
	elif !owner_id.is_empty():
		type_option.add_item("You" if owned_by_local else "Taken")
		type_option.selected = 0
		type_option.disabled = true
	else:
		if host_local:
			type_option.add_item("Open")
			actions.append("open")
			type_option.add_item("AI")
			actions.append("ai")
			type_option.selected = 1 if slot_type == "ai" else 0
		else:
			if slot_type == "ai":
				type_option.add_item("AI")
				type_option.selected = 0
				type_option.disabled = true
			else:
				type_option.add_item("Open")
				actions.append("open")
				type_option.add_item("Join")
				actions.append("join")
				type_option.selected = 0
	row_refs["actions"] = actions

func update_lobby_subtitle() -> void:
	var active_slots := get_active_lobby_slots()
	var human_count := 0
	var ai_count := 0
	for slot in active_slots:
		if str(slot.get("type", "")) == "ai":
			ai_count += 1
		else:
			human_count += 1
	if !network_enabled:
		lobby_subtitle.text = "Connecting to the LAN session server..."
	elif ai_count == 0 and human_count > 1:
		lobby_subtitle.text = "Shared lobby connected. All human slots are PvP."
	else:
		lobby_subtitle.text = "Shared LAN lobby connected. Host can toggle open slots into AI fighters."

func update_start_button_state() -> void:
	var active_count := get_active_lobby_slots().size()
	if network_enabled:
		var is_host := local_client_id == network_host_client_id and !local_client_id.is_empty()
		start_match_button.disabled = !is_host or active_count < 2
		start_match_button.text = "Start Match (%d)" % active_count if is_host else "Waiting For Host"
	else:
		start_match_button.disabled = active_count < 2
		start_match_button.text = "Start Match (%d)" % active_count

func get_active_lobby_slots() -> Array[Dictionary]:
	var active_slots: Array[Dictionary] = []
	for slot in lobby_slots:
		if str(slot.get("type", "open")) != "open":
			active_slots.append(slot.duplicate(true))
	return active_slots

func get_local_slot_index() -> int:
	if local_client_id.is_empty():
		return -1
	for i in range(lobby_slots.size()):
		if str(lobby_slots[i].get("owner_id", "")) == local_client_id:
			return i
	return -1

func show_title_screen() -> void:
	get_tree().paused = false
	clear_world()
	game_phase = GamePhase.TITLE
	round_over = false
	console_open = false
	title_screen.visible = true
	lobby_screen.visible = false
	round_end_overlay.visible = false
	console_panel.visible = false
	set_mobile_controls_active(false)
	camera.global_position = arena_center

func show_lobby_screen() -> void:
	get_tree().paused = false
	clear_world()
	game_phase = GamePhase.LOBBY
	round_over = false
	console_open = false
	title_screen.visible = false
	lobby_screen.visible = true
	round_end_overlay.visible = false
	console_panel.visible = false
	set_mobile_controls_active(false)
	populate_lobby_ui()
	camera.global_position = arena_center

func clear_world() -> void:
	player_one = null
	orb_id_counter = 0
	crystal_id_counter = 0
	for node in [players_node, orbs_node, crystals_node, structures_node, minions_node]:
		for child in node.get_children():
			child.free()
	for child in get_children():
		if child.has_method("get_snapshot") and str(child.get("entity_id")).begins_with("pickup_"):
			child.free()

func _on_quick_play_pressed() -> void:
	local_quick_play = true
	network_round_host = false
	active_participants = [
		{"slot_index": 0, "nickname": "Player 1", "type": "human", "owner_id": local_client_id},
		{"slot_index": 1, "nickname": "AI 2", "type": "ai", "owner_id": null},
	]
	start_local_or_host_round()

func _on_open_lobby_pressed() -> void:
	show_lobby_screen()

func _on_quit_title_pressed() -> void:
	get_tree().quit()

func _on_back_to_title_pressed() -> void:
	show_title_screen()

func _on_start_match_pressed() -> void:
	if network_enabled:
		NetworkClient.send_message("start_match")
	else:
		local_quick_play = true
		active_participants = get_active_lobby_slots()
		start_local_or_host_round()

func _on_slot_nickname_changed(new_text: String, index: int) -> void:
	if index >= lobby_slots.size():
		return
	var slot := lobby_slots[index]
	var slot_type := str(slot.get("type", "open"))
	var owner_id := str(slot.get("owner_id", ""))
	if network_enabled:
		if owner_id == local_client_id and !new_text.strip_edges().is_empty():
			NetworkClient.send_message("set_nickname", {"nickname": new_text})
		elif local_client_id == network_host_client_id and slot_type == "ai":
			NetworkClient.send_message("set_ai_nickname", {"slot_index": index, "nickname": new_text})
	else:
		lobby_slots[index]["nickname"] = new_text

func _on_slot_type_selected(selected: int, index: int) -> void:
	if index >= lobby_slot_rows.size():
		return
	var actions: Array = lobby_slot_rows[index]["actions"]
	if selected < 0 or selected >= actions.size():
		return
	var action := str(actions[selected])
	if network_enabled:
		match action:
			"open":
				if local_client_id == network_host_client_id:
					NetworkClient.send_message("set_slot_type", {"slot_index": index, "slot_type": "open"})
			"ai":
				NetworkClient.send_message("set_slot_type", {"slot_index": index, "slot_type": "ai"})
			"join":
				NetworkClient.send_message("claim_slot", {"slot_index": index})

func start_network_round() -> void:
	local_quick_play = false
	start_local_or_host_round()

func start_local_or_host_round() -> void:
	get_tree().paused = false
	clear_world()
	round_over = false
	console_open = false
	return_to_lobby_requested = false
	rematch_votes.clear()
	game_phase = GamePhase.ROUND
	npc_attack_delay_remaining = NPC_ATTACK_DELAY
	remote_input_states.clear()
	snapshot_accumulator = 0.0
	input_accumulator = 0.0
	last_sent_move = Vector2.ZERO
	pending_dash_send = false
	console_panel.visible = false
	round_end_overlay.visible = false
	title_screen.visible = false
	lobby_screen.visible = false
	set_mobile_controls_active(should_show_mobile_controls() and (!get_local_controlled_participant().is_empty() or local_quick_play))
	if network_enabled and !network_round_host and !local_quick_play:
		spawn_proxy_players(active_participants)
	else:
		spawn_simulated_players(active_participants)
		spawn_castle_pads(active_participants)
		spawn_crystal_clusters()
		spawn_orbs()
	refresh_local_player_reference()
	update_camera()

func spawn_simulated_players(participants: Array[Dictionary]) -> void:
	for participant_index in range(participants.size()):
		var participant: Dictionary = participants[participant_index]
		var slot_index := int(participant.get("slot_index", 0))
		var position := get_spawn_position(participant_index, participants.size())
		var p = PLAYER_SCENE.instantiate()
		p.position = position
		p.player_id = slot_index + 1
		p.entity_id = "player_%d" % slot_index
		p.set_meta("nickname", str(participant.get("nickname", "Player %d" % (slot_index + 1))))
		p.set_meta("controller", str(participant.get("type", "ai")))
		p.set_meta("owner_id", str(participant.get("owner_id", "")))
		if p.has_method("set_facing_direction"):
			p.call("set_facing_direction", (arena_center - position).normalized())
		players_node.add_child(p)
		if str(participant.get("owner_id", "")) == local_client_id or (local_quick_play and slot_index == 0):
			player_one = p
	refresh_local_player_reference()

func spawn_proxy_players(participants: Array[Dictionary]) -> void:
	for participant_index in range(participants.size()):
		var participant: Dictionary = participants[participant_index]
		var slot_index := int(participant.get("slot_index", 0))
		var p = PLAYER_SCENE.instantiate()
		p.position = get_spawn_position(participant_index, participants.size())
		p.player_id = slot_index + 1
		p.entity_id = "player_%d" % slot_index
		p.set_network_proxy(true)
		p.set_meta("nickname", str(participant.get("nickname", "Player %d" % (slot_index + 1))))
		p.set_meta("controller", str(participant.get("type", "human")))
		p.set_meta("owner_id", str(participant.get("owner_id", "")))
		players_node.add_child(p)
		if str(participant.get("owner_id", "")) == local_client_id:
			player_one = p
	refresh_local_player_reference()
func spawn_orbs() -> void:
	if orbs_node.get_child_count() > 0:
		return
	spawn_orb_batch(100, 0)
	spawn_orb_batch(50, 1)
	spawn_orb_batch(50, 2)

func spawn_orb_batch(count: int, orb_type: int) -> void:
	for i in range(count):
		var orb = ORB_SCENE.instantiate()
		orb.entity_id = "orb_%d" % orb_id_counter
		orb_id_counter += 1
		orb.position = random_point_in_arena(180.0)
		orb.orb_type = orb_type
		orbs_node.add_child(orb)

func spawn_crystal_clusters() -> void:
	if crystals_node.get_child_count() > 0:
		return
	var positions = [
		arena_center + Vector2(-arena_radius * 0.46, -arena_radius * 0.1),
		arena_center + Vector2(arena_radius * 0.46, -arena_radius * 0.1)
	]
	var cluster_count: int = mini(active_participants.size(), positions.size())
	for i in range(cluster_count):
		var cluster = CRYSTAL_CLUSTER_SCENE.instantiate()
		cluster.entity_id = "crystal_%d" % crystal_id_counter
		crystal_id_counter += 1
		cluster.position = positions[i]
		cluster.scale = Vector2.ONE * CRYSTAL_CLUSTER_SCALE
		crystals_node.add_child(cluster)

func spawn_castle_pads(participants: Array[Dictionary]) -> void:
	if structures_node.get_child_count() > 0:
		return
	for participant_index in range(participants.size()):
		var participant: Dictionary = participants[participant_index]
		var slot_index := int(participant.get("slot_index", 0))
		var spawn_position := get_spawn_position(participant_index, participants.size())
		var to_center := (arena_center - spawn_position).normalized()
		var pad = CASTLE_PAD_SCENE.instantiate()
		pad.entity_id = "castle_pad_%d" % slot_index
		pad.owner_player_id = slot_index + 1
		pad.owner_owner_id = str(participant.get("owner_id", ""))
		pad.owner_nickname = str(participant.get("nickname", "Player %d" % (slot_index + 1)))
		pad.global_position = spawn_position + (to_center * 1800.0)
		structures_node.add_child(pad)

func handle_input(delta: float) -> void:
	if game_phase != GamePhase.ROUND:
		shift_was_pressed = false
		mobile_dash_requested = false
		return
	if round_over or console_open:
		for player in players_node.get_children():
			if is_instance_valid(player):
				player.set_input(Vector2.ZERO)
		shift_was_pressed = false
		mobile_dash_requested = false
		return
	var keyboard_input: Vector2 = Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
	var mobile_input := Vector2.ZERO
	if mobile_controls != null and mobile_controls.visible:
		mobile_input = mobile_controls.get_move_vector()
	var local_move := (keyboard_input + mobile_input).limit_length()
	var shift_pressed: bool = Input.is_key_pressed(KEY_SHIFT)
	var dash_pressed := (shift_pressed and !shift_was_pressed) or mobile_dash_requested
	if network_enabled and !network_round_host and !local_quick_play:
		input_accumulator += delta
		pending_dash_send = pending_dash_send or dash_pressed
		if input_accumulator >= INPUT_SEND_INTERVAL or local_move != last_sent_move or pending_dash_send:
			input_accumulator = 0.0
			last_sent_move = local_move
			NetworkClient.send_message("input_state", {
				"move": [local_move.x, local_move.y],
				"dash_pressed": pending_dash_send,
			})
			pending_dash_send = false
	else:
		for player in players_node.get_children():
			if !is_instance_valid(player):
				continue
			var controller := str(player.get_meta("controller", "ai"))
			var owner_id := str(player.get_meta("owner_id", ""))
			if local_quick_play and int(player.player_id) == 1:
				player.set_input(local_move)
				if dash_pressed:
					player.try_dash_attack()
			elif controller == "human" and owner_id == local_client_id:
				player.set_input(local_move)
				if dash_pressed:
					player.try_dash_attack()
			elif controller == "human" and owner_id != local_client_id and !owner_id.is_empty():
				var remote_state: Dictionary = remote_input_states.get(owner_id, {"move": [0.0, 0.0], "dash_pressed": false})
				var move_array = remote_state.get("move", [0.0, 0.0])
				if move_array is Array and move_array.size() >= 2:
					player.set_input(Vector2(float(move_array[0]), float(move_array[1])))
				else:
					player.set_input(Vector2.ZERO)
				if bool(remote_state.get("dash_pressed", false)):
					player.try_dash_attack()
					remote_state["dash_pressed"] = false
					remote_input_states[owner_id] = remote_state
			else:
				player.set_input(get_npc_input(player))
	shift_was_pressed = shift_pressed
	mobile_dash_requested = false

func get_npc_input(npc: Node2D) -> Vector2:
	if local_quick_play:
		return Vector2.ZERO
	if npc_attack_delay_remaining > 0.0:
		return Vector2.ZERO
	var target := get_nearest_opponent(npc)
	if target == null:
		return Vector2.ZERO
	return (target.global_position - npc.global_position).normalized()

func get_nearest_opponent(source: Node2D) -> Node2D:
	var best_target: Node2D = null
	var best_distance_sq := INF
	for candidate in players_node.get_children():
		var node := candidate as Node2D
		if node == null or node == source or !is_instance_valid(node):
			continue
		var distance_sq := source.global_position.distance_squared_to(node.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_target = node
	return best_target

func build_round_snapshot() -> Dictionary:
	return {
		"phase": "round_end" if round_over else "round",
		"winner_name": get_winner_name(),
		"players": collect_snapshots(players_node),
		"orbs": collect_snapshots(orbs_node),
		"crystals": collect_snapshots(crystals_node),
		"structures": collect_snapshots(structures_node),
		"minions": collect_snapshots(minions_node),
		"pickups": collect_pickup_snapshots(),
	}

func collect_snapshots(parent: Node) -> Array:
	var snapshots: Array = []
	for child in parent.get_children():
		if child.has_method("get_snapshot"):
			snapshots.append(child.call("get_snapshot"))
	return snapshots

func collect_pickup_snapshots() -> Array:
	var snapshots: Array = []
	for child in get_children():
		if child.has_method("get_snapshot"):
			var entity_id := str(child.get("entity_id"))
			if entity_id.begins_with("pickup_"):
				snapshots.append(child.call("get_snapshot"))
	return snapshots

func apply_round_snapshot(payload: Dictionary) -> void:
	sync_players_from_snapshot(payload.get("players", []))
	sync_entities_from_snapshot(orbs_node, ORB_SCENE, payload.get("orbs", []))
	sync_entities_from_snapshot(crystals_node, CRYSTAL_CLUSTER_SCENE, payload.get("crystals", []))
	sync_entities_from_snapshot(structures_node, CASTLE_PAD_SCENE, payload.get("structures", []))
	sync_entities_from_snapshot(minions_node, CASTLE_MINION_SCENE, payload.get("minions", []))
	sync_pickups_from_snapshot(payload.get("pickups", []))
	var phase := str(payload.get("phase", "round"))
	if phase == "round_end" and !round_over:
		show_round_end(payload)

func sync_players_from_snapshot(player_snapshots: Array) -> void:
	var existing := {}
	for child in players_node.get_children():
		existing[str(child.entity_id)] = child
	var keep_ids := {}
	for snapshot in player_snapshots:
		if snapshot is Dictionary:
			var entity_id := str(snapshot.get("entity_id", ""))
			if entity_id.is_empty():
				continue
			keep_ids[entity_id] = true
			var player = existing.get(entity_id, null)
			if player == null:
				player = PLAYER_SCENE.instantiate()
				player.set_network_proxy(true)
				players_node.add_child(player)
			player.apply_network_snapshot(snapshot)
			if str(snapshot.get("owner_id", "")) == local_client_id:
				player_one = player
	for key in existing.keys():
		if !keep_ids.has(key):
			existing[key].queue_free()
	refresh_local_player_reference()

func get_spawn_position(participant_index: int, participant_count: int) -> Vector2:
	var angle := (-PI * 0.5) + (TAU * float(participant_index) / float(max(participant_count, 1)))
	var spawn_radius := arena_radius * 0.68
	return arena_center + Vector2(cos(angle), sin(angle)) * spawn_radius

func sync_entities_from_snapshot(parent: Node, scene: PackedScene, snapshots: Array) -> void:
	var existing := {}
	for child in parent.get_children():
		existing[str(child.get("entity_id"))] = child
	var keep_ids := {}
	for snapshot in snapshots:
		if snapshot is Dictionary:
			var entity_id := str(snapshot.get("entity_id", ""))
			if entity_id.is_empty():
				continue
			keep_ids[entity_id] = true
			var node = existing.get(entity_id, null)
			if node == null:
				node = scene.instantiate()
				if node.has_method("set_network_proxy"):
					node.call("set_network_proxy", true)
				parent.add_child(node)
			if node.has_method("apply_network_snapshot"):
				node.call("apply_network_snapshot", snapshot)
	for key in existing.keys():
		if !keep_ids.has(key):
			existing[key].queue_free()

func sync_pickups_from_snapshot(snapshots: Array) -> void:
	var existing := {}
	for child in get_children():
		if child.has_method("get_snapshot"):
			var entity_id := str(child.get("entity_id"))
			if entity_id.begins_with("pickup_"):
				existing[entity_id] = child
	var keep_ids := {}
	for snapshot in snapshots:
		if snapshot is Dictionary:
			var entity_id := str(snapshot.get("entity_id", ""))
			if entity_id.is_empty():
				continue
			keep_ids[entity_id] = true
			var node = existing.get(entity_id, null)
			if node == null:
				node = GREEN_PICKUP_SCENE.instantiate()
				node.set_network_proxy(true)
				add_child(node)
			node.apply_network_snapshot(snapshot)
	for key in existing.keys():
		if !keep_ids.has(key):
			existing[key].queue_free()

func should_show_mobile_controls() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()

func refresh_local_player_reference() -> void:
	if local_quick_play:
		for child in players_node.get_children():
			if is_instance_valid(child) and int(child.player_id) == 1:
				player_one = child
				return

	if !local_client_id.is_empty():
		for child in players_node.get_children():
			if is_instance_valid(child) and str(child.get_meta("owner_id", "")) == local_client_id:
				player_one = child
				return

	if local_slot_index >= 0:
		var expected_entity_id := "player_%d" % local_slot_index
		for child in players_node.get_children():
			if !is_instance_valid(child):
				continue
			if str(child.get("entity_id")) == expected_entity_id or int(child.player_id) == local_slot_index + 1:
				player_one = child
				return

	player_one = null

func get_local_participant_slot_index() -> int:
	for participant in active_participants:
		if str(participant.get("owner_id", "")) == local_client_id:
			return int(participant.get("slot_index", -1))
	return local_slot_index

func set_mobile_controls_active(active: bool) -> void:
	if mobile_controls == null:
		return
	if mobile_controls.has_method("set_controls_active"):
		mobile_controls.call("set_controls_active", active)
	else:
		mobile_controls.visible = active

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

func get_winner_name() -> String:
	var surviving: Array[String] = []
	for candidate in players_node.get_children():
		if is_instance_valid(candidate):
			surviving.append(str(candidate.get_meta("nickname", "Player")))
	return surviving[0] if surviving.size() == 1 else ""

func end_round(winner: Node2D) -> void:
	round_over = true
	game_phase = GamePhase.ROUND_END
	console_open = false
	console_panel.visible = false
	set_mobile_controls_active(false)
	for player in players_node.get_children():
		if is_instance_valid(player):
			player.set_input(Vector2.ZERO)
	var round_result := {
		"winner_name": str(winner.get_meta("nickname", "Player")) if winner != null else "",
	}
	if network_enabled and network_round_host and !local_quick_play:
		NetworkClient.send_message("end_round", round_result)
	show_round_end(round_result)

func show_round_end(payload: Dictionary) -> void:
	var winner_name := str(payload.get("winner_name", ""))
	if !winner_name.is_empty():
		round_end_title.text = "%s Wins" % winner_name
		round_end_subtitle.text = "Run Again needs every player to agree. Return To Lobby is always available."
	else:
		round_end_title.text = "Round Over"
		round_end_subtitle.text = "Run Again needs every player to agree."
	round_end_overlay.visible = true

func _on_replay_pressed() -> void:
	if network_enabled and !local_quick_play:
		NetworkClient.send_message("run_again_vote")
		round_end_subtitle.text = "Run Again vote sent. Waiting for all players."
	else:
		get_tree().paused = false
		start_local_or_host_round()

func _on_quit_pressed() -> void:
	if network_enabled and !local_quick_play:
		NetworkClient.send_message("return_to_lobby")
	else:
		show_lobby_screen()

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
	if try_run_energy_console_command(command):
		return
	match command.to_lower():
		"help":
			append_console_log("Commands: help, clear, god, energy = 10")
		"clear":
			console_log.clear()
		"god":
			run_god_command()
		_:
			append_console_log("Unknown command.")

func try_run_energy_console_command(command: String) -> bool:
	var trimmed := command.strip_edges()
	var pieces := trimmed.split("=")
	if pieces.size() != 2:
		return false
	if pieces[0].strip_edges().to_lower() != "energy":
		return false
	var energy_text := pieces[1].strip_edges()
	if energy_text.is_empty() or !energy_text.is_valid_int():
		append_console_log("Use `energy = 10`.")
		return true
	var target_energy := clampi(int(energy_text), 0, 10)
	run_energy_console_command(target_energy)
	return true

func run_energy_console_command(target_energy: int) -> void:
	if network_enabled and !local_quick_play:
		NetworkClient.send_message("admin_set_energy", {"energy": target_energy})
		if network_round_host:
			apply_network_admin_set_energy({
				"client_id": local_client_id,
				"energy": target_energy,
			})
		else:
			append_console_log("Requested energy = %d" % target_energy)
		return
	apply_energy_to_local_player(target_energy)

func apply_network_admin_set_energy(payload: Dictionary) -> void:
	var client_id := str(payload.get("client_id", ""))
	var target_energy := clampi(int(payload.get("energy", 0)), 0, 10)
	var target_player := get_player_for_client_id(client_id)
	if target_player == null:
		append_console_log("No player found for energy command.")
		return
	if target_player.has_method("set_energy_amount"):
		target_player.call("set_energy_amount", target_energy)
		append_console_log("%s energy set to %d" % [str(target_player.get_meta("nickname", "Player")), target_energy])

func apply_energy_to_local_player(target_energy: int) -> void:
	if player_one == null or !is_instance_valid(player_one):
		append_console_log("No local player found.")
		return
	if player_one.has_method("set_energy_amount"):
		player_one.call("set_energy_amount", target_energy)
		append_console_log("Energy set to %d" % target_energy)

func get_player_for_client_id(client_id: String) -> Node:
	for candidate in players_node.get_children():
		if !is_instance_valid(candidate):
			continue
		if str(candidate.get_meta("owner_id", "")) == client_id:
			return candidate
	return null

func run_god_command() -> void:
	var source := player_one
	var target := get_first_opponent_player()
	if source == null or !is_instance_valid(source):
		append_console_log("No local player found.")
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

func random_point_in_arena(margin: float = 0.0) -> Vector2:
	var usable_radius: float = maxf(arena_radius - margin, 0.0)
	var angle: float = randf() * TAU
	var distance: float = sqrt(randf()) * usable_radius
	return arena_center + Vector2(cos(angle), sin(angle)) * distance

func get_arena_center() -> Vector2:
	return arena_center

func get_arena_radius() -> float:
	return arena_radius

func get_local_controlled_participant() -> Dictionary:
	for participant in active_participants:
		if str(participant.get("owner_id", "")) == local_client_id:
			return participant
	return {}
