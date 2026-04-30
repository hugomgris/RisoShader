shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 group_color : source_color = vec3(1.0, 0.0, 0.0);

void fragment() {
    ALBEDO = group_color;
}