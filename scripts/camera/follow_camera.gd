class_name FollowCamera
extends Camera3D
## 自动跟随镜头。右摇杆完全让给攻击，所以镜头不吃手动输入。
## 铁律：永远不 roll。所有朝向都用 look_at(..., Vector3.UP) 生成，
## 俯仰角也夹在 ±80° 以内，避免接近竖直时 look_at 退化。

@export var target: CharacterBody3D

@export_group("距离与角度")
## 镜头到注视点的距离
@export var distance: float = 7.0
## 俯仰角。负数 = 从上往下看
@export_range(-80.0, 80.0) var pitch_deg: float = -15.0
## 注视点比主角高多少。越大主角越靠画面下方，上方视野越多
@export var look_height_offset: float = 0.8

@export_group("跟随")
## 位置跟随响应。越大越紧，越小越"拖"
@export var position_follow_rate: float = 10.0
## 镜头朝移动方向回正的速度。0 = 镜头水平朝向永远固定
@export var yaw_follow_rate: float = 1.2
## 水平速度低于此值时不回正，避免微小移动带着镜头乱转
@export var yaw_follow_min_speed: float = 1.5

var _yaw: float = 0.0
var _pivot: Vector3 = Vector3.ZERO


func _ready() -> void:
    var f: Vector3 = -global_basis.z
    _yaw = atan2(-f.x, -f.z)
    if target != null:
        _pivot = target.global_position
    _apply()


# 放在物理帧里，和主角的移动同步，避免两者错帧产生的抖动；
# 命中定格冻结物理时镜头也随之冻结，这正是想要的效果
func _physics_process(delta: float) -> void:
    if target == null:
        return
    _pivot = _pivot.lerp(target.global_position, 1.0 - exp(-position_follow_rate * delta))
    _update_yaw(delta)
    _apply()


func _update_yaw(delta: float) -> void:
    if yaw_follow_rate <= 0.0:
        return
    var v: Vector3 = target.velocity
    v.y = 0.0
    var speed: float = v.length()
    if speed < yaw_follow_min_speed:
        return
    var desired: float = atan2(-v.x, -v.z)
    # 朝镜头方向后退时不回正，否则镜头会绕着主角甩 180°
    var cam_fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
    var toward_camera: float = maxf(0.0, -cam_fwd.dot(v / speed))
    var weight: float = 1.0 - toward_camera
    _yaw = lerp_angle(_yaw, desired, (1.0 - exp(-yaw_follow_rate * delta)) * weight)


func _apply() -> void:
    var pitch: float = deg_to_rad(clampf(pitch_deg, -80.0, 80.0))
    var orbit: Basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, pitch)
    var look_point: Vector3 = _pivot + Vector3.UP * look_height_offset
    global_position = look_point + orbit * Vector3(0.0, 0.0, distance)
    look_at(look_point, Vector3.UP)
