attribute vec4 a_position;
uniform mat4 u_mvp;
varying vec2 v_uv;
void main() {
    v_uv = a_position.xy * 0.5 + 0.5;
    gl_Position = u_mvp * a_position;
}
