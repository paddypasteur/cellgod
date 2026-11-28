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
// 动画时间（秒），由脚本按游戏时间累加。不用 TIME：TIME 不受命中定格影响，
// 定格时膜还在流动，"定住"那一下就不脆了（DESIGN《受击形变：先脆后晃》第 1 段：纹丝不动）
uniform float anim_time = 0.0;
// 受击形变（HitWobble 写入，模型空间）：接触点、冲击方向、凹陷深度与范围、整体被推开的量与衰减距离
uniform vec3 hit_pos = vec3(0.0);
uniform vec3 hit_dir = vec3(0.0, 0.0, -1.0);
uniform float hit_dent = 0.0;
uniform float hit_dent_radius = 0.4;
uniform float hit_bend = 0.0;
uniform float hit_bend_falloff = 0.6;
// 0 = 软膜；1 = 聚合成刃（不起伏、不透明、高光更锐）
uniform float hardness : hint_range(0.0, 1.0) = 0.0;
// 质量偏移（模型空间方向 × 量）：这一侧鼓出去、背面凹进来。0 = 不变形
uniform vec3 stretch_dir = vec3(0.0, 0.0, -1.0);
uniform float stretch_amount = 0.0;
// 背面凹陷相对正面鼓出的比例
uniform float stretch_back_ratio = 0.35;

// —— 刃：膜上朝出手方向的一片被拉成一把刀（模型空间）——
// 2026-11-28 开发者："本质还是圆锥""特别规则的圆锥""要尽可能去模仿正常的那种冷兵器的样子"。
// 所以刃的形状不再从球面"拉长"出来（那样宽度沿长度匀速变小 = 圆锥），而是直接按刀的轮廓摆顶点：
// 大部分长度几乎等宽、最后一段收尖；截面是扁的透镜形（宽在挥击平面内）；根部一小段从身体平滑过渡
// 方向、伸出长度（米，从膜表面算）
uniform vec3 pod_dir = vec3(0.0, 0.0, -1.0);
uniform float pod_len = 0.0;
// 挥动所绕的轴：刃在垂直于这根轴的平面里挥，刃宽躺在这个平面里
uniform vec3 pod_axis = vec3(0.0, 1.0, 0.0);
// 刀身单向的轻微弯曲（弧度，刃尖处）
uniform float pod_curve = 0.0;
// 膜上离出手方向多少度以内的部分变成刃（存余弦）
uniform float pod_root_cos = 0.3;
// 刃宽（米）、截面厚度 / 宽度
uniform float pod_width = 0.5;
uniform float pod_thickness_ratio = 0.15;
// 从全长的多少开始收窄；收窄之前宽度只收到多少。
// 2026-11-28 开发者："前面不要有一个两个凸出来专门的尖"——末端不汇成尖点，而是越来越薄、渐渐化开（变透明）
uniform float pod_tip_start = 0.7;
uniform float pod_keep_width = 0.9;
// 末端最窄还剩多宽（相对刃宽）：不收到 0，所以没有尖点；剩下的这一截由透明度化掉
uniform float pod_end_width = 0.15;
// 末端从多少开始变透明（相对收窄段：0 = 收窄一开始，1 = 最末端）
uniform float pod_fade_start = 0.35;
// 体积守恒（DESIGN：一体感 = 体积守恒。鼓出去多少，身上就少多少）：
// 刃伸出时身体整体缩小多少（半径比例），刃根周围凹进去多少（半径比例）。脚本按刃伸出的程度给值
uniform float pod_shrink = 0.0;
uniform float pod_dent = 0.0;
// 根部从身体过渡到刃的那一段占全长多少
uniform float pod_root_blend = 0.15;
// 刃的部分硬化（不透明、少起伏）
uniform float pod_hardness : hint_range(0.0, 1.0) = 0.8;

varying float v_blade;
varying float v_fade;

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

    // 刃：t = 0 在根部边缘、1 在末端。膜上的这一片按 t 重新摆成刃的形状
    float s = 0.0;
    v_fade = 1.0;
    if (pod_len > 0.001) {
        float t = smoothstep(pod_root_cos, 1.0, dot(u, pod_dir));
        s = t;
        // 截面坐标：x 沿刃宽（挥击平面内），y 沿厚度（挥动轴）
        vec3 ew = normalize(cross(pod_axis, pod_dir));
        vec3 lat = rest - pod_dir * dot(rest, pod_dir);
        vec2 c = vec2(dot(lat, ew), dot(lat, pod_axis));
        vec2 cn = length(c) > 1e-5 ? normalize(c) : vec2(0.0);
        // 轮廓：几乎等宽；末段沿一条平滑曲线收窄（收窄到头时两边是平行的，不形成尖角），
        // 收到 pod_end_width 为止，再往外由透明度化掉。刃很短（刚伸出 / 快收回）时宽度跟着缩，不留一块方板
        float x = clamp((t - pod_tip_start) / (1.0 - pod_tip_start), 0.0, 1.0);
        float w = t < pod_tip_start
            ? mix(1.0, pod_keep_width, t / pod_tip_start)
            : pod_keep_width * mix(1.0, pod_end_width, smoothstep(0.0, 1.0, x));
        float hw = 0.5 * pod_width * w * clamp(pod_len / 1.0, 0.3, 1.0);
        // 两侧都薄：透镜形截面，越往末端越薄
        float ht = hw * pod_thickness_ratio * (1.0 - 0.7 * x);
        float along = mix(r * 0.35, r + pod_len, t);
        vec3 blade = pod_dir * along + ew * (hw * cn.x) + pod_axis * (ht * cn.y * (1.0 - 0.3 * abs(cn.x)));
        v_fade = 1.0 - smoothstep(pod_fade_start, 1.0, x);
        // 体积守恒：身体整体缩一圈，刃根周围再凹进去一圈（刃就是从这里抽走的物质）
        float near_root = smoothstep(pod_root_cos - 0.6, pod_root_cos, dot(u, pod_dir));
        vec3 body = rest * (1.0 - pod_shrink) - u * r * pod_dent * near_root;
        // 根部一小段从（缩过的）身体平滑过渡到刃
        float b = smoothstep(0.0, pod_root_blend, t);
        p = mix(body, blade, b);
        // 单向轻微弯曲，越往刃尖越弯
        float ang = pod_curve * t * t;
        p = rotate_axis(p, pod_axis, ang);
        // 扁截面的法线：宽面朝挥动轴方向，刃口朝两侧
        vec3 nb = normalize(ew * cn.x * pod_thickness_ratio + pod_axis * cn.y + pod_dir * 0.02);
        n = normalize(mix(NORMAL, nb, b));
        n = rotate_axis(n, pod_axis, ang);
    }
    v_blade = s * step(0.001, pod_len);
    float hard_local = max(hardness, v_blade * pod_hardness);

    // 胞质流动：挥击时顺着 flow_dir 拉成条纹并被带着走，幅度变大
    float t = anim_time * flow_speed * (1.0 + flow_align * 2.0);
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

    // 受击：接触点凹进去；整条被推开，离接触点越远越跟不上 → 绕命中点弓起。
    // 弯的衰减只按"垂直于冲击方向"的距离算：同一截身体（沿冲击方向的整个厚度）一起移动，所以是弯，不是被挤扁。
    // 杆状的敌人因此弯腰；圆的敌人中间被推得多、边缘少 → 压成碗状。同一条规则，形状不同反应自然不同
    if (hit_dent > 0.0001 || abs(hit_bend) > 0.0001) {
        vec3 dv = rest - hit_pos;
        float d2 = dot(dv, dv);
        p += hit_dir * hit_dent * exp(-d2 / (hit_dent_radius * hit_dent_radius));
        vec3 dp = dv - hit_dir * dot(dv, hit_dir);
        p += hit_dir * hit_bend * exp(-dot(dp, dp) / (hit_bend_falloff * hit_bend_falloff));
    }

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
    ALPHA = clamp(mix(body_alpha, 1.0, hard) + rim * 0.7, 0.0, 1.0) * v_fade;
    EMISSION = rim_color.rgb * rim * rim_strength * v_fade;
    ROUGHNESS = mix(0.55, 0.12, hard);
    SPECULAR = mix(0.35, 0.9, hard);
}
