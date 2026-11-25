class_name TrainingDummy
extends StaticBody3D
## 不动的靶子。只用来验证命中和打击感，不是敌人原型。
## 原型阶段不做敌人 AI，见 CLAUDE.md "不要提前加内容"。

## 受击闪烁颜色
@export var flash_color: Color = Color(1.0, 0.35, 0.25)
## 闪烁、回弹持续时间（秒）
@export var flash_time: float = 0.18
## 蓄满一击时受击膨胀的最大倍率，轻击约 1.1
@export var punch_scale: float = 1.3

var hit_count: int = 0

var _material: StandardMaterial3D
var _base_color: Color = Color.WHITE

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
    add_to_group(&"target")
    # 复制一份材质，否则所有靶子共用一个材质，打一个全部一起闪
    var source := _mesh.get_active_material(0) as StandardMaterial3D
    if source != null:
        _material = source.duplicate() as StandardMaterial3D
        _mesh.material_override = _material
        _base_color = _material.albedo_color


func take_hit(strength: float, _direction: Vector3) -> void:
    hit_count += 1
    if _material != null:
        _material.albedo_color = flash_color
        create_tween().tween_property(_material, "albedo_color", _base_color, flash_time)
    _mesh.scale = Vector3.ONE * lerpf(1.1, punch_scale, strength)
    create_tween().tween_property(_mesh, "scale", Vector3.ONE, flash_time) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
