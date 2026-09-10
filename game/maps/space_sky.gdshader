shader_type sky;

// Procedural spacescape for the graybox corridor: deep-space gradient,
// two hash-based star layers, faint nebulae (purple + brand-orange), and
// a small sun disc aligned with the scene's DirectionalLight. Pure math —
// no texture assets, so the map stays hand-written and diffable.


float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}


float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z
	);
}


float fbm(vec3 p) {
	float amp = 0.5;
	float sum = 0.0;
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec3(11.5, 7.3, 5.1);
		amp *= 0.5;
	}
	return sum;
}


// One star field: the sphere is cut into `cells` cubic cells, `density` of
// them get a star at a hashed offset, drawn as a soft dot of size `size`
// (cell-space). Brightness varies per star so the field doesn't look flat.
float star_layer(vec3 dir, float cells, float density, float size) {
	vec3 p = dir * cells;
	vec3 cell = floor(p);
	float h = hash13(cell);
	vec3 sp = vec3(hash13(cell + 13.1), hash13(cell + 27.7), hash13(cell + 41.3)) * 0.6 + 0.2;
	float d = length(fract(p) - sp);
	float twinkle = 0.6 + 0.4 * hash13(cell + 3.7);
	return step(1.0 - density, h) * smoothstep(size, 0.0, d) * twinkle;
}


void sky() {
	vec3 dir = EYEDIR;
	// Deep space, barely lighter toward the horizon so up/down still reads.
	vec3 col = mix(
		vec3(0.012, 0.014, 0.026), vec3(0.035, 0.040, 0.070), pow(1.0 - abs(dir.y), 3.0)
	);
	// Nebulae: broad cold purple + a sparser warm band in the brand orange.
	float neb1 = fbm(dir * 2.6);
	float neb2 = fbm(dir * 5.2 + vec3(19.0, 3.0, 7.0));
	col += vec3(0.10, 0.07, 0.18) * smoothstep(0.48, 0.85, neb1);
	col += vec3(0.16, 0.09, 0.04) * smoothstep(0.58, 0.95, neb2);
	// Stars: dense faint field + sparse bright field.
	float s = star_layer(dir, 90.0, 0.20, 0.28) * 0.5;
	s += star_layer(dir, 45.0, 0.08, 0.18) * 1.4;
	col += vec3(0.90, 0.95, 1.00) * s;
	// Sun disc + halo where the scene's DirectionalLight comes from, so the
	// shadows on the track visibly belong to something in the sky.
	if (LIGHT0_ENABLED) {
		float amt = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * (pow(amt, 1400.0) * 3.0 + pow(amt, 60.0) * 0.12);
	}
	COLOR = col;
}
