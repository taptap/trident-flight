// NanoVG draws the live cockpit displays into one sRGB-encoded render target.
shader_type spatial;
render_mode shading_model_pbr, cull_back;
uniform sampler2D display : filter_linear;
void fragment() {
    vec3 pixel = texture(display, vec2(UV.x, 1.0 - UV.y)).rgb;
    ALBEDO = vec3(0.003, 0.006, 0.009);
    EMISSION = pow(pixel, vec3(2.2)) * 0.85;
    ROUGHNESS = 0.3;
    METALLIC = 0.0;
    CLEARCOAT = 0.25;
    CLEARCOAT_ROUGHNESS = 0.18;
}
