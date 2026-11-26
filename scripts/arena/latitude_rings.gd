extends Node3D
## 竞技场内壁上的纬线环：每隔一段高度画一圈很淡的水平环，像地球仪的纬线。
## 解决开发者说的"不知道自己在哪一层"：看自己和哪一圈齐平就知道高度，
## 上升下降时能看到环一圈圈掠过；比自己那圈高的敌人就是比自己高。
## 全画在墙上，交战区里不新增任何物体，所以不会"乱"（之前的 B 方案就是因为满场竖线才乱）。
## 也是为正式版打样：血管壁、组织表面本来就该有这样的结构纹理。

## 两圈之间的高度间隔（米）
@export var spacing: float = 2.5
## 环线粗细（米）
@export var thickness: float = 0.06
## 普通环的不透明度
@export_range(0.0, 1.0) var opacity: float = 0.25
## 赤道（y = 竞技场中心高度）那一圈的不透明度，给整个空间一个"零层"
@export_range(0.0, 1.0) var equator_opacity: float = 0.6
@export var color: Color = Color(1.0, 0.9, 0.9)
## 环离球壁往里缩多少（米），避免和半透明边界球面重叠闪烁
@export var inset: float = 0.1
## 竞技场半径。父节点有 radius 属性（Arena）时自动取它
@export var radius: float = 20.0


func _ready() -> void:
    var parent_radius: Variant = get_parent().get("radius")
    if parent_radius != null:
        radius = float(parent_radius)
    _build()


func _build() -> void:
    for child: Node in get_children():
        child.queue_free()
    var normal := _make_material(opacity)
    var equator := _make_material(equator_opacity)
    # 从赤道往上下对称地铺，保证赤道一定有一圈
    var count: int = int(floor((radius - spacing * 0.5) / spacing))
    for i: int in range(-count, count + 1):
        var y: float = i * spacing
        var ring_radius: float = sqrt(maxf(radius * radius - y * y, 0.0)) - inset
        if ring_radius < 1.0:
            continue
        var torus := TorusMesh.new()
        torus.inner_radius = ring_radius - thickness
        torus.outer_radius = ring_radius + thickness
        # 环很大、管很细：沿环方向多分段，管截面少分段
        torus.rings = 96
        torus.ring_segments = 4
        var ring := MeshInstance3D.new()
        ring.mesh = torus
        ring.material_override = equator if i == 0 else normal
        ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        ring.position = Vector3(0.0, y, 0.0)
        add_child(ring)


func _make_material(alpha: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.albedo_color = Color(color, alpha)
    return m
