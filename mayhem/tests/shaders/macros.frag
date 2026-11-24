#version 300 es
#define SCALE(x) ((x) * 2.0)
#if defined(GL_ES) && __VERSION__ >= 300
precision highp float;
#endif
out vec4 o;
void main() {
    vec3 v = vec3(SCALE(0.25), 1.0, 0.0);
    for (int i = 0; i < 3; ++i) { v.z += float(i); }
    o = vec4(v, 1.0);
}
