extends Control

signal fire_requested

const JOYSTICK_RADIUS := 110.0
const MOUSE_TOUCH_ID := -999

var move_vector: Vector2 = Vector2.ZERO
var burn_active := false
var joystick_touch_id := -1

@onready var joystick_area = $JoystickArea
@onready var joystick_base = $JoystickArea/JoystickBase
@onready var joystick_knob = $JoystickArea/JoystickBase/JoystickKnob
@onready var burn_button = $Buttons/BurnButton
@onready var fire_button = $Buttons/FireButton

func _ready() -> void:
	joystick_area.gui_input.connect(_on_joystick_gui_input)
	burn_button.button_down.connect(_on_burn_button_down)
	burn_button.button_up.connect(_on_burn_button_up)
	burn_button.mouse_exited.connect(_on_burn_button_mouse_exited)
	fire_button.pressed.connect(_on_fire_button_pressed)
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

func _on_joystick_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and joystick_touch_id == -1 and joystick_area.get_global_rect().has_point(event.position):
			joystick_touch_id = event.index
			update_joystick(event.position)
		elif !event.pressed and event.index == joystick_touch_id:
			reset_joystick()
	elif event is InputEventScreenDrag and event.index == joystick_touch_id:
		update_joystick(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and joystick_area.get_global_rect().has_point(event.position):
			joystick_touch_id = MOUSE_TOUCH_ID
			update_joystick(event.position)
		elif !event.pressed and joystick_touch_id == MOUSE_TOUCH_ID:
			reset_joystick()
	elif event is InputEventMouseMotion and joystick_touch_id == MOUSE_TOUCH_ID and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		update_joystick(event.position)

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
