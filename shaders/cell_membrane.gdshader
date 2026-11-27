// 细胞膜：半透明、缓慢流动起伏、边缘硬高光。主角和敌人共用，参数由 CellLook 资源给。
// DESIGN《细胞的视觉系统》：两层结构（实核 + 半透明膜）、待机时膜在流动、轮廓必须硬。
// 没有任何贴图：起伏用几组正弦叠出来，边缘高光用视线与法线的夹角（菲涅尔）算。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 膜的颜色和不透明度。半透明是为了看见里面的核
uniform vec4 base_color : source_color = vec4(0.55, 0.85, 0.8, 1.0);
uniform float body_alpha : hint_range(0.0, 1.0) = 0.4;
// 边缘高光：保证半透明物体在任何背景下剪影都清楚（重叠时不糊成一团）
uniform vec4 rim_color : source_color = vec4(0.85, 1.0, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 6.0) = 2.0;
// 菲涅尔超过这个值才算"边缘"；越大边缘线越细
uniform float rim_edge : hint_range(0.0, 1.0) = 0.6;
// 边缘线的软硬：越小越硬
uniform float rim_softness : hint_range(0.001, 1.0) = 0.12;
// 膜的流动：速度、起伏幅度（米）、起伏的疏密
uniform float flow_speed = 0.6;
uniform float flow_amplitude = 0.03;
uniform float flow_scale = 3.0;
// 0 = 软膜；1 = 聚合成刃（不起伏、不透明、高光更锐）。伪足挥击时用
uniform float hardness : hint_range(0.0, 1.0) = 0.0;

float wobble(vec3 p, float t) {
    return sin(p.x * flow_scale + t * 1.3)
        * sin(p.y * flow_scale * 1.1 + t * 0.9)
        * sin(p.z * flow_scale * 0.9 + t * 1.7);
}

void vertex() {
    float t = TIME * flow_speed;
    // 两层不同频率叠加，避免一眼看出是规则的正弦波
    float w = wobble(VERTEX, t) + 0.5 * wobble(VERTEX * 2.1 + vec3(1.7, 0.3, 2.9), t * 1.6);
    VERTEX += NORMAL * w * flow_amplitude * (1.0 - hardness);
}

void fragment() {
    float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float soft = mix(rim_softness, 0.02, hardness);
    float rim = smoothstep(rim_edge - soft, rim_edge, fres);
    ALBEDO = base_color.rgb;
    // 边缘处不透明度拉高：剪影是实的，只有中间是透的
    ALPHA = clamp(mix(body_alpha, 1.0, hardness) + rim * 0.7, 0.0, 1.0);
    EMISSION = rim_color.rgb * rim * rim_strength;
    ROUGHNESS = mix(0.55, 0.12, hardness);
    SPECULAR = mix(0.35, 0.9, hardness);
}
