extends XROrigin3D

## Current XR interface
var xr_interface: OpenXRInterface
var xr_is_focused = false

@onready var demo_scene = $DemoScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	xr_interface = XRServer.find_interface('OpenXR')
	if xr_interface == null:
		return

	if xr_interface.is_initialized():
		var vp: Viewport = get_viewport()
		vp.use_xr = true
		vp.transparent_bg = true

		# Disable vsync
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

		# Enable VRS
		if RenderingServer.get_rendering_device():
			vp.vrs_mode = Viewport.VRS_XR

		# Connect the OpenXR events
		xr_interface.session_begun.connect(_on_openxr_session_begun)
		xr_interface.session_visible.connect(_on_openxr_visible_state)
		xr_interface.session_focussed.connect(_on_openxr_focused_state)

		# Check for passthrough
		if xr_interface.is_passthrough_supported():
			xr_interface.start_passthrough()

		var spatial_container_ext = OpenXRSpatialContainerExtension
		if spatial_container_ext:
			_update_scale_from_bounds()
			print("Connecting to spatial container signals...")
			spatial_container_ext.spatial_container_bounds_changed.connect(_on_spatial_container_bounds_changed)
			spatial_container_ext.spatial_container_interactable_changed.connect(_on_spatial_container_interactability_changed)
			

func _update_scale_from_bounds():
	var spatial_container_ext = OpenXRSpatialContainerExtension
	if spatial_container_ext:
		print("Updating scale from bounds...")
		var bounds = spatial_container_ext.get_spatial_container_bounds()
		_update_scale(bounds)


func _on_spatial_container_bounds_changed(_spatial_container_rid: RID, _infinite_bounds: bool, _bounds_mode: OpenXRSpatialContainerState.BoundsMode, updated_bounds: Vector3) -> void:
	_update_scale(updated_bounds)


func _update_scale(bounds: Vector3) -> void:
	# Use the smallest dimension to update the scale, so we keep the gltf with
	# a constant aspect ratio within the spatial container bounds
	var min_dimension: float = min(bounds.x, min(bounds.y, bounds.z))
	world_scale = 20 / min_dimension


func _on_spatial_container_interactability_changed(_spatial_container_rid: RID, anyInteractable: bool) -> void:
	print("Interactability changed to " + str(anyInteractable))


# Handle OpenXR session ready
func _on_openxr_session_begun() -> void:
	if xr_interface == null:
		return

	# Get the reported refresh rate
	var current_refresh_rate = xr_interface.get_display_refresh_rate()
	if current_refresh_rate > 0:
		print("OpenXR: Refresh rate reported as ", str(current_refresh_rate))
	else:
		print("OpenXR: No refresh rate given by the XR runtime")

	# See if we have a better refresh rate available
	var new_rate = current_refresh_rate
	var available_rates: Array = xr_interface.get_available_display_refresh_rates()
	if available_rates.size() == 0:
		print("OpenXR: Target does not support refresh rate extension")
	elif available_rates.size() == 1:
		# Only one available, so use it
		new_rate = available_rates[0]
	else:
		for rate in available_rates:
			if rate < new_rate:
				new_rate = rate

	# Did we find a better rate?
	if current_refresh_rate != new_rate:
		print("OpenXR: Setting refresh rate to ", str(new_rate))
		xr_interface.set_display_refresh_rate(new_rate)
		current_refresh_rate = new_rate

	# Now match our physics rate
	Engine.physics_ticks_per_second = current_refresh_rate


# Handle OpenXR visible state
func _on_openxr_visible_state() -> void:
	_update_scale_from_bounds()
	# We always pass this state at startup,
	# but the second time we get this, it means our player took off their headset
	if xr_is_focused:
		print("OpenXR lost focus")

		xr_is_focused = false

		# Pause the game
		process_mode = Node.PROCESS_MODE_DISABLED


# Handle OpenXR focused state
func _on_openxr_focused_state() -> void:
	print("OpenXR gained focus")
	xr_is_focused = true

	# Unpause the game
	process_mode = Node.PROCESS_MODE_INHERIT
