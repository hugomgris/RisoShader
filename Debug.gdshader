shader_type canvas_item;

void fragment() {
    vec3 base = texture(TEXTURE, UV).rgb;
    // Amplify whatever is there x10 so we can see it
    COLOR = vec4(base * 10.0, 1.0);
}