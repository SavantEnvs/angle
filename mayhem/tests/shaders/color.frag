#version 300 es
precision mediump float;
uniform vec4 u_color;
in vec2 v_uv;
out vec4 fragColor;
void main() {
    float d = length(v_uv - vec2(0.5));
    fragColor = u_color * smoothstep(0.5, 0.4, d);
}
