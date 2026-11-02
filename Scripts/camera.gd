extends Camera2D
## One finger pans (when pan is enabled); two fingers pinch to zoom.
## On the laptop, the mouse drags to pan and the wheel zooms.

const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const WHEEL_STEP := 1.1

@export var grid: Node2D  # set in the Inspector

var pan_enabled := true  # the dig toggle will switch this off later
var touches: Dictionary = {}  # finger index -> screen position


func _ready() -> void:
	var world: Rect2 = grid.get_world_rect()
	limit_left = int(world.position.x)
	limit_top = int(world.position.y)
	limit_right = int(world.end.x)
	limit_bottom = int(world.end.y)
	position = world.get_center()  # start centered

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		# A finger went down or lifted: track which fingers are on screen.
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)

	elif event is InputEventScreenDrag:
		if touches.size() == 2:
			_pinch(event)
		else:
			if touches.size() == 1 and pan_enabled:
				position -= event.relative / zoom
			touches[event.index] = event.position

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom_level(zoom.x * WHEEL_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom_level(zoom.x / WHEEL_STEP)


func _pinch(event: InputEventScreenDrag) -> void:
	# Compare the gap between the two fingers before and after this move.
	var before: Array = touches.values()
	var old_gap: float = before[0].distance_to(before[1])
	touches[event.index] = event.position
	var after: Array = touches.values()
	var new_gap: float = after[0].distance_to(after[1])
	if old_gap > 0.0:
		_set_zoom_level(zoom.x * new_gap / old_gap)


func _set_zoom_level(level: float) -> void:
	var clamped: float = clamp(level, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(clamped, clamped)
