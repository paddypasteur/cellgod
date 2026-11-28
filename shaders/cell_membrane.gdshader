// 细胞膜：半透明、流动起伏、边缘硬高光。主角和敌人共用，参数由 CellLook 资源给。
// DESIGN《细胞的视觉系统》：两层结构（实核 + 半透明膜）、待机时膜在流动、轮廓必须硬。
// 没有任何贴图：起伏用几组正弦叠出来，边缘高光用视线与法线的夹角（菲涅尔）算。
//
// 主角的攻击也全在这里（DESIGN《攻击动作 = 全细胞惯性》）：没有单独的刃模型，
// 刃是膜朝出手方向被拉出去的那一段——根部就是身体，越往外越薄，挥动时尾部被甩在后面而弯。
// 整团质量的偏移（蓄力时往后聚、出手时往前冲、收招后晃）由一个"质量偏移"矢量驱动。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 膜的颜色和不透明度。半透明是为了看见里面的核
uniform vec4 base_color : source_color = vec4(0.55, 0.85, 0.8, 1.0);
uniform float body_alpha : hint_range(0.0, 1.0) = 0.4;
// 边缘高光：保证半透明物体在任何背景下剪影都清楚（重叠时不糊成一团）
uniform vec4 rim_color : source_color = vec4(0.85, 1.0, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 6.0) = 2.0;
// 边缘线的宽度（屏幕像素）。按像素而不是按角度定宽：
// 按角度定宽时，视线几乎贴着表面掠过的大片区域都会被判成"边缘"，整个物体泛亮、看不见内部（2026-11-27 开发者反馈）
uniform float rim_pixels : hint_range(0.5, 12.0) = 2.5;
// 边缘带最宽能占菲涅尔值的多少，防止远处小物体整个被描满
uniform float rim_max_band : hint_range(0.01, 1.0) = 0.3;
// 膜的流动：速度、起伏幅度（米）、起伏的疏密
uniform float flow_speed = 0.6;
uniform float flow_amplitude = 0.03;
uniform float flow_scale = 3.0;
// 挥击时胞质被带着走：起伏顺挥击方向拉成条纹、幅度变大，挥完慢慢散回乱流。
// flow_align 0..1 由脚本衰减；flow_advect 是脚本累加的位移（米），直接用 TIME 乘会在 align 变化时跳
uniform vec3 flow_dir = vec3(1.0, 0.0, 0.0);
uniform float flow_align : hint_range(0.0, 1.0) = 0.0;
uniform float flow_advect = 0.0;
uniform float flow_align_amp_boost = 2.5;
// 0 = 软膜；1 = 聚合成刃（不起伏、不透明、高光更锐）
uniform float hardness : hint_range(0.0, 1.0) = 0.0;
// 质量偏移（模型空间方向 × 量）：这一侧鼓出去、背面凹进来。0 = 不变形
uniform vec3 stretch_dir = vec3(0.0, 0.0, -1.0);
uniform float stretch_amount = 0.0;
// 背面凹陷相对正面鼓出的比例
uniform float stretch_back_ratio = 0.35;

// —— 刃：从膜上拉出去的舌状突起（模型空间）——
// 方向、伸出长度（米，从膜表面算）
uniform vec3 pod_dir = vec3(0.0, 0.0, -1.0);
uniform float pod_len = 0.0;
// 挥动所绕的轴：刃在垂直于这根轴的平面里挥，所以沿这根轴压扁（刃是扁的，刃口朝运动方向）
uniform vec3 pod_axis = vec3(0.0, 1.0, 0.0);
// 尖端相对根部被甩在后面的角度（弧度，正负表示方向），越往外弯得越多
uniform float pod_bend = 0.0;
// 根部有多宽：膜上离出手方向多少度以内的部分会被拉出去（存余弦）。越小根部越宽、和身体越连成一片
uniform float pod_root_cos = 0.55;
// 越往外越细：尖端的粗细相对根部
uniform float pod_thin : hint_range(0.0, 1.0) = 0.25;
// 沿挥动轴压扁的程度（1 = 压成薄片）
uniform float pod_flat : hint_range(0.0, 1.0) = 0.75;
// 伸出长度沿突起的分布：大于 1 时质量集中在根部，尖端拉得更细长
uniform float pod_profile = 1.4;
// 刃的部分硬化（不透明、少起伏）
uniform float pod_hardness : hint_range(0.0, 1.0) = 0.8;

varying float v_blade;

float wobble(vec3 p, float t) {
    return sin(p.x * flow_scale + t * 1.3)
        * sin(p.y * flow_scale * 1.1 + t * 0.9)
        * sin(p.z * flow_scale * 0.9 + t * 1.7);
}

// 绕单位轴 k 旋转 v（罗德里格斯公式）
vec3 rotate_axis(vec3 v, vec3 k, float a) {
    float c = cos(a);
    float s = sin(a);
    return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

void vertex() {
    vec3 rest = VERTEX;
    float r = length(rest);
    vec3 u = rest / max(r, 0.0001);
    vec3 n = NORMAL;
    vec3 p = rest;

    // 刃：膜上朝出手方向的那一片被拉出去。s = 0 在根部边缘、1 在正中（尖端）
    float s = 0.0;
    if (pod_len > 0.001) {
        s = smoothstep(pod_root_cos, 1.0, dot(u, pod_dir));
        vec3 lat = rest - pod_dir * dot(rest, pod_dir);
        lat -= pod_axis * dot(lat, pod_axis) * pod_flat * s;
        lat *= mix(1.0, pod_thin, s);
        float ext = pod_len * pow(s, pod_profile);
        p = pod_dir * (dot(rest, pod_dir) + ext) + lat;
        // 越往外被甩得越靠后：整根弯成弧，前缘是凸的
        float ang = pod_bend * ext / pod_len;
        p = rotate_axis(p, pod_axis, ang);
        // 法线近似：突起侧面朝外，尖端朝前
        vec3 side = lat + pod_dir * 0.15 * r;
        n = normalize(mix(NORMAL, normalize(side + vec3(1e-5)), s));
        n = rotate_axis(n, pod_axis, ang);
    }
    v_blade = s * step(0.001, pod_len);
    float hard_local = max(hardness, v_blade * pod_hardness);

    // 胞质流动：挥击时顺着 flow_dir 拉成条纹并被带着走，幅度变大
    float t = TIME * flow_speed * (1.0 + flow_align * 2.0);
    vec3 q = rest - flow_dir * dot(rest, flow_dir) * flow_align * 0.8 - flow_dir * flow_advect;
    // 两层不同频率叠加，避免一眼看出是规则的正弦波
    float w = wobble(q, t) + 0.5 * wobble(q * 2.1 + vec3(1.7, 0.3, 2.9), t * 1.6);
    float amp = flow_amplitude * (1.0 + flow_align * flow_align_amp_boost);
    p += n * w * amp * (1.0 - hard_local);

    // 整团质量的偏移：越靠近偏移方向的点被推得越远（平方让鼓包集中），背面整体往里收
    float d = dot(u, stretch_dir);
    float front = max(d, 0.0);
    float back = max(-d, 0.0);
    p += stretch_dir * (front * front - back * stretch_back_ratio) * stretch_amount * r;

    VERTEX = p;
    NORMAL = n;
}

void fragment() {
    float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    // 边缘带宽度 = 若干像素对应的菲涅尔变化量：剪影处菲涅尔变化快 → 带窄而实；
    // 大片掠射表面菲涅尔虽高但变化慢 → 落不进带里，不会整片发亮
    float band = clamp(fwidth(fres) * rim_pixels, 0.005, rim_max_band);
    float top = 0.985;
    float hard = max(hardness, v_blade * pod_hardness);
    float rim = smoothstep(top - band, top - band * 0.3, fres) * mix(1.0, 1.2, hard);
    ALBEDO = base_color.rgb;
    // 边缘处不透明度拉高：剪影是实的，只有中间是透的
    ALPHA = clamp(mix(body_alpha, 1.0, hard) + rim * 0.7, 0.0, 1.0);
    EMISSION = rim_color.rgb * rim * rim_strength;
    ROUGHNESS = mix(0.55, 0.12, hard);
    SPECULAR = mix(0.35, 0.9, hard);
}
