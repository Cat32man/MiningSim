shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Terrain rock. Vertex colour = material tint (alpha = 1 - lava glow); UV2 = (metallic, glint)
// from materials.gd.
// World-space triplanar mapping so chunks line up seamlessly.

uniform sampler2D albedo_noise : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bump_noise : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D glint_noise : filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.22;
uniform float bump_strength = 1.2;
// Floors get less bump so they read as smooth, walkable ground.
uniform float floor_bump = 0.45;
uniform float glint_scale = 3.5;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

float tri_sample(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy).r * w.x + texture(tex, p.xz).r * w.y + texture(tex, p.xy).r * w.z;
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 w = tri_weights(n);
	vec3 p = w_pos * uv_scale;

	// Masks sharpened so vein edges don't smear across whole triangles.
	float metal = smoothstep(0.1, 0.4, UV2.x) * UV2.x;
	float ore = smoothstep(0.1, 0.4, UV2.y) * UV2.y;

	ALBEDO = COLOR.rgb * tri_sample(albedo_noise, p, w);

	// Triplanar normal map, whiteout blend, in world space.
	float strength = bump_strength * mix(1.0, floor_bump, smoothstep(0.6, 0.9, n.y));
	vec3 tx = texture(bump_noise, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(bump_noise, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(bump_noise, p.xy).xyz * 2.0 - 1.0;
	tx.xy *= strength;
	ty.xy *= strength;
	tz.xy *= strength;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 wn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Glints: tiny crystal facets that catch the light. Sampling shifts slightly with the view
	// direction, so they twinkle as you move — but they only show where light actually hits.
	vec3 gp = w_pos * glint_scale + VIEW * 0.15;
	float g = tri_sample(glint_noise, gp, w);
	float glint = smoothstep(0.72, 0.8, g) * ore;

	// Lava cracks: thin bright seams where two noise layers cross, breathing slowly.
	float glow = 1.0 - COLOR.a;
	if (glow > 0.01) {
		float c1 = tri_sample(albedo_noise, w_pos * 0.09, w);
		float c2 = tri_sample(glint_noise, w_pos * 0.05 + vec3(13.0), w);
		// Only some patches of rock are cracked through.
		float patch = smoothstep(0.6, 0.75, tri_sample(albedo_noise, w_pos * 0.02 + vec3(41.0), w));
		float seam = (1.0 - smoothstep(0.0, 0.012, abs(c1 - c2))) * patch;
		float pulse = 0.75 + 0.25 * sin(TIME * 1.3 + dot(w_pos, vec3(0.21, 0.13, 0.17)));
		EMISSION = vec3(1.0, 0.22, 0.03) * seam * glow * pulse * 2.2;
		ALBEDO = mix(ALBEDO, vec3(0.9, 0.3, 0.05), seam * glow * 0.5);
	}

	METALLIC = metal;
	ROUGHNESS = mix(mix(0.93, 0.3, max(metal, ore * 0.7)), 0.06, glint);
	SPECULAR = mix(0.5, 1.0, max(ore, glint));
}
