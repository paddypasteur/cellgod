extends MultiMeshInstance3D
## 竞技场里缓慢漂移的小颗粒。无重力环境里玩家需要"空气里有东西"才能感知自己的速度和位置：
## 自己动的时候颗粒往后流，停下来时颗粒几乎不动。
## 只是显示：没有碰撞、不进 target 组、不参与索敌（靶子就是因为参与索敌才被撤掉的）。
## 用 MultiMesh 一次画完，几百个颗粒也只占一次绘制。

## 颗粒数量
@export var count: int = 600
## 漂移速度（米/秒）。要慢：快了会被读成"有东西在动"，抢敌人的注意力
@export var drift_speed: float = 0.25
## 颗粒大小范围（直径，米）
@export var size_min: float = 0.04
@export var size_max: float = 0.09
@export var color: Color = Color(1.0, 0.85, 0.85)
## 分布半径。父节点有 radius 属性（Arena）时自动取它，略小一点免得贴在边界上
@export var radius: float = 19.5

var _positions: PackedVector3Array = PackedVector3Array()
var _velocities: PackedVector3Array = PackedVector3Array()
var _sizes: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
    var parent_radius: Variant = get_parent().get("radius")
    if parent_radius != null:
        radius = float(parent_radius) - 0.5
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    var mesh := SphereMesh.new()
    mesh.radius = 0.5
    mesh.height = 1.0
    # 颗粒很小，面数压到最低
    mesh.radial_segments = 6
    mesh.rings = 3
    mesh.material = material

    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = count

    _positions.resize(count)
    _velocities.resize(count)
    _sizes.resize(count)
    for i: int in count:
        # 开立方根让颗粒在球体积里均匀分布，而不是挤在球心
        _positions[i] = _random_unit() * radius * pow(randf(), 1.0 / 3.0)
        _velocities[i] = _random_unit() * drift_speed * randf_range(0.5, 1.0)
        _sizes[i] = randf_range(size_min, size_max)


func _process(delta: float) -> void:
    for i: int in count:
        var p: Vector3 = _positions[i] + _velocities[i] * delta
        # 飘出边界就从对面重新进来，总数和密度保持不变
        if p.length() > radius:
            p = -p * 0.98
        _positions[i] = p
        multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * _sizes[i]), p))


static func _random_unit() -> Vector3:
    var v := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
    while v.length_squared() < 0.0001 or v.length_squared() > 1.0:
        v = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
    return v.normalized()
