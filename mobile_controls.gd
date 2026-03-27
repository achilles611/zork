extends Control

signal fire_requested

const JOYSTICK_RADIUS := 128.0
const MOUSE_TOUCH_ID := -999
const JOYSTICK_MARGIN := 56.0
const BUTTON_GROUP_MARGIN_X := 40.0
const BUTTON_GROUP_MARGIN_Y := 118.0
const BUTTON_GROUP_SIZE := Vector2(420.0, 500.0)

var move_vector: Vector2 = Vector2.ZERO
var burn_active := false
var joystick_touch_id := -1
var burn_touch_id := -1

@onready var joystick_area = $JoystickArea
@onready var joystick_base = $JoystickArea/JoystickBase
@onready var joystick_knob = $JoystickArea/JoystickBase/JoystickKnob
@onready var burn_button = $Buttons/BurnButton
@onready var fire_button = $Buttons/FireButton

func _ready() -> void:
	set_process_input(true)
	get_viewport().size_changed.connect(_layout_controls)
	burn_button.button_down.connect(_on_burn_button_down)
	burn_button.button_up.connect(_on_burn_button_up)
	burn_button.mouse_exited.connect(_on_burn_button_mouse_exited)
	fire_button.pressed.connect(_on_fire_button_pressed)
	_layout_controls()
	reset_joystick()

func get_move_vector() -> Vector2:
	return move_vector

func is_burn_active() -> bool:
	return burn_active

func _on_burn_button_down() -> void:
	burn_active = true

func _on_burn_button_up() -> void:
	burn_active = false

func _on_burn_button_mouse_exited() -> void:
	if !Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		burn_active = false

func _on_fire_button_pressed() -> void:
	fire_requested.emit()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if joystick_touch_id == -1 and is_inside_joystick_activation_area(event.position):
				joystick_touch_id = event.index
				update_joystick(event.position)
				get_viewport().set_input_as_handled()
			elif burn_touch_id == -1 and burn_button.get_global_rect().has_point(event.position):
				burn_touch_id = event.index
				burn_active = true
				get_viewport().set_input_as_handled()
			elif fire_button.get_global_rect().has_point(event.position):
				fire_requested.emit()
				get_viewport().set_input_as_handled()
		else:
			if event.index == joystick_touch_id:
				reset_joystick()
				get_viewport().set_input_as_handled()
			if event.index == burn_touch_id:
				burn_touch_id = -1
				burn_active = false
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == joystick_touch_id:
			update_joystick(event.position)
			get_viewport().set_input_as_handled()
		elif event.index == burn_touch_id:
			burn_active = burn_button.get_global_rect().has_point(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and is_inside_joystick_activation_area(event.position):
			joystick_touch_id = MOUSE_TOUCH_ID
			update_joystick(event.position)
		elif !event.pressed and joystick_touch_id == MOUSE_TOUCH_ID:
			reset_joystick()
	elif event is InputEventMouseMotion and joystick_touch_id == MOUSE_TOUCH_ID and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		update_joystick(event.position)

func _layout_controls() -> void:
	var viewport_size := get_viewport_rect().size
	joystick_area.position = Vector2(JOYSTICK_MARGIN, viewport_size.y - joystick_area.size.y - JOYSTICK_MARGIN)
	$Buttons.position = viewport_size - BUTTON_GROUP_SIZE - Vector2(BUTTON_GROUP_MARGIN_X, BUTTON_GROUP_MARGIN_Y)

func is_inside_joystick_activation_area(global_position: Vector2) -> bool:
	if joystick_area.get_global_rect().has_point(global_position) or joystick_base.get_global_rect().has_point(global_position):
		return true

	var viewport_size := get_viewport_rect().size
	var left_control_zone := Rect2(
		Vector2(0.0, viewport_size.y * 0.45),
		Vector2(viewport_size.x * 0.5, viewport_size.y * 0.55)
	)
	return left_control_zone.has_point(global_position)

func update_joystick(global_position: Vector2) -> void:
	var center := get_joystick_center()
	var offset := global_position - center
	if offset.length() > JOYSTICK_RADIUS:
		offset = offset.normalized() * JOYSTICK_RADIUS

	move_vector = offset / JOYSTICK_RADIUS
	joystick_knob.position = (joystick_base.size - joystick_knob.size) * 0.5 + offset

func reset_joystick() -> void:
	joystick_touch_id = -1
	move_vector = Vector2.ZERO
	joystick_knob.position = (joystick_base.size - joystick_knob.size) * 0.5

func get_joystick_center() -> Vector2:
	return joystick_base.global_position + (joystick_base.size * 0.5)
