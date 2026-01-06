extends Control

func _process(delta: float) -> void:
	var arranger = get_node_or_null("../Arranger")
	if arranger:
		# Force uniform scaling to prevent distortion (use X scale for both axes)
		var s = arranger.scale.x
		scale = Vector2(s, s)
		# Compensate size so anchors cover the full viewport in local coordinates
		size = get_viewport_rect().size / s
		
		# Inverse scale the high-res D-Pad so it stays physical size
		var dpad = get_node_or_null("Control/LeftPad/Omnipad")
		if dpad:
			var target_scale = 8.5 / s
			dpad.scale = Vector2(target_scale, target_scale)
	else:
		size = get_viewport_rect().size
	
	var is_landscape = PicoVideoStreamer.is_system_landscape()
	
	# Only show if in landscape mode AND controls are needed (no physical controller)
	var is_controller_connected = ControllerUtils.is_real_controller_connected()
	var should_be_visible = is_landscape and not is_controller_connected
	
	# print("LandscapeUI: landscape=", is_landscape, " controller=", is_controller_connected, " visible=", should_be_visible)
	
	visible = should_be_visible
