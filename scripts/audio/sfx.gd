extends RefCounted
## Procedural sound library: every sound is synthesised in code at startup (no audio files).
## Call preload_all() once (during the loading screen), then play()/play_3d()/loop_3d().

const RATE := 22050

static var _cache := {}


static func preload_all() -> void:
	for n in ["hum", "drill", "pick", "step", "pistol", "shotgun", "overheat", "chitter", "bug_hurt",
			"bug_die", "bite", "gnaw", "break", "swarm_warn", "roar", "spit", "slash", "hurt", "flare", "flare_loop", "scan", "place", "click", "rig", "ambience",
			"drip", "deposit", "death", "empty"]:
		stream(n)


static func stream(n: String) -> AudioStreamWAV:
	if not _cache.has(n):
		_cache[n] = _make(n)
	return _cache[n]


## Non-positional one-shot (UI, the player's own body).
static func play(n: String, parent: Node, volume_db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream(n)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Positional one-shot that frees itself.
static func play_3d(n: String, pos: Vector3, parent: Node, volume_db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(n)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 60.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Persistent looping emitter attached to `parent`; the caller toggles .playing.
static func loop_3d(n: String, parent: Node3D, volume_db := 0.0, unit_size := 5.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(n)
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = 50.0
	parent.add_child(p)
	return p


# --- Synthesis ------------------------------------------------------------------

static func _make(n: String) -> AudioStreamWAV:
	match n:
		"hum":  # electric transformer hum: mains fundamental + harmonics, seamless 1 s loop
			return _loop(_gen(1.0, func(t, _i, _r):
				return 0.35 * sin(TAU * 60.0 * t) + 0.3 * sin(TAU * 120.0 * t) \
					+ 0.12 * sin(TAU * 180.0 * t) + 0.08 * sin(TAU * 240.0 * t) \
					+ 0.05 * sin(TAU * 360.0 * t) * (0.6 + 0.4 * sin(TAU * 2.0 * t))))
		"drill":  # motor whine + grinding, 1 s loop
			var grit := _noise(1.0, 0.25, 11)
			return _loop(_gen(1.0, func(t, i, _r):
				var whine := 0.22 * sin(TAU * 440.0 * t + 2.0 * sin(TAU * 7.0 * t)) + 0.12 * sin(TAU * 880.0 * t)
				return whine + grit[i] * (0.7 + 0.3 * sin(TAU * 31.0 * t))))
		"pick":  # stone chip: noise crack + low thud + metallic ping
			var crack := _noise(0.3, 0.6, 3)
			return _gen(0.3, func(t, i, _r):
				return crack[i] * exp(-t * 40.0) + 0.5 * sin(TAU * 95.0 * t) * exp(-t * 25.0) \
					+ 0.18 * sin(TAU * 2100.0 * t) * exp(-t * 18.0))
		"step":  # gravel footstep
			var g := _noise(0.14, 0.35, 5)
			return _gen(0.14, func(t, i, _r):
				return (g[i] * 1.4 + 0.3 * sin(TAU * 70.0 * t)) * exp(-t * 35.0))
		"pistol":  # laser zap: falling sine sweep
			return _gen(0.2, func(t, _i, _r):
				var f := lerpf(2200.0, 380.0, t / 0.2)
				return 0.55 * sin(TAU * f * t) * exp(-t * 14.0) + 0.15 * sin(TAU * f * 1.5 * t) * exp(-t * 30.0))
		"shotgun":  # heavy laser blast: low sweep + noise burst
			var blast := _noise(0.4, 0.5, 7)
			return _gen(0.4, func(t, i, _r):
				var f := lerpf(900.0, 110.0, minf(t / 0.3, 1.0))
				return 0.5 * sin(TAU * f * t) * exp(-t * 7.0) + blast[i] * 0.9 * exp(-t * 16.0))
		"overheat":  # venting hiss
			var h := _noise(0.6, 0.9, 13)
			return _gen(0.6, func(t, i, _r): return h[i] * 0.7 * exp(-t * 4.0) * minf(t * 30.0, 1.0))
		"chitter":  # bug clicks: fast train of filtered noise pulses
			var c := _noise(0.35, 0.8, 17)
			return _gen(0.35, func(t, i, _r):
				var pulse := pow(maxf(sin(TAU * 26.0 * t), 0.0), 8.0)
				return c[i] * pulse * 1.3 * (1.0 - t / 0.35))
		"bug_hurt":  # squeal
			return _gen(0.18, func(t, _i, _r):
				return 0.45 * sin(TAU * lerpf(1500.0, 800.0, t / 0.18) * t) * exp(-t * 12.0))
		"bug_die":  # wet crunch + falling squeal
			var sq := _noise(0.45, 0.4, 19)
			return _gen(0.45, func(t, i, _r):
				return sq[i] * exp(-t * 9.0) + 0.35 * sin(TAU * lerpf(900.0, 200.0, t / 0.45) * t) * exp(-t * 6.0))
		"bite":  # mandible snap
			var s := _noise(0.1, 0.9, 23)
			return _gen(0.1, func(t, i, _r): return s[i] * exp(-t * 60.0) * 1.2)
		"gnaw":  # jaws on metal: scrape + clank
			var gs := _noise(0.22, 0.95, 53)
			return _gen(0.22, func(t, i, _r):
				return gs[i] * exp(-t * 18.0) * 0.9 + 0.3 * sin(TAU * 1730.0 * t) * exp(-t * 22.0) 					+ 0.2 * sin(TAU * 2610.0 * t) * exp(-t * 30.0))
		"break":  # machine failure: heavy clank, then a crackle of shorting sparks
			var bc := _noise(1.2, 0.9, 59)
			return _gen(1.2, func(t, i, _r):
				var clank := 0.5 * sin(TAU * 150.0 * t) * exp(-t * 8.0) + 0.25 * sin(TAU * 523.0 * t) * exp(-t * 6.0) 					+ 0.15 * sin(TAU * 1370.0 * t) * exp(-t * 9.0)
				var crackle := bc[i] * pow(maxf(sin(TAU * 11.0 * t + sin(TAU * 3.0 * t) * 4.0), 0.0), 12.0) * 1.5
				return clank + crackle * minf(t * 6.0, 1.0) * exp(-t * 1.5))
		"swarm_warn":  # something big moving in the rock: swelling rumble, then chittering
			var rum := _noise(3.5, 0.025, 61)
			var ch := _noise(3.5, 0.8, 67)
			return _gen(3.5, func(t, i, _r):
				var swell := sin(PI * t / 3.5)
				var clicks := pow(maxf(sin(TAU * (18.0 + t * 6.0) * t), 0.0), 10.0) * smoothstep(1.2, 3.0, t)
				return rum[i] * 3.0 * swell + ch[i] * clicks * 0.8 * swell)
		"roar":  # boss roar: growling low saw with a rough noise throat, swelling then falling
			var rn := _noise(1.8, 0.3, 71)
			return _gen(1.8, func(t, i, _r):
				var env: float = minf(t * 6.0, 1.0) * exp(-maxf(t - 0.8, 0.0) * 2.5)
				var f: float = 70.0 + 25.0 * sin(TAU * 0.7 * t) - t * 12.0
				var saw: float = fmod(f * t, 1.0) * 2.0 - 1.0
				var growl: float = saw * (0.6 + 0.4 * sin(TAU * 31.0 * t))
				return (growl * 0.35 + rn[i] * 0.9) * env)
		"spit":  # wet hiss of spines leaving the throat
			var sp := _noise(0.35, 0.85, 73)
			return _gen(0.35, func(t, i, _r):
				return sp[i] * exp(-t * 9.0) * minf(t * 80.0, 1.0) + 0.2 * sin(TAU * lerpf(500.0, 180.0, t / 0.35) * t) * exp(-t * 10.0))
		"slash":  # quick blade whoosh
			var sl := _noise(0.22, 0.7, 79)
			return _gen(0.22, func(t, i, _r):
				var env: float = sin(PI * clampf(t / 0.22, 0.0, 1.0))
				return sl[i] * env * env * 0.9)
		"hurt":  # body hit: low thump
			var b := _noise(0.25, 0.2, 29)
			return _gen(0.25, func(t, i, _r):
				return 0.7 * sin(TAU * 65.0 * t) * exp(-t * 14.0) + b[i] * exp(-t * 20.0))
		"flare":  # ignition hiss
			var fl := _noise(0.7, 0.85, 31)
			return _gen(0.7, func(t, i, _r): return fl[i] * 0.8 * exp(-t * 3.0) * minf(t * 60.0, 1.0))
		"flare_loop":  # burning sputter, 1 s loop
			var fb := _noise(1.0, 0.6, 37)
			return _loop(_gen(1.0, func(t, i, _r):
				return fb[i] * 0.35 * (0.75 + 0.25 * sin(TAU * 9.0 * t))))
		"scan":  # rising chirp with an echo
			return _gen(0.8, func(t, _i, _r):
				var a := 0.4 * sin(TAU * lerpf(500.0, 1600.0, minf(t / 0.25, 1.0)) * t) * exp(-t * 6.0)
				var e := 0.0
				if t > 0.3:
					e = 0.18 * sin(TAU * 1600.0 * t) * exp(-(t - 0.3) * 8.0)
				return a + e)
		"place":  # heavy clunk
			return _gen(0.4, func(t, _i, _r):
				return 0.6 * sin(TAU * 110.0 * t) * exp(-t * 12.0) + 0.2 * sin(TAU * 640.0 * t) * exp(-t * 10.0) \
					+ 0.1 * sin(TAU * 1310.0 * t) * exp(-t * 16.0))
		"click":  # UI blip
			return _gen(0.06, func(t, _i, _r): return 0.35 * sin(TAU * 1250.0 * t) * exp(-t * 60.0))
		"deposit":  # ore rattling into a bin
			var dp := _noise(0.5, 0.5, 41)
			return _gen(0.5, func(t, i, _r):
				var rattle := pow(maxf(sin(TAU * 17.0 * t), 0.0), 6.0)
				return dp[i] * rattle * exp(-t * 4.0) * 1.4)
		"rig":  # diesel-free electric drive: low rumble with a motor tone, 1 s loop
			var rr := _noise(1.0, 0.08, 43)
			return _loop(_gen(1.0, func(t, i, _r):
				return 0.3 * sin(TAU * 48.0 * t) + 0.18 * sin(TAU * 96.0 * t) + 0.1 * sin(TAU * 300.0 * t) \
					+ rr[i] * 1.5))
		"ambience":  # cave air: very low rumble, 4 s loop
			var am := _noise(4.0, 0.02, 47)
			return _loop(_gen(4.0, func(t, i, _r): return am[i] * 2.5 * (0.8 + 0.2 * sin(TAU * 0.25 * t))))
		"drip":  # water drop
			return _gen(0.15, func(t, _i, _r):
				return 0.4 * sin(TAU * lerpf(1600.0, 900.0, t / 0.15) * t) * exp(-t * 30.0))
		"death":  # low falling tone
			return _gen(1.2, func(t, _i, _r):
				return 0.4 * sin(TAU * lerpf(220.0, 55.0, t / 1.2) * t) * exp(-t * 2.0))
		_:  # "empty": dry click when out of charges
			return _gen(0.05, func(t, _i, _r): return 0.3 * sin(TAU * 300.0 * t) * exp(-t * 80.0))


## Renders `fn(t, index, rng)` -> float sample into a 16-bit mono WAV stream.
static func _gen(seconds: float, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var v: float = fn.call(float(i) / RATE, i, rng)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


static func _loop(s: AudioStreamWAV) -> AudioStreamWAV:
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = s.data.size() / 2
	return s


## Low-passed white noise: `brightness` 1 = white, small = rumbly.
static func _noise(seconds: float, brightness: float, seed_value: int) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var y := 0.0
	for i in n:
		y += brightness * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y
	# Normalise so dark noise isn't silent.
	var peak := 0.001
	for v in out:
		peak = maxf(peak, absf(v))
	for i in n:
		out[i] = out[i] / peak * 0.5
	return out
