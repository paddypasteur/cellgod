class_name HitFx
extends Node3D
## 命中特效（白盒版）：**切口 + 胞质从被打穿的另一侧迸出 → 在体液里被迅速拖停 → 缓缓飘一会儿 → 淡掉**。
## DESIGN《粒子：方向、减速、永存》（2026-11-28）：
##   - 不要环：环形表示钝器 / 爆炸那种没有方向的冲击（开发者："它是一个圆环，像钝器打在那上面"）
##   - 沿冲击方向、从被击中物体的另一侧迸出（开发者 11-28："穿过去从另一侧迸出"）
##   - 指数减速后停住：整个游戏在体液里，飞出去的东西本就该被黏滞介质迅速拖停，不能匀速飞走再啪地消失
##   - 停下之后缓缓飘一会儿再淡（Vlambeer 的"永存"）
##   - 随机：尺寸 ±20%、速度 ±30%、朝向随机
## 数量、初速、尺寸、存活时间都来自 HitTier（冲击系统的主强度）。
## 用 _process 自己推，命中定格时全局时间冻结，delta = 0，粒子也停在那一帧——这正是想要的

const CUT_TIME: float = 0.12
## 黏滞：速度每秒衰减到 exp(-DRAG) 倍。8 ≈ 0.3 秒内基本停住
const DRAG: float = 8.0
## 停下之后的漂浮速度（米/秒）
const DRIFT_SPEED: float = 0.15
## 存活时间的最后这么多比例用来淡出
const FADE_PART: float = 0.45

var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _drift: PackedVector3Array = PackedVector3Array()
var _basis: Array[Basis] = []
var _life: PackedFloat32Array = PackedFloat32Array()
var _age: float = 0.0
var _mm: MultiMesh = null
var _color: Color = Color.WHITE


## at：迸出的位置（被击中物体朝冲击方向的那一侧表面）；impulse_dir：冲击方向（刃的运动方向）；
## slash_dir：切口沿它展开
static func spawn(parent: Node, at: Vector3, impulse_dir: Vector3, slash_dir: Vector3, tier: HitTier,
        cytoplasm_color: Color, membrane_color: Color) -> void:
    if parent == null or tier == null:
        return
    var fx := HitFx.new()
    parent.add_child(fx)
    fx.global_position = at
    fx._build(impulse_dir.normalized(), slash_dir.normalized(), tier, cytoplasm_color, membrane_color)


func _build(impulse_dir: Vector3, slash_dir: Vector3, tier: HitTier, cyto: Color, membrane: Color) -> void:
    _spawn_cut(slash_dir, membrane)
    var count: int = tier.get_particle_count()
    if count <= 0:
        _finish_after(CUT_TIME + 0.2)
        return
    _color = cyto
    var size: float = tier.get_particle_size()
    var speed: float = tier.get_particle_speed()
    var life: float = tier.get_particle_life()
    var drop := SphereMesh.new()
    drop.radius = size * 0.5
    drop.height = size
    drop.radial_segments = 8
    drop.rings = 4
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.vertex_color_use_as_albedo = true
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    drop.material = m
    _mm = MultiMesh.new()
    _mm.transform_format = MultiMesh.TRANSFORM_3D
    _mm.use_colors = true
    _mm.mesh = drop
    _mm.instance_count = count
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = _mm
    mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mmi)
    # 粒子用世界坐标模拟，节点本身放在原点
    mmi.top_level = true
    var side_a: Vector3 = impulse_dir.cross(Vector3.UP)
    if side_a.length_squared() < 0.01:
        side_a = impulse_dir.cross(Vector3.RIGHT)
    side_a = side_a.normalized()
    var side_b: Vector3 = impulse_dir.cross(side_a).normalized()
    for i: int in count:
        # 锥形散开（约 35°），速度 ±30%，大小 ±20%（压成略扁的椭球，朝向随机才看得出来）
        var spread: float = deg_to_rad(35.0) * sqrt(randf())
        var around: float = randf() * TAU
        var dir: Vector3 = (impulse_dir * cos(spread)
            + (side_a * cos(around) + side_b * sin(around)) * sin(spread)).normalized()
        _pos.append(global_position)
        _vel.append(dir * speed * randf_range(0.7, 1.3))
        _drift.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * DRIFT_SPEED * randf_range(0.5, 1.0))
        var s: float = randf_range(0.8, 1.2)
        var rot := Basis(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(), randf() * TAU)
        _basis.append(rot * Basis.from_scale(Vector3(s, s * randf_range(0.6, 1.0), s)))
        _life.append(life * randf_range(0.7, 1.3))
    _write()
    _finish_after(life * 1.3 + 0.2)


func _process(delta: float) -> void:
    if _mm == null or delta <= 0.0:
        return
    _age += delta
    var keep: float = exp(-DRAG * delta)
    for i: int in _pos.size():
        _vel[i] = _vel[i] * keep
        # 冲出去的速度被拖到很小之后，接上一点慢慢的漂浮
        _pos[i] += (_vel[i] + _drift[i] * (1.0 - minf(_vel[i].length() / 1.0, 1.0))) * delta
    _write()


func _write() -> void:
    for i: int in _pos.size():
        var fade_start: float = _life[i] * (1.0 - FADE_PART)
        var a: float = 1.0 - clampf((_age - fade_start) / maxf(_life[i] * FADE_PART, 0.001), 0.0, 1.0)
        _mm.set_instance_transform(i, Transform3D(_basis[i], _pos[i]))
        _mm.set_instance_color(i, Color(_color, 0.9 * a))


## 计时器跟着游戏时间走：命中定格冻结时特效不会提前消失
func _finish_after(seconds: float) -> void:
    get_tree().create_timer(seconds, false).timeout.connect(queue_free)


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
    create_tween().tween_callback(cut.queue_free).set_delay(CUT_TIME)


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
