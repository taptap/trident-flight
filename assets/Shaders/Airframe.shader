// Meter-scale swept panel construction and filtered coating relief, without a UV/tangent dependency.
shader_type spatial;
render_mode shading_model_pbr, cull_disabled;
uniform vec4 coating = vec4(0.05, 0.055, 0.06, 1.0);
uniform float base_roughness = 0.48;
uniform float metal = 0.45;
uniform float coat = 0.0;
uniform float skin_detail = 0.0;
uniform vec3 navigation_light = vec3(0.0);
varying vec3 local_position;
varying vec3 local_normal;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hatch_distance(vec2 p, vec2 half_size) {
    vec2 q = abs(p) - half_size + vec2(0.08);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.08;
}

void vertex() {
    local_position = VERTEX;
    local_normal = NORMAL;
}

void fragment() {
    vec2 p = vec2(abs(local_position.x), local_position.z);
    vec2 panel = vec2(p.x / 1.8, (p.y - p.x * 1.18) / 2.65);
    vec2 edge = (0.5 - abs(fract(panel) - 0.5)) * vec2(1.8, 2.65);
    float aa = max(length(fwidth(p)) * 0.65, 0.002);
    float seam_distance = min(edge.x, edge.y);
    float hatch = min(abs(hatch_distance(p - vec2(3.1, 12.8), vec2(0.52, 0.8))),
        abs(hatch_distance(p - vec2(5.7, 17.0), vec2(0.42, 0.62))));
    seam_distance = min(seam_distance, hatch);
    float coverage = min(1.0, 0.012 / aa);
    float seam = (1.0 - smoothstep(0.005, 0.005 + aa, seam_distance)) * coverage;
    float bevel = 1.0 - smoothstep(0.012, 0.04 + aa, seam_distance);
    // Flush fasteners sit beside the structural seam, not in a grid across the entire wing.
    vec2 fastener = vec2(abs(edge.x - 0.055), (fract(p.y / 0.26) - 0.5) * 0.26);
    float rivet = (1.0 - smoothstep(0.009, 0.009 + aa, length(fastener))) * coverage * coverage;
    float detail = skin_detail * smoothstep(3.0, 5.0, p.y) * smoothstep(0.2, 0.7, abs(local_normal.y));
    float panel_tone = hash21(floor(panel));
    float grain = sin(local_position.x * 330.0) * sin(local_position.z * 310.0 + local_position.y * 97.0);
    float grain_filter = 1.0 - smoothstep(0.5, 2.5, length(fwidth(local_position * 52.0)));
    float broad = sin(p.y * 3.2 + sin(p.x * 7.1)) * sin(p.x * 5.7) * 0.5 + 0.5;
    ALBEDO = coating.rgb * (1.0 + detail * ((panel_tone - 0.5) * 0.12 + (broad - 0.5) * 0.035));
    ALBEDO *= 1.0 - detail * (seam * 0.48 + rivet * 0.22);
    ROUGHNESS = clamp(base_roughness + detail * ((panel_tone - 0.5) * 0.055 + bevel * 0.04)
        + skin_detail * grain * 0.025 * grain_filter, 0.05, 0.95);
    // Surface-gradient bump mapping works on the original position/normal-only GLB.
    float height = detail * (-seam * 0.0018 - rivet * 0.0007 + bevel * 0.0005)
        + skin_detail * grain * grain_filter * 0.00012;
    vec3 dx = dFdx(VERTEX);
    vec3 dy = dFdy(VERTEX);
    vec3 r1 = cross(dy, NORMAL);
    vec3 r2 = cross(NORMAL, dx);
    float det = dot(dx, r1);
    vec3 gradient = (r1 * dFdx(height) + r2 * dFdy(height)) * sign(det) / max(abs(det), 0.00000001);
    NORMAL = normalize(NORMAL - gradient);
    METALLIC = metal;
    SPECULAR = 0.5;
    CLEARCOAT = coat;
    CLEARCOAT_ROUGHNESS = 0.13;
    EMISSION = navigation_light;
}
