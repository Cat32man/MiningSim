extends RefCounted
## Graphics settings, per computer in user://settings.cfg, set from the title screen or the
## Esc menu. Two separate choices:
##   Renderer: Vulkan (default) or OpenGL (the Compatibility renderer, for old or flaky
##     drivers: a friend's Intel UHD on a 2020 driver kept losing its Vulkan device). It only
##     changes at start-up: it's written to override.cfg next to the game, which Godot reads
##     when it starts.
##   Quality: Low / Medium / High (a first run on built-in graphics starts on Low).
##     low:    60% resolution, no fog, AO, glow or lamp shadows, less world loaded
##     medium: 80% resolution, fog and glow, smaller lamp shadows
##     high:   full resolution, 2x MSAA, everything on
##   (OpenGL has no FSR, fog or AO, so there it scales plainly and skips those.)

const SETTINGS := "user://settings.cfg"
const LEVELS := ["low", "medium", "high"]
const RENDERERS := ["vulkan", "opengl"]


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg


static func level() -> String:
	var l = _cfg().get_value("graphics", "quality", "")
	if l == "very_low":
		return "low"  # v12's "Very low" was OpenGL + low
	if l in LEVELS:
		return l
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return "low"
	return "high"


## Steps to the next quality level, saves it and returns it.
static func next() -> String:
	var l: String = LEVELS[(LEVELS.find(level()) + 1) % LEVELS.size()]
	var cfg := _cfg()
	cfg.set_value("graphics", "quality", l)
	cfg.save(SETTINGS)
	return l


static func label() -> String:
	return "Graphics: " + level().capitalize()


# --- Renderer ------------------------------------------------------------------------

## The renderer chosen for the next start.
static func renderer() -> String:
	var cfg := _cfg()
	var r = cfg.get_value("graphics", "renderer", "")
	if r in RENDERERS:
		return r
	return "opengl" if cfg.get_value("graphics", "quality", "") == "very_low" else "vulkan"


static func set_renderer(r: String) -> void:
	var cfg := _cfg()
	cfg.set_value("graphics", "renderer", r)
	cfg.save(SETTINGS)
	_write_override(r == "opengl")


static func next_renderer() -> String:
	var r: String = RENDERERS[(RENDERERS.find(renderer()) + 1) % RENDERERS.size()]
	set_renderer(r)
	return r


static func renderer_label() -> String:
	return "Renderer: %s%s" % ["OpenGL" if renderer() == "opengl" else "Vulkan",
		" (restart)" if needs_restart() else ""]


static func using_opengl() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## The renderer only changes when the game starts.
static func needs_restart() -> bool:
	return (renderer() == "opengl") != using_opengl()


## Godot reads override.cfg beside the executable at start-up (exported builds only).
static func _write_override(opengl: bool) -> void:
	if not OS.has_feature("template"):
		return
	var path := OS.get_executable_path().get_base_dir().path_join("override.cfg")
	if opengl:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string('[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n')
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# --- Applying ------------------------------------------------------------------------

## Applies the quality level for the running renderer. `env` and `world` may be null
## (title screen).
static func apply(vp: Viewport, env: Environment, world) -> void:
	var l := level()
	var gl := using_opengl()
	var scale := {"low": 0.6, "medium": 0.8, "high": 1.0}[l] as float
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 and not gl else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	vp.msaa_3d = Viewport.MSAA_2X if l == "high" else Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = {"low": 0, "medium": 2048, "high": 4096}[l]  # 0: no lamp shadows
	if env:
		env.volumetric_fog_enabled = l != "low"
		env.ssao_enabled = l == "high"
		env.glow_enabled = l != "low"
	if world:
		world.view_radius_h = 3 if l == "low" else 4
