extends RefCounted
## Graphics quality (Low / Medium / High), per computer in user://settings.cfg. Set from the
## title screen or the Esc menu. A first run on built-in (integrated) graphics starts on Low.
##   low:    60% resolution (FSR upscaled), no fog, AO, glow or lamp shadows, less world loaded
##   medium: 80% resolution, fog and glow, smaller lamp shadows
##   high:   full resolution, 2x MSAA, everything on

const SETTINGS := "user://settings.cfg"
const LEVELS := ["low", "medium", "high"]


static func level() -> String:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var l = cfg.get_value("graphics", "quality", "")
	if l in LEVELS:
		return l
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return "low"
	return "high"


## Steps to the next level, saves it and returns it.
static func next() -> String:
	var l: String = LEVELS[(LEVELS.find(level()) + 1) % LEVELS.size()]
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("graphics", "quality", l)
	cfg.save(SETTINGS)
	return l


static func label() -> String:
	return "Graphics: " + level().capitalize()


## Applies the current level. `env` and `world` may be null (title screen).
static func apply(vp: Viewport, env: Environment, world) -> void:
	var l := level()
	match l:
		"low":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.6
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.positional_shadow_atlas_size = 0  # lamps and flashlight cast no shadows
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
