extends Control

@export var rect: Control
@export var center_y: bool = false
@export var kb_anchor: Node2D = null

var display_frame: Node2D = null
var landscape_ui: Control = null
var display_container: Node2D = null

var cached_kb_active: bool = false
var cached_controller_connected: bool = false

var dirty: bool = true
var last_screensize: Vector2i = Vector2i.ZERO

func set_keyboard_active(active: bool):
	if cached_kb_active != active:
		cached_kb_active = active
		dirty = true

func update_controller_state():
	var new_state = ControllerUtils.is_real_controller_connected()
	if cached_controller_connected != new_state:
		cached_controller_connected = new_state
		dirty = true

func _ready() -> void:
	if has_node("displayContainer/DisplayFrame"):
		display_frame = get_node("displayContainer/DisplayFrame")
	
	if has_node("displayContainer"):
		display_container = get_node("displayContainer")
	
	# Attempt to find sibling LandscapeUI
	var parent = get_parent()
	if parent and parent.has_node("LandscapeUI"):
		landscape_ui = parent.get_node("LandscapeUI")
	
	if has_node("kbanchor"):
		kb_anchor = get_node("kbanchor")
	
	if has_node("Label"):
		get_node("Label").visible = false
	
	# Initial check
	update_controller_state()
	visible = false

var frames_rendered = 0

func _process(delta: float) -> void:
	if frames_rendered < 10:
		frames_rendered += 1
		return
		
	var screensize := DisplayServer.window_get_size()
	if screensize.x == 0 or screensize.y == 0:
		return
		
	if screensize != last_screensize:
		dirty = true
		last_screensize = screensize
		# Safe to check keyboard height on resize (rare event)
		var real_kb_height = DisplayServer.virtual_keyboard_get_height()
		if real_kb_height == 0:
			cached_kb_active = false
			# Restore focus to game loop if keyboard closed
			if PicoVideoStreamer.instance:
				PicoVideoStreamer.instance.release_input_locks()
		
		if real_kb_height > 0:
			cached_kb_active = true
		
	if not dirty:
		return
	dirty = false # Reset flag
	
	var kb_height = 0
	
	var is_landscape = PicoVideoStreamer.is_system_landscape()

	
	var target_size = rect.size
	var target_pos = rect.position
	
	# Reserve space for side controls:
	# Assume we need at least some pixels on each side.
	# Let's subtract a "safe zone" width from the available screen width calculation.
	var available_size = Vector2(screensize)


	# Use cached state instead of polling every frame
	var is_controller_connected = cached_controller_connected
	
	# If Landscape OR Controller is connected, we target the game-only size (128x128)
	# BUT only if this is the actual game display (has display_container)
	# If Landscape OR Controller is connected, we target the game-only size (128x128)
	# BUT only if this is the actual game display (has display_container)
	var maxScale: int = 1
	if (is_landscape or is_controller_connected) and display_container:
		target_size = Vector2(128, 128)
		target_pos = Vector2(0, 0)
		
		# Define a "virtual" target size used ONLY for calculating the max scale.
		# This ensures that we reserve enough "game-pixel" equivalent space for the UI.
		var scale_calc_size = Vector2(128, 128)
		
		# Only reserve space for side controls if:
		# 1. We are physically in landscape (wide screen)
		# 2. AND No controller is connected (so we need on-screen controls)
		if is_landscape and not is_controller_connected:
			# We need approx 80 pixels of "game-scaled" space on each side.
			# 80 * 2 = 160. Total width 288.
			scale_calc_size.x += 160
		
		# Use the virtual size for scale calculation
		maxScale = max(1, floor(min(
			available_size.x / scale_calc_size.x, available_size.y / scale_calc_size.y
		)))
	else:
		# Standard scaling logic for portraits/menus
		maxScale = max(1, floor(min(
			available_size.x / target_size.x, available_size.y / target_size.y
		)))

	self.scale = Vector2(maxScale, maxScale)
	
	# Compensate for Arranger zoom to keep high-res D-pad at constant physical size
	var dpad = get_node_or_null("kbanchor/kb_gaming/Onmipad")
	if dpad:
		var target_scale = 8.5 / float(maxScale)
		dpad.scale = Vector2(target_scale, target_scale)

	if not visible:
		visible = true
	# Calculate kb_height based on overlap
	if cached_kb_active:
		var real_kb_h = DisplayServer.virtual_keyboard_get_height()
		# Calculate where the bottom of the Pico-8 specific screen is (in window coordinates)
		var screen_bottom = 0
		
		# For this calculation, we need to know where the "Arranger" top-left is effectively placed
		# Landscape is always centered. Portrait is usually 0, unless centered_y is on.
		if is_landscape:
			screen_bottom = (screensize.y / 2) + (64 * maxScale)
		else:
			# Portrait Logic:
			# Arranger Y = (Centered ? (ScreenY - ContentY)/2 : 0)
			# Screen Y = Arranger Y + 12 (top padding) + 128 (screen height)
			var content_height = target_size.y * maxScale
			var arr_y = (screensize.y - content_height) / 2 if center_y else 0
			screen_bottom = arr_y + (140 * maxScale) # 140 = 12 (padding) + 128 (screen)
		
		if screen_bottom > (screensize.y - real_kb_h):
			kb_height = 64

	
	var extraSpace = Vector2(screensize) - (target_size * maxScale)
	if kb_height:
		extraSpace.y -= kb_height
		if KBMan.get_current_keyboard_type() == KBMan.KBType.FULL:
			extraSpace.y = max(-92 * maxScale, extraSpace.y)
		else:
			extraSpace.y = max(0, extraSpace.y)
			
	if display_frame:
		display_frame.visible = false
		
	# Keyboard Anchor Control
	if kb_anchor != null:
		if is_landscape or is_controller_connected:
			# Normal logic: Hide in landscape or if controller connected
			kb_anchor.visible = false
		else:
			# Normal Portrait logic
			kb_anchor.visible = true


	if is_landscape:
		landscape_ui.visible = not is_controller_connected
		# Perfect Centering for Landscape Game Display
		self.position = (Vector2(screensize) / 2).floor()
	else:
		if not center_y:
			extraSpace.y = 0
		# Portrait / Generic UI Centering Logic (Top-Left Logic)
		self.position = Vector2i(Vector2(extraSpace.x / 2, extraSpace.y / 2) - target_pos * maxScale)

	# 2. Configure Display Container (if exists)
	if display_container:
		display_container.centered = is_landscape
		
		var target_y = 0
		# Base offset for portrait
		if not is_landscape:
			target_y = 12
			
		# Keyboard offset (move up to show bottom text)
		if kb_height > 0:
			target_y -= 64
			
		display_container.position = Vector2(0, target_y)
