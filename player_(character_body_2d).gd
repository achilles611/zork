extends CharacterBody2D

const GREEN_SATELLITE_SCENE = preload("res://GreenSatellite.tscn")
const TIP_SCRIPT = preload("res://tip.gd")

@export var move_speed: float = 1450.0
@export var player_id: int = 0

const BASE_MODEL_SCALE := 3.1
const MAX_ENERGY := 20
const MAX_LEGS := 12
const AUTO_SPIN_SPEED := 2.4
const DASH_ENERGY_COST := 3
const DASH_COOLDOWN := 0.45
const DASH_TIME := 0.1
const DASH_EASE_OUT_DISTANCE_MULTIPLIER := 0.92
const ARM_CLASH_DAMAGE := 20
const BODY_HIT_DAMAGE := 30
const CRYSTAL_DAMAGE := 10
const HIT_COOLDOWN := 0.16
const CLASH_COOLDOWN := 0.12
const KNOCKBACK_MODEL_RATIO := 0.2
const LABEL_MARGIN := 120.0
const DAMAGE_NUMBER_OFFSET := Vector2(0, -240)
const STATS_NORMAL_COLOR := Color.WHITE
const STATS_DAMAGE_COLOR := Color(1.0, 0.2, 0.2)
const STATS_DAMAGE_FLASH_TIME := 0.28
const BODY_COLOR := Color(1.0, 1.0, 1.0, 0.97)
const DAMAGE_SOUND_MIX_RATE := 22050.0
const DAMAGE_SOUND_DURATION := 0.28
const DAMAGE_SOUND_VOLUME_DB := -7.0
const BODY_HURT_SOUND_MIX_RATE := 22050.0
const BODY_HURT_SOUND_DURATION := 0.36
const BODY_HURT_SOUND_VOLUME_DB := -4.0
const PICKUP_SOUND_MIX_RATE := 22050.0
const PICKUP_SOUND_DURATION := 0.32
const PICKUP_SOUND_VOLUME_DB := -5.0
const ARM_HIT_SOUND_MIX_RATE := 22050.0
const ARM_HIT_SOUND_DURATION := 0.18
const ARM_HIT_SOUND_VOLUME_DB := -4.0
const ARM_BREAK_SOUND_MIX_RATE := 22050.0
const ARM_BREAK_SOUND_DURATION := 0.28
const ARM_BREAK_SOUND_VOLUME_DB := -2.0
const BODY_POINT_COUNT := 48
const LEG_LENGTH := 440.0
const LEG_BASE_HALF_ANGLE := 0.24
const ARM_MAX_HP := 40
const ARM_CRACK_HP_THRESHOLD := 20
const ARM_RADIUS := 40.0

var hp: int = 100
var energy: int = MAX_ENERGY
var leg_count: int = 1
var arm_hp: Array[int] = [ARM_MAX_HP]
var alive := true
var entity_id := ""
var network_proxy := false

var move_input: Vector2 = Vector2.ZERO
var recently_hit := {}
var recent_clashes := {}
var green_satellites: Array = []
var tip_nodes: Array[Area2D] = []
var visual_nodes: Array[Node] = []
var pending_crack_animation_indices: Array[int] = []
var stats_flash_tween: Tween = null
var dash_tween: Tween = null
var dash_cooldown_remaining := 0.0
var is_dashing := false
var damage_audio_player: AudioStreamPlayer = null
var hurt_audio_player: AudioStreamPlayer = null
var pickup_audio_player: AudioStreamPlayer = null
var arm_hit_audio_player: AudioStreamPlayer = null
var arm_break_audio_player: AudioStreamPlayer = null

@onready var label = $Label
@onready var body_collision_shape = $CollisionShape2D
@onready var body_hurtbox = $BodyHurtbox
@onready var tip = $Tip
@onready var tip_collision_shape = $Tip/CollisionShape2D

func _ready() -> void:
	add_to_group("combat_players")
	scale = Vector2.ONE * BASE_MODEL_SCALE
	label.top_level = true
	label.add_theme_color_override("font_color", STATS_NORMAL_COLOR)
	rebuild_model()
	setup_audio()
	update_label()
	update_label_position()

func _physics_process(delta: float) -> void:
	if !alive:
		return

	if network_proxy:
		update_label_position()
		return

	update_cooldowns(delta)

	if dash_cooldown_remaining > 0.0:
		dash_cooldown_remaining = maxf(dash_cooldown_remaining - delta, 0.0)

	if !is_dashing:
		rotation += AUTO_SPIN_SPEED * delta
		velocity = move_input.normalized() * move_speed
		move_and_slide()

	update_label_position()

func update_cooldowns(delta: float) -> void:
	for target in recently_hit.keys():
		recently_hit[target] -= delta
		if recently_hit[target] <= 0.0:
			recently_hit.erase(target)

	for target in recent_clashes.keys():
		recent_clashes[target] -= delta
		if recent_clashes[target] <= 0.0:
			recent_clashes.erase(target)

func set_input(dir: Vector2) -> void:
	move_input = dir

func set_facing_direction(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	rotation = direction.angle()

func set_rotation_input(_value: float) -> void:
	return

func set_network_proxy(enabled: bool) -> void:
	network_proxy = enabled
	if body_hurtbox != null:
		body_hurtbox.monitoring = !enabled
		body_hurtbox.monitorable = !enabled
		var hurtbox_shape := body_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurtbox_shape != null:
			hurtbox_shape.disabled = enabled
	for current_tip in tip_nodes:
		if current_tip == null:
			continue
		current_tip.monitoring = !enabled
		current_tip.monitorable = !enabled
		var shape := current_tip.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null:
			shape.disabled = enabled

func get_snapshot() -> Dictionary:
	return {
		"entity_id": entity_id,
		"player_id": int(player_id),
		"nickname": str(get_meta("nickname", "")),
		"controller": str(get_meta("controller", "")),
		"owner_id": str(get_meta("owner_id", "")),
		"position": [global_position.x, global_position.y],
		"rotation": rotation,
		"hp": hp,
		"energy": energy,
		"leg_count": leg_count,
		"arm_hp": arm_hp.duplicate(),
		"alive": alive,
	}

func apply_network_snapshot(data: Dictionary) -> void:
	var previous_arm_hp = arm_hp.duplicate()
	entity_id = str(data.get("entity_id", entity_id))
	player_id = int(data.get("player_id", player_id))
	set_meta("nickname", str(data.get("nickname", get_meta("nickname", ""))))
	set_meta("controller", str(data.get("controller", get_meta("controller", ""))))
	set_meta("owner_id", str(data.get("owner_id", get_meta("owner_id", ""))))
	var position_data = data.get("position", [global_position.x, global_position.y])
	if position_data is Array and position_data.size() >= 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	rotation = float(data.get("rotation", rotation))
	hp = int(data.get("hp", hp))
	energy = int(data.get("energy", energy))
	var next_arm_hp = data.get("arm_hp", arm_hp)
	if next_arm_hp is Array:
		arm_hp.clear()
		for value in next_arm_hp:
			arm_hp.append(int(value))
	var next_leg_count := int(data.get("leg_count", arm_hp.size()))
	if arm_hp.is_empty() and next_leg_count > 0:
		for _i in range(next_leg_count):
			arm_hp.append(ARM_MAX_HP)
	leg_count = arm_hp.size()
	if next_leg_count != leg_count:
		leg_count = next_leg_count
	if tip_nodes.size() != leg_count or previous_arm_hp != arm_hp:
		rebuild_model()
	alive = bool(data.get("alive", alive))
	sync_energy_satellites()
	update_label()
	update_label_position()

func try_dash_attack() -> bool:
	if !alive or is_dashing or dash_cooldown_remaining > 0.0:
		return false
	if energy < DASH_ENERGY_COST:
		return false

	energy -= DASH_ENERGY_COST
	sync_energy_satellites()
	update_label()

	var dash_direction := get_tip_direction()
	var dash_distance: float = get_tip_local_center().length() * scale.x * DASH_EASE_OUT_DISTANCE_MULTIPLIER
	var destination := global_position + dash_direction * dash_distance

	is_dashing = true
	dash_cooldown_remaining = DASH_COOLDOWN
	velocity = Vector2.ZERO

	if dash_tween != null:
		dash_tween.kill()

	dash_tween = create_tween()
	dash_tween.set_trans(Tween.TRANS_QUINT)
	dash_tween.set_ease(Tween.EASE_OUT)
	dash_tween.tween_property(self, "global_position", destination, DASH_TIME)
	dash_tween.tween_callback(_finish_dash)
	return true

func _finish_dash() -> void:
	is_dashing = false
	dash_tween = null

func gain_white_orb() -> void:
	gain_energy(1)

func gain_blue_orb() -> void:
	gain_energy(1)

func gain_red_orb() -> void:
	gain_energy(1)

func gain_energy(amount: int = 1) -> bool:
	var previous_energy := energy
	energy = mini(energy + amount, MAX_ENERGY)
	if energy == previous_energy:
		return false

	sync_energy_satellites()
	update_label()
	play_green_pickup_sound()
	return true

func set_energy_amount(value: int) -> void:
	energy = clampi(value, 0, MAX_ENERGY)
	sync_energy_satellites()
	update_label()

func deposit_all_energy() -> int:
	var deposited := energy
	if deposited <= 0:
		return 0
	energy = 0
	sync_energy_satellites()
	update_label()
	return deposited

func gain_leg(amount: int = 1) -> bool:
	var previous_leg_count := leg_count
	var target_leg_count := mini(leg_count + amount, MAX_LEGS)
	while arm_hp.size() < target_leg_count:
		arm_hp.append(ARM_MAX_HP)
	leg_count = arm_hp.size()
	if leg_count == previous_leg_count:
		return false
	rebuild_model()
	play_green_pickup_sound()
	return true

func add_green_satellite() -> bool:
	return gain_energy(1)

func can_hit(target: Node) -> bool:
	return alive and target != self and !recently_hit.has(target)

func is_arm_active(index: int) -> bool:
	return alive and index >= 0 and index < arm_hp.size()

func register_hit(target: Node) -> void:
	recently_hit[target] = HIT_COOLDOWN

func can_arm_clash(other: Node, my_arm_index: int, other_arm_index: int) -> bool:
	if !alive or other == self:
		return false
	return !recent_clashes.has(get_arm_clash_key(other, my_arm_index, other_arm_index))

func register_arm_clash(other: Node, my_arm_index: int, other_arm_index: int) -> void:
	recent_clashes[get_arm_clash_key(other, my_arm_index, other_arm_index)] = CLASH_COOLDOWN

func get_arm_clash_key(other: Node, my_arm_index: int, other_arm_index: int) -> String:
	var other_entity_id := ""
	if other != null and is_instance_valid(other):
		other_entity_id = str(other.get("entity_id"))
		if other_entity_id.is_empty():
			other_entity_id = str(other.get_instance_id())
	return "%s:%d:%d" % [other_entity_id, my_arm_index, other_arm_index]

func is_body_hurtbox(area: Area2D) -> bool:
	return area == body_hurtbox

func get_tip_direction() -> Vector2:
	var direction: Vector2 = (get_tip_global_position() - global_position).normalized()
	if direction == Vector2.ZERO:
		return Vector2.RIGHT.rotated(rotation)
	return direction

func get_tip_global_position() -> Vector2:
	var primary_shape := get_primary_tip_collision_shape()
	if primary_shape == null:
		return global_position
	return to_global(primary_shape.position)

func get_tip_local_center() -> Vector2:
	if leg_count <= 0:
		return Vector2(get_body_radius(), 0.0)
	return get_leg_tip_local_center(0)

func get_primary_tip_collision_shape() -> CollisionShape2D:
	if tip_nodes.is_empty():
		return tip_collision_shape
	return tip_nodes[0].get_node_or_null("CollisionShape2D") as CollisionShape2D

func deal_tip_damage(other: Node) -> void:
	if !alive or other == null or !is_instance_valid(other):
		return
	if !other.alive or !can_hit(other):
		return

	register_hit(other)
	if other.has_method("take_body_hit"):
		other.call("take_body_hit", BODY_HIT_DAMAGE, self, get_tip_global_position())
	elif other.has_method("take_damage"):
		other.call("take_damage", BODY_HIT_DAMAGE)

	var push_direction_to_other: Vector2 = (other.global_position - global_position).normalized()
	if push_direction_to_other == Vector2.ZERO:
		push_direction_to_other = get_tip_direction()
	var knockback_distance := get_combat_knockback_distance()
	if other.has_method("apply_knockback"):
		other.call("apply_knockback", push_direction_to_other, knockback_distance)
	apply_knockback(-push_direction_to_other, knockback_distance * 0.65)

func handle_arm_clash(other: Node, my_arm_index: int, other_arm_index: int) -> void:
	if !alive or other == null or !is_instance_valid(other):
		return
	if !other.alive:
		return
	if my_arm_index < 0 or my_arm_index >= arm_hp.size():
		return
	if other_arm_index < 0:
		return
	if int(player_id) > int(other.player_id):
		return
	if !can_arm_clash(other, my_arm_index, other_arm_index):
		return
	if other.has_method("can_arm_clash") and !bool(other.call("can_arm_clash", self, other_arm_index, my_arm_index)):
		return

	register_arm_clash(other, my_arm_index, other_arm_index)
	if other.has_method("register_arm_clash"):
		other.call("register_arm_clash", self, other_arm_index, my_arm_index)
	damage_arm(my_arm_index, ARM_CLASH_DAMAGE)
	if other.has_method("damage_arm"):
		other.call("damage_arm", other_arm_index, ARM_CLASH_DAMAGE)

	var separation: Vector2 = (global_position - other.global_position).normalized()
	if separation == Vector2.ZERO:
		separation = Vector2.RIGHT

	var knockback_distance := get_combat_knockback_distance()
	apply_knockback(separation, knockback_distance)
	if other.has_method("apply_knockback"):
		other.call("apply_knockback", -separation, knockback_distance)
	play_arm_hit_sound()

func damage_arm(index: int, amount: int) -> void:
	if index < 0 or index >= arm_hp.size():
		return
	var previous_hp := arm_hp[index]
	arm_hp[index] = max(arm_hp[index] - amount, 0)
	if arm_hp[index] <= 0:
		sever_arm(index)
		return
	if previous_hp > ARM_CRACK_HP_THRESHOLD and arm_hp[index] <= ARM_CRACK_HP_THRESHOLD:
		pending_crack_animation_indices.append(index)
	rebuild_model()
	play_arm_hit_sound()

func damage_nearest_arm(amount: int, source_position: Vector2) -> void:
	if arm_hp.is_empty():
		take_damage(amount)
		return
	var best_index := 0
	var best_distance_sq := INF
	for i in range(arm_hp.size()):
		var arm_tip_position := to_global(get_leg_tip_local_center(i))
		var distance_sq := arm_tip_position.distance_squared_to(source_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = i
	damage_arm(best_index, amount)

func sever_nearest_arm(source_position: Vector2) -> void:
	if arm_hp.is_empty():
		kill_instantly()
		return
	var best_index := 0
	var best_distance_sq := INF
	for i in range(arm_hp.size()):
		var arm_tip_position := to_global(get_leg_tip_local_center(i))
		var distance_sq := arm_tip_position.distance_squared_to(source_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = i
	sever_arm(best_index)

func sever_arm(index: int) -> void:
	if index < 0 or index >= arm_hp.size():
		return
	var tip_world_position := to_global(get_leg_tip_local_center(index))
	spawn_arm_explosion(tip_world_position)
	play_arm_break_sound()
	arm_hp.remove_at(index)
	leg_count = arm_hp.size()
	if leg_count <= 0:
		kill_instantly()
		return
	rebuild_model()

func apply_knockback(direction: Vector2, distance: float = -1.0) -> void:
	if distance < 0.0:
		distance = get_combat_knockback_distance()
	if direction == Vector2.ZERO:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", global_position + direction.normalized() * distance, 0.16)

func hit_by_player(player: Node2D) -> void:
	if !alive or player == null or !is_instance_valid(player):
		return
	if player.has_method("get_team_id") and int(player.call("get_team_id")) == player_id:
		return
	if recently_hit.has(player):
		return

	recently_hit[player] = HIT_COOLDOWN
	play_arm_hit_sound()

func take_body_hit(amount: int, attacker: Node2D = null, source_position: Vector2 = Vector2.ZERO) -> void:
	if !alive:
		return
	if source_position == Vector2.ZERO:
		source_position = global_position
	play_hurt_sound()
	take_damage(amount, false)
	if !alive:
		return
	sever_nearest_arm(source_position)
	if !alive:
		return
	var push_direction := (global_position - source_position).normalized()
	if push_direction == Vector2.ZERO:
		push_direction = Vector2.RIGHT.rotated(rotation)
	var knockback_distance := get_combat_knockback_distance()
	apply_knockback(push_direction, knockback_distance)
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("apply_knockback"):
		attacker.call("apply_knockback", -push_direction, knockback_distance * 0.65)

func get_attack_power() -> int:
	return CRYSTAL_DAMAGE

func get_team_id() -> int:
	return player_id

func is_attackable() -> bool:
	return alive

func get_camera_zoom_factor() -> float:
	return 1.0

func get_green_satellite_count() -> int:
	cleanup_green_satellites()
	return green_satellites.size()

func get_green_satellite_index(satellite: Node) -> int:
	cleanup_green_satellites()
	return green_satellites.find(satellite)

func sync_energy_satellites() -> void:
	cleanup_green_satellites()
	if get_tree().current_scene == null:
		return

	while green_satellites.size() < energy:
		var satellite = GREEN_SATELLITE_SCENE.instantiate()
		satellite.owner_player = self
		get_tree().current_scene.add_child(satellite)
		green_satellites.append(satellite)

	while green_satellites.size() > energy:
		var satellite_to_remove = green_satellites.pop_back()
		if is_instance_valid(satellite_to_remove):
			satellite_to_remove.queue_free()

func cleanup_green_satellites() -> void:
	for i in range(green_satellites.size() - 1, -1, -1):
		if !is_instance_valid(green_satellites[i]):
			green_satellites.remove_at(i)

func clear_green_satellites() -> void:
	for satellite in green_satellites:
		if is_instance_valid(satellite):
			satellite.queue_free()
	green_satellites.clear()

func take_damage(amount: int, play_sound: bool = true) -> void:
	if !alive:
		return

	hp -= amount
	if play_sound:
		play_damage_impact_sound()
	flash_stats_damage(amount)
	show_damage_number(amount)

	if hp <= 0:
		kill_instantly()

func flash_stats_damage(amount: int) -> void:
	if stats_flash_tween != null:
		stats_flash_tween.kill()

	label.add_theme_color_override("font_color", STATS_DAMAGE_COLOR)
	label.text = "HP -%d\nEN %d" % [amount, energy]

	stats_flash_tween = create_tween()
	stats_flash_tween.tween_interval(STATS_DAMAGE_FLASH_TIME)
	stats_flash_tween.tween_callback(restore_stats_label)

func restore_stats_label() -> void:
	label.add_theme_color_override("font_color", STATS_NORMAL_COLOR)
	update_label()
	stats_flash_tween = null

func show_damage_number(amount: int) -> void:
	var damage_label := Label.new()
	damage_label.top_level = true
	damage_label.z_index = 100
	damage_label.text = "-%d" % amount
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	damage_label.add_theme_font_size_override("font_size", 52)
	damage_label.global_position = global_position + (DAMAGE_NUMBER_OFFSET * scale.x)
	get_tree().current_scene.add_child(damage_label)
	damage_label.global_position -= damage_label.size * 0.5

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "global_position", damage_label.global_position + Vector2(0, -90), 0.5)
	tween.tween_property(damage_label, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(damage_label.queue_free)

func update_label() -> void:
	label.text = "HP %d\nEN %d" % [hp, energy]

func update_label_position() -> void:
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := Vector2.ONE
	if camera != null:
		camera_zoom = camera.zoom

	label.scale = Vector2.ONE / camera_zoom

	var body_radius := get_body_radius() * scale.y
	var label_size: Vector2 = label.size * label.scale
	var world_offset := Vector2(0.0, -(body_radius + (LABEL_MARGIN * scale.y)))
	label.global_position = global_position + world_offset - Vector2(label_size.x * 0.5, label_size.y)

func get_body_radius() -> float:
	var circle_shape := body_collision_shape.shape as CircleShape2D
	if circle_shape == null:
		return 180.0
	return circle_shape.radius

func rebuild_model() -> void:
	leg_count = arm_hp.size()
	clear_visual_nodes()
	rebuild_tip_nodes()
	create_body_visual()
	create_leg_visuals()
	animate_pending_cracks()
	set_network_proxy(network_proxy)

func clear_visual_nodes() -> void:
	for node in visual_nodes:
		if is_instance_valid(node):
			node.queue_free()
	visual_nodes.clear()

func rebuild_tip_nodes() -> void:
	for child in get_children():
		if child is Area2D and child != tip and str(child.name).begins_with("ExtraTip"):
			child.queue_free()

	tip_nodes.clear()
	if leg_count <= 0:
		tip.position = Vector2.ZERO
		tip.monitoring = false
		tip.monitorable = false
		tip_collision_shape.disabled = true
		return

	tip_nodes.append(tip)

	for i in range(1, leg_count):
		var extra_tip := Area2D.new()
		extra_tip.name = "ExtraTip%d" % i
		extra_tip.set_script(TIP_SCRIPT)
		var shape := CollisionShape2D.new()
		shape.shape = tip_collision_shape.shape.duplicate()
		extra_tip.add_child(shape)
		add_child(extra_tip)
		tip_nodes.append(extra_tip)

	for i in range(tip_nodes.size()):
		configure_tip_node(tip_nodes[i], i)

func configure_tip_node(tip_node: Area2D, index: int) -> void:
	tip_node.position = get_leg_tip_local_center(index)
	tip_node.monitoring = !network_proxy
	tip_node.monitorable = !network_proxy
	tip_node.set("owner_player", self)
	tip_node.set("arm_index", index)
	if tip_node.has_method("_on_area_entered"):
		var collision_handler := Callable(tip_node, "_on_area_entered")
		if !tip_node.area_entered.is_connected(collision_handler):
			tip_node.area_entered.connect(collision_handler)
	var shape := tip_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		return
	var circle := CircleShape2D.new()
	circle.radius = ARM_RADIUS
	shape.shape = circle
	shape.position = Vector2.ZERO
	shape.rotation = 0.0
	shape.disabled = network_proxy or !is_arm_active(index)

func create_body_visual() -> void:
	var radius := get_body_radius()
	var body_fill := Polygon2D.new()
	body_fill.polygon = make_circle_points(radius, BODY_POINT_COUNT)
	body_fill.color = BODY_COLOR
	body_fill.z_index = 2
	add_child(body_fill)
	visual_nodes.append(body_fill)

	var body_outline := Line2D.new()
	body_outline.width = 18.0
	body_outline.default_color = BODY_COLOR
	body_outline.antialiased = true
	body_outline.closed = true
	body_outline.z_index = 3
	body_outline.points = make_circle_points(radius, BODY_POINT_COUNT)
	add_child(body_outline)
	visual_nodes.append(body_outline)

func create_leg_visuals() -> void:
	for i in range(leg_count):
		var polygon := Polygon2D.new()
		polygon.polygon = build_leg_polygon(i)
		polygon.color = BODY_COLOR
		polygon.z_index = 2
		polygon.set_meta("arm_index", i)
		add_child(polygon)
		visual_nodes.append(polygon)

		var outline := Line2D.new()
		outline.width = 18.0
		outline.default_color = BODY_COLOR
		outline.antialiased = true
		outline.closed = true
		outline.z_index = 3
		outline.points = polygon.polygon
		outline.set_meta("arm_index", i)
		add_child(outline)
		visual_nodes.append(outline)

		if arm_hp[i] <= ARM_CRACK_HP_THRESHOLD:
			var crack := Line2D.new()
			crack.width = 10.0
			crack.default_color = Color(0.24, 0.02, 0.02, 0.92)
			crack.antialiased = true
			crack.z_index = 4
			crack.points = build_crack_points(i)
			crack.set_meta("arm_index", i)
			crack.set_meta("is_arm_crack", true)
			add_child(crack)
			visual_nodes.append(crack)

func build_leg_polygon(index: int) -> PackedVector2Array:
	var radius := get_body_radius()
	var angle := get_leg_angle(index)
	var base_left := Vector2.RIGHT.rotated(angle - LEG_BASE_HALF_ANGLE) * radius
	var base_right := Vector2.RIGHT.rotated(angle + LEG_BASE_HALF_ANGLE) * radius
	var tip_point := Vector2.RIGHT.rotated(angle) * (radius + LEG_LENGTH)
	return PackedVector2Array([base_left, tip_point, base_right])

func get_leg_tip_local_center(index: int) -> Vector2:
	var radius := get_body_radius()
	var angle := get_leg_angle(index)
	return Vector2.RIGHT.rotated(angle) * (radius + LEG_LENGTH)

func get_leg_hitbox_center(index: int, hitbox_height: float = LEG_LENGTH) -> Vector2:
	var radius := get_body_radius()
	var angle := get_leg_angle(index)
	return Vector2.RIGHT.rotated(angle) * (radius + hitbox_height * 0.5)

func get_leg_angle(index: int) -> float:
	return TAU * float(index) / float(max(leg_count, 1))

func build_crack_points(index: int) -> PackedVector2Array:
	var angle := get_leg_angle(index)
	var direction := Vector2.RIGHT.rotated(angle)
	var normal := Vector2(-direction.y, direction.x)
	var radius := get_body_radius()
	var points := PackedVector2Array()
	points.append(direction * (radius + 28.0))
	points.append(direction * (radius + LEG_LENGTH * 0.22) + normal * 16.0)
	points.append(direction * (radius + LEG_LENGTH * 0.48) - normal * 14.0)
	points.append(direction * (radius + LEG_LENGTH * 0.74) + normal * 12.0)
	points.append(direction * (radius + LEG_LENGTH * 0.94))
	return points

func animate_pending_cracks() -> void:
	if pending_crack_animation_indices.is_empty():
		return
	var pending_lookup := {}
	for index in pending_crack_animation_indices:
		pending_lookup[index] = true
	pending_crack_animation_indices.clear()
	for node in visual_nodes:
		if !(node is Line2D):
			continue
		if !bool(node.get_meta("is_arm_crack", false)):
			continue
		var arm_index := int(node.get_meta("arm_index", -1))
		if !pending_lookup.has(arm_index):
			continue
		node.modulate.a = 0.0
		node.scale = Vector2.ONE * 0.7
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(node, "modulate:a", 1.0, 0.14)
		tween.tween_property(node, "scale", Vector2.ONE, 0.16)

func spawn_arm_explosion(world_position: Vector2) -> void:
	if get_tree().current_scene == null:
		return
	for i in range(5):
		var shard := Polygon2D.new()
		shard.top_level = true
		shard.z_index = 25
		shard.polygon = PackedVector2Array([
			Vector2(-12, -8),
			Vector2(14, 0),
			Vector2(-10, 8),
		])
		shard.color = Color(0.95, 0.95, 0.98, 0.96)
		shard.global_position = world_position
		shard.rotation = randf() * TAU
		get_tree().current_scene.add_child(shard)
		var direction := Vector2.RIGHT.rotated((TAU * float(i) / 5.0) + randf_range(-0.22, 0.22))
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "global_position", world_position + direction * randf_range(100.0, 170.0), 0.26)
		tween.tween_property(shard, "rotation", shard.rotation + randf_range(-1.4, 1.4), 0.26)
		tween.tween_property(shard, "modulate:a", 0.0, 0.26)
		tween.chain().tween_callback(shard.queue_free)

func get_combat_knockback_distance() -> float:
	var model_radius := get_body_radius() + LEG_LENGTH
	return model_radius * scale.x * KNOCKBACK_MODEL_RATIO

func make_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func setup_audio() -> void:
	damage_audio_player = AudioStreamPlayer.new()
	damage_audio_player.volume_db = DAMAGE_SOUND_VOLUME_DB
	damage_audio_player.stream = build_damage_stream()
	add_child(damage_audio_player)

	hurt_audio_player = AudioStreamPlayer.new()
	hurt_audio_player.volume_db = BODY_HURT_SOUND_VOLUME_DB
	hurt_audio_player.stream = build_hurt_stream()
	add_child(hurt_audio_player)

	pickup_audio_player = AudioStreamPlayer.new()
	pickup_audio_player.volume_db = PICKUP_SOUND_VOLUME_DB
	pickup_audio_player.stream = build_pickup_stream()
	add_child(pickup_audio_player)

	arm_hit_audio_player = AudioStreamPlayer.new()
	arm_hit_audio_player.volume_db = ARM_HIT_SOUND_VOLUME_DB
	arm_hit_audio_player.stream = build_arm_hit_stream()
	add_child(arm_hit_audio_player)

	arm_break_audio_player = AudioStreamPlayer.new()
	arm_break_audio_player.volume_db = ARM_BREAK_SOUND_VOLUME_DB
	arm_break_audio_player.stream = build_arm_break_stream()
	add_child(arm_break_audio_player)

func play_damage_impact_sound() -> void:
	if damage_audio_player != null:
		damage_audio_player.play()

func play_green_pickup_sound() -> void:
	if pickup_audio_player != null:
		pickup_audio_player.play()

func play_hurt_sound() -> void:
	if hurt_audio_player != null:
		hurt_audio_player.play()

func play_arm_hit_sound() -> void:
	if arm_hit_audio_player != null:
		arm_hit_audio_player.play()

func play_arm_break_sound() -> void:
	if arm_break_audio_player != null:
		arm_break_audio_player.play()

func build_damage_stream() -> AudioStreamWAV:
	var frame_count: int = int(DAMAGE_SOUND_MIX_RATE * DAMAGE_SOUND_DURATION)
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for i in range(frame_count):
		var t: float = float(i) / DAMAGE_SOUND_MIX_RATE
		var decay: float = exp(-7.5 * t)
		var low_sweep: float = 180.0 - (90.0 * (t / DAMAGE_SOUND_DURATION))
		var bass: float = sin(TAU * low_sweep * t) * 0.28 * decay
		var crunch: float = sin(TAU * 78.0 * t) * 0.16 * decay
		var grit: float = (randf() * 2.0 - 1.0) * 0.08 * decay
		var sample: float = clampf(bass + crunch + grit, -1.0, 1.0)
		buffer.put_16(int(round(sample * 32767.0)))
	return make_wav_stream(buffer, DAMAGE_SOUND_MIX_RATE)

func build_pickup_stream() -> AudioStreamWAV:
	var frame_count: int = int(PICKUP_SOUND_MIX_RATE * PICKUP_SOUND_DURATION)
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for i in range(frame_count):
		var t: float = float(i) / PICKUP_SOUND_MIX_RATE
		var decay: float = exp(-7.0 * t)
		var tone_a: float = sin(TAU * 880.0 * t) * 0.22 * decay
		var tone_b: float = sin(TAU * 1320.0 * t) * 0.15 * decay
		var tone_c: float = sin(TAU * 1760.0 * t) * 0.08 * decay
		var sample: float = clampf(tone_a + tone_b + tone_c, -1.0, 1.0)
		buffer.put_16(int(round(sample * 32767.0)))
	return make_wav_stream(buffer, PICKUP_SOUND_MIX_RATE)

func build_hurt_stream() -> AudioStreamWAV:
	var frame_count: int = int(BODY_HURT_SOUND_MIX_RATE * BODY_HURT_SOUND_DURATION)
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for i in range(frame_count):
		var t: float = float(i) / BODY_HURT_SOUND_MIX_RATE
		var decay: float = exp(-4.0 * t)
		var formant_a: float = sin(TAU * 180.0 * t) * 0.2 * decay
		var formant_b: float = sin(TAU * 260.0 * t) * 0.18 * decay
		var throat: float = sin(TAU * 92.0 * t) * 0.12 * decay
		var wobble: float = sin(TAU * 14.0 * t) * 0.06 * decay
		var sample: float = clampf(formant_a + formant_b + throat + wobble, -1.0, 1.0)
		buffer.put_16(int(round(sample * 32767.0)))
	return make_wav_stream(buffer, BODY_HURT_SOUND_MIX_RATE)

func build_arm_hit_stream() -> AudioStreamWAV:
	var frame_count: int = int(ARM_HIT_SOUND_MIX_RATE * ARM_HIT_SOUND_DURATION)
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for i in range(frame_count):
		var t: float = float(i) / ARM_HIT_SOUND_MIX_RATE
		var decay: float = exp(-13.0 * t)
		var ping_a: float = sin(TAU * 1680.0 * t) * 0.34 * decay
		var ping_b: float = sin(TAU * 2520.0 * t) * 0.2 * decay
		var metal: float = sin(TAU * 980.0 * t) * 0.12 * decay
		var sample: float = clampf(ping_a + ping_b + metal, -1.0, 1.0)
		buffer.put_16(int(round(sample * 32767.0)))
	return make_wav_stream(buffer, ARM_HIT_SOUND_MIX_RATE)

func build_arm_break_stream() -> AudioStreamWAV:
	var frame_count: int = int(ARM_BREAK_SOUND_MIX_RATE * ARM_BREAK_SOUND_DURATION)
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for i in range(frame_count):
		var t: float = float(i) / ARM_BREAK_SOUND_MIX_RATE
		var decay: float = exp(-7.0 * t)
		var bang: float = sin(TAU * 220.0 * t) * 0.18 * decay
		var ping: float = sin(TAU * 1420.0 * t) * 0.24 * decay
		var shards: float = (randf() * 2.0 - 1.0) * 0.1 * decay
		var sample: float = clampf(bang + ping + shards, -1.0, 1.0)
		buffer.put_16(int(round(sample * 32767.0)))
	return make_wav_stream(buffer, ARM_BREAK_SOUND_MIX_RATE)

func make_wav_stream(buffer: StreamPeerBuffer, mix_rate: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(mix_rate)
	stream.stereo = false
	stream.data = buffer.data_array
	return stream

func kill_instantly() -> void:
	if !alive:
		return

	alive = false
	hp = 0
	clear_green_satellites()
	if stats_flash_tween != null:
		stats_flash_tween.kill()
	if dash_tween != null:
		dash_tween.kill()
	label.queue_free()
	queue_free()
