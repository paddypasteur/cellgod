class_name HitFx
extends Node3D
## 命中特效（白盒版）：**沿刃的轨迹切开 → 胞质朝挥击的反方向喷出 → 膜口回缩**。
## 不用通用火花：这个世界里被砍中意味着膜破裂、胞质外泄，
## 和序章里大块头那具"从内部撑破"的空皮是同一套视觉语言（DESIGN《打击感的投资顺序》）。
## 全部是纯色几何体，没有贴图。命中定格时全局时间冻结，特效也跟着停在那一帧——这正是想要的。

const CUT_TIME: float = 0.12


## spray_dir：胞质喷出的主方向（单位向量）；slash_dir：刃在命中点的运动方向（切口沿它展开）
static func spawn(parent: Node, at: Vector3, spray_dir: Vector3, slash_dir: Vector3, tier: HitTier,
        cytoplasm_color: Color, membrane_color: Color) -> void:
    if parent == null or tier == null:
        return
    var fx := HitFx.new()
    parent.add_child(fx)
    fx.global_position = at
    fx._build(spray_dir.normalized(), slash_dir.normalized(), tier, cytoplasm_color, membrane_color)


func _build(spray_dir: Vector3, slash_dir: Vector3, tier: HitTier, cyto: Color, membrane: Color) -> void:
    var life: float = maxf(tier.particle_lifetime, maxf(tier.membrane_time, CUT_TIME))
    if tier.particle_amount > 0:
        _spawn_droplets(spray_dir, tier, cyto)
    if tier.membrane_time > 0.0:
        _spawn_membrane_ring(spray_dir, tier, membrane)
    _spawn_cut(slash_dir, membrane)
    # 计时器跟着游戏时间走：命中定格冻结时特效不会提前消失
    get_tree().create_timer(life + 0.2, false).timeout.connect(queue_free)


## 胞质飞沫：一次性喷出，无重力（体内没有"下"），靠阻尼减速，越飞越小
func _spawn_droplets(spray_dir: Vector3, tier: HitTier, color: Color) -> void:
    var p := CPUParticles3D.new()
    p.one_shot = true
    p.explosiveness = 1.0
    p.amount = tier.particle_amount
    p.lifetime = tier.particle_lifetime
    p.local_coords = false
    p.direction = spray_dir
    p.spread = 35.0
    p.initial_velocity_min = tier.particle_speed * 0.5
    p.initial_velocity_max = tier.particle_speed
    p.gravity = Vector3.ZERO
    p.damping_min = tier.particle_speed * 2.0
    p.damping_max = tier.particle_speed * 3.0
    p.scale_amount_min = 0.6
    p.scale_amount_max = 1.2
    var shrink := Curve.new()
    shrink.add_point(Vector2(0.0, 1.0))
    shrink.add_point(Vector2(1.0, 0.0))
    p.scale_amount_curve = shrink
    var mesh := SphereMesh.new()
    mesh.radius = tier.particle_size * 0.5
    mesh.height = tier.particle_size
    mesh.radial_segments = 6
    mesh.rings = 3
    mesh.material = _unshaded(color)
    p.mesh = mesh
    add_child(p)
    p.emitting = true


## 膜口：命中处一圈膜，从张开回缩到闭合
func _spawn_membrane_ring(normal: Vector3, tier: HitTier, color: Color) -> void:
    var torus := TorusMesh.new()
    torus.inner_radius = 0.28
    torus.outer_radius = 0.4
    torus.rings = 16
    torus.ring_segments = 4
    torus.material = _unshaded(color)
    var ring := MeshInstance3D.new()
    ring.mesh = torus
    ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(ring)
    # 环面朝喷出方向（圆环默认躺在 XZ 平面，法线是 Y）
    ring.basis = _basis_y_to(normal)
    ring.scale = Vector3.ONE * 1.6
    create_tween().tween_property(ring, "scale", Vector3.ONE * 0.1, tier.membrane_time) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## 切口：沿刃运动方向的一道细线，很快收窄消失
func _spawn_cut(slash_dir: Vector3, color: Color) -> void:
    var box := BoxMesh.new()
    box.size = Vector3(0.04, 0.9, 0.04)
    box.material = _unshaded(color.lightened(0.4))
    var cut := MeshInstance3D.new()
    cut.mesh = box
    cut.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(cut)
    cut.basis = _basis_y_to(slash_dir)
    create_tween().tween_property(cut, "scale", Vector3(0.1, 1.2, 0.1), CUT_TIME)


static func _unshaded(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = color
    return m


static func _basis_y_to(dir: Vector3) -> Basis:
    var d: Vector3 = dir.normalized()
    if d.length_squared() < 0.0001:
        return Basis.IDENTITY
    if d.dot(Vector3.UP) < -0.9999:
        return Basis(Vector3.RIGHT, PI)
    return Basis(Quaternion(Vector3.UP, d))
