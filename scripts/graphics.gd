extends RefCounted
## Graphics quality (Very low / Low / Medium / High), per computer in user://settings.cfg. Set
## from the title screen or the Esc menu. A first run on built-in (integrated) graphics starts
## on Low.
##   very_low: the OpenGL (Compatibility) renderer instead of Vulkan, for old or flaky drivers
##             (an Intel UHD on a 2020 driver kept losing its Vulkan device). Needs a restart:
##             it's written to override.cfg next to the game, which Godot reads at start-up.
##   low:      60% resolution (FSR upscaled), no fog, AO, glow or lamp shadows, less world loaded
##   medium:   80% resolution, fog and glow, smaller lamp shadows
##   high:     full resolution, 2x MSAA, everything on

const SETTINGS := "user://settings.cfg"
const LEVELS := ["very_low", "low", "medium", "high"]
const NAMES := {"very_low": "Very low (OpenGL)", "low": "Low", "medium": "Medium", "high": "High"}


static func level() -> String:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var l = cfg.get_value("graphics", "quality", "")
	if l in LEVELS:
		return l
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return "low"
	return "high"


static func set_level(l: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("graphics", "quality", l)
	cfg.save(SETTINGS)
	_write_renderer(l == "very_low")


## Steps to the next level, saves it and returns it.
static func next() -> String:
	var l: String = LEVELS[(LEVELS.find(level()) + 1) % LEVELS.size()]
	set_level(l)
	return l


static func label() -> String:
	return "Graphics: " + NAMES[level()] + (" (restart)" if needs_restart() else "")


static func using_opengl() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## The renderer only changes when the game starts.
static func needs_restart() -> bool:
	return (level() == "very_low") != using_opengl()


static func _override_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join("override.cfg")


## Godot reads override.cfg beside the executable at start-up (exported builds only).
static func _write_renderer(opengl: bool) -> void:
	if not OS.has_feature("template"):
		return
	var path := _override_path()
	if opengl:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string('[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n')
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Applies the current level. `env` and `world` may be null (title screen).
static func apply(vp: Viewport, env: Environment, world) -> void:
	var l := level()
	if using_opengl():
		# OpenGL: no FSR, fog or AO there anyway; keep it light.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 0.75
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.positional_shadow_atlas_size = 0
		l = "low"
	else:
		match l:
			"very_low", "low":  # very_low waiting for a restart: low until then
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				vp.scaling_3d_scale = 0.6
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.positional_shadow_atlas_size = 0  # lamps and flashlight cast no shadows
				l = "low"
			"medium":
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				vp.scaling_3d_scale = 0.8
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.positional_shadow_atlas_size = 2048
			_:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
				vp.scaling_3d_scale = 1.0
				vp.msaa_3d = Viewport.MSAA_2X
				vp.positional_shadow_atlas_size = 4096
	if env:
		env.volumetric_fog_enabled = l != "low"
		env.ssao_enabled = l == "high"
		env.glow_enabled = l != "low"
	if world:
		world.view_radius_h = 3 if l == "low" else 4
