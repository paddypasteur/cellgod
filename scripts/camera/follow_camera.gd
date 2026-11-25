class_name FollowCamera
extends Camera3D
## 跟随镜头。右摇杆手动转镜头，松手一段时间后恢复自动朝移动方向回正。
## 铁律：永远不 roll。所有朝向都用 look_at(..., Vector3.UP) 生成，
## 俯仰角也夹在 ±80° 以内，避免接近竖直时 look_at 退化。

@export var target: CharacterBody3D

@export_group("距离与角度")
## 镜头到注视点的距离
@export var distance: float = 7.0
## 俯仰角。负数 = 从上往下看。运行中拖动会立刻覆盖右摇杆转出来的角度
@export_range(-80.0, 80.0) var pitch_deg: float = -15.0:
    set(value):
        pitch_deg = value
        # 手动控制改的是 _pitch_deg，所以检查器里的改动必须同步过去，否则运行时拖动无效
        _pitch_deg = value
## 注视点比主角高多少。越大主角越靠画面下方，上方视野越多
@export var look_height_offset: float = 0.8
## 肩后偏移（米）。镜头和注视点一起沿镜头右方平移，视线方向不变，
## 主角因此偏到画面一侧，朝前打的伪足不再被自己的身体挡住。
## 正数 = 镜头在主角右后方（主角偏画面左侧）；负数反之；0 = 正后方
@export var shoulder_offset: float = 0.0

@export_group("跟随")
## 位置跟随响应。越大越紧，越小越"拖"
@export var position_follow_rate: float = 10.0
## 镜头朝移动方向回正的速度。0 = 镜头水平朝向永远固定
@export var yaw_follow_rate: float = 1.2
## 水平速度低于此值时不回正，避免微小移动带着镜头乱转
@export var yaw_follow_min_speed: float = 1.5

@export_group("右摇杆手动控制")
## 水平转动速度（度/秒，摇杆推满时）
@export var stick_yaw_speed_deg: float = 180.0
## 俯仰转动速度（度/秒，摇杆推满时）
@export var stick_pitch_speed_deg: float = 90.0
## 反转上下
@export var invert_pitch: bool = false
## 手动俯仰的下限/上限（度）。整体还会再夹在 ±80° 内防止 look_at 退化
@export_range(-80.0, 80.0) var pitch_min_deg: float = -60.0
@export_range(-80.0, 80.0) var pitch_max_deg: float = 40.0
## 右摇杆死区
@export_range(0.0, 0.9) var stick_deadzone: float = 0.2
## 松开右摇杆多久后，自动回正才重新生效（秒）。避免刚转好的镜头被立刻拉回去
@export var auto_follow_resume_delay: float = 1.0

var _yaw: float = 0.0
var _pitch_deg: float = 0.0
var _pivot: Vector3 = Vector3.ZERO
var _manual_cooldown: float = 0.0


func _ready() -> void:
    var f: Vector3 = -global_basis.z
    _yaw = atan2(-f.x, -f.z)
    _pitch_deg = pitch_deg
    if target != null:
        _pivot = target.global_position
    _apply()


# 放在物理帧里，和主角的移动同步，避免两者错帧产生的抖动；
# 命中定格冻结物理时镜头也随之冻结，这正是想要的效果
func _physics_process(delta: float) -> void:
    if target == null:
        return
    _pivot = _pivot.lerp(target.global_position, 1.0 - exp(-position_follow_rate * delta))
    _update_manual(delta)
    _update_yaw(delta)
    _apply()


func _update_manual(delta: float) -> void:
    _manual_cooldown = maxf(_manual_cooldown - delta, 0.0)
    var stick: Vector2 = Input.get_vector(&"camera_left", &"camera_right", &"camera_down", &"camera_up", stick_deadzone)
    if stick == Vector2.ZERO:
        return
    _manual_cooldown = auto_follow_resume_delay
    # 摇杆往右推 = 镜头往右看 = yaw 减小（yaw 正方向是从上往下看逆时针）
    _yaw -= deg_to_rad(stick_yaw_speed_deg) * stick.x * delta
    var pitch_sign: float = -1.0 if invert_pitch else 1.0
    _pitch_deg += stick_pitch_speed_deg * stick.y * pitch_sign * delta
    _pitch_deg = clampf(_pitch_deg, pitch_min_deg, pitch_max_deg)


func _update_yaw(delta: float) -> void:
    if yaw_follow_rate <= 0.0 or _manual_cooldown > 0.0:
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
    var pitch: float = deg_to_rad(clampf(_pitch_deg, -80.0, 80.0))
    var orbit: Basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, pitch)
    # orbit.x 是镜头右方；绕 X 轴的俯仰不改变它，所以它始终水平，平移不会带来 roll
    var look_point: Vector3 = _pivot + Vector3.UP * look_height_offset + orbit.x * shoulder_offset
    global_position = look_point + orbit * Vector3(0.0, 0.0, distance)
    look_at(look_point, Vector3.UP)
