class_name Player
extends CharacterBody3D
## 原型主角：无定形免疫细胞。
## 身体永远不转向，攻击方向只由瞄准输入决定，和移动方向完全无关。
## 这就是"攻击方向与身体朝向解耦"这条机制本身。

signal hit_landed(target: Node, charge: float)

enum PodState { IDLE, CHARGING, EXTENDING, HOLDING, RETRACTING }

## 攻击方向的输入方案。方案未定，三种都保留，运行时在检查器里切换对比
enum AimMode {
    RIGHT_STICK,     ## 0 = 右摇杆/鼠标瞄准，镜头不吃右摇杆
    MOVE_DIRECTION,  ## 1 = 朝移动输入的方向，回中时朝镜头前方
    CAMERA_FORWARD,  ## 2 = 永远朝镜头水平前方（传统类魂），上下靠吸附或升降
    CAMERA_LOOK,     ## 3 = 永远朝镜头实际朝向（含俯仰），右摇杆上下即可往上下打
    SOULS,           ## 4 = 类魂：身体有正面，转向移动方向，攻击永远朝正面
}

@export_group("移动")
## 最大悬浮速度（米/秒）
@export var max_speed: float = 7.0
## 有输入时的加速响应。越大越跟手，越小越"滑"
@export var acceleration: float = 10.0
## 松开输入后的减速响应。越大停得越快
@export var deceleration: float = 6.0
## 上升/下降速度相对水平速度的比例
@export_range(0.0, 2.0) var vertical_speed_scale: float = 0.8

@export_group("瞄准")
## 攻击方向由什么决定。运行中可在远程检查器里改，下一帧生效。
## 选 0 时右摇杆归瞄准；选 1/2/3/4 时右摇杆归镜头
@export var aim_mode: AimMode = AimMode.SOULS
## （模式 0）右摇杆（或鼠标偏移）推满时，攻击方向偏离"水平前方"多少度。
## 90 = 推满指向正侧/正上/正下；180 = 推满指向正后方。
## 这是把二维摇杆映射到三维方向的临时方案，方案本身未定。
@export_range(30.0, 180.0) var aim_max_tilt_deg: float = 120.0
## 右摇杆死区
@export_range(0.0, 0.9) var aim_stick_deadzone: float = 0.25
## 摇杆回中后：true = 瞄准回到镜头前方；false = 保持最后一次的方向
@export var aim_neutral_returns_forward: bool = false
## （键鼠临时方案）鼠标离主角屏幕位置多少像素算"推满"
@export var mouse_aim_radius_px: float = 300.0
## 瞄准吸附：攻击方向与目标夹角小于此值时直接对准目标。0 = 关闭
@export_range(0.0, 45.0) var aim_assist_angle_deg: float = 12.0

@export_group("类魂朝向（模式 4）")
## 待机/移动时身体转向的速度（度/秒）
@export var turn_speed_deg: float = 720.0
## 蓄力期间还能慢慢修正朝向的速度（度/秒）。0 = 蓄力时完全锁死
@export var charge_turn_speed_deg: float = 180.0
## 按下攻击时若推着方向，立刻转过去再出招（类魂的"按方向+攻击"）
@export var snap_facing_on_attack: bool = true
## 朝向最多能抬头/低头多少度。上升/下降输入会让正面倾斜，0 = 正面永远水平
@export_range(0.0, 89.0) var facing_max_pitch_deg: float = 60.0

@export_group("类魂 · 上下方向（模式 4，三个开关可任意组合）")
## 开关 1：攻击的上下角度跟随镜头俯仰。右摇杆往上看，伪足就往上打
@export var vertical_from_camera: bool = true
## 镜头每偏离默认俯仰 1°，攻击抬高/压低多少度
@export_range(0.0, 2.0) var camera_pitch_follow_ratio: float = 1.0
## 镜头俯仰在默认值附近多少度内不影响攻击，免得轻碰右摇杆攻击就歪
@export_range(0.0, 30.0) var camera_pitch_deadzone_deg: float = 5.0
## 开关 2：不对称吸附。水平窄（保住"朝正面打"），上下宽（高低交给游戏找）。
## 关闭时退回上面"瞄准"分组里的对称吸附
@export var vertical_assist_enabled: bool = true
## 不对称吸附的水平容差（度）
@export_range(0.0, 45.0) var assist_horizontal_deg: float = 12.0
## 不对称吸附的上下容差（度）
@export_range(0.0, 89.0) var assist_vertical_deg: float = 60.0
## 开关 3：方向攻击。按住上升/下降键出招 = 上挑/下砸（丝之歌式），优先于开关 1
@export var directional_attacks: bool = false
## 上挑/下砸的角度（度）。90 = 正上/正下
@export_range(0.0, 90.0) var directional_attack_pitch_deg: float = 70.0
## 方向攻击开启时，出招期间升降键只管方向，不再让身体上下移动
@export var directional_locks_vertical_move: bool = true

@export_group("伪足 · 长度与蓄力")
## 轻点时伸出的长度（从膜表面算起，米）
@export var pod_min_length: float = 1.5
## 蓄满时伸出的长度
@export var pod_max_length: float = 7.0
## 从开始按住到蓄满所需时间（秒）
@export var charge_time_to_max: float = 0.6
## 按住时间短于此值就松开，算轻点（最短伪足、零蓄力）
@export var tap_threshold: float = 0.1

@export_group("伪足 · 时序")
## 伸出速度（米/秒）。实际速度按蓄力在短/长之间插值：长伪足伸得慢
@export var extend_speed_short: float = 45.0
@export var extend_speed_long: float = 25.0
## 伸到头后停留的时间（秒）。长伪足停得久 = 破绽大
@export var hold_time_short: float = 0.03
@export var hold_time_long: float = 0.25
## 收回速度（米/秒）
@export var retract_speed_short: float = 40.0
@export var retract_speed_long: float = 14.0
## 收回过程中提前按下的攻击会被记住多久（秒），收完立刻开始下一次蓄力
@export var input_buffer_time: float = 0.15

@export_group("伪足 · 风险")
## 蓄力期间的移动速度倍率
@export_range(0.0, 1.0) var move_scale_charging: float = 0.6
## 伪足伸出期间（伸、停、收）的移动速度倍率，按蓄力在短/长之间插值
@export_range(0.0, 1.0) var move_scale_extended_short: float = 0.8
@export_range(0.0, 1.0) var move_scale_extended_long: float = 0.2

@export_group("伪足 · 命中")
## 伪足尖端的判定半径
@export var pod_tip_radius: float = 0.35
## 命中定格时长（秒），按蓄力在轻/重之间插值。重击多冻几帧
@export var hitstop_light: float = 0.05
@export var hitstop_heavy: float = 0.14
## 伪足能打到的物理层
@export_flags_3d_physics var hit_mask: int = 2

@export_group("显示")
## 身体半径。要和碰撞形状、身体网格保持一致
@export var body_radius: float = 0.5
## 蓄力时显示一条细线，预告伪足能伸多远
@export var show_reach_preview: bool = true
## 蓄满时膜鼓起部分沿攻击方向拉长到多少（相对身体直径）
@export var bulge_max_stretch: float = 1.2

## 竞技场边界由 Arena 在运行时写入，不在这里调
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 20.0

var _pod_state: PodState = PodState.IDLE
var _charge_time: float = 0.0
var _hold_timer: float = 0.0
var _buffer_timer: float = 0.0

## 当前瞄准方向（已含吸附），世界空间单位向量
var _aim_dir: Vector3 = Vector3.FORWARD
var _aim_from_mouse: bool = false

## 身体正面（模式 4 用）。存成偏航+俯仰两个角而不是向量，
## 这样转身用 rotate_toward 就不会遇到"正好转 180°时方向不确定"的问题
var _facing_yaw: float = 0.0
var _facing_pitch: float = 0.0
var _last_stick: Vector2 = Vector2.ZERO

## 本次攻击在松手时锁定的参数
var _attack_dir: Vector3 = Vector3.FORWARD
var _attack_charge: float = 0.0
var _target_length: float = 0.0
## 当前伪足从膜表面伸出的长度
var _pod_length: float = 0.0

var _tip_shape: SphereShape3D = SphereShape3D.new()
var _tip_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()

@onready var _pod_mesh: MeshInstance3D = $Pseudopod
@onready var _bulge_mesh: MeshInstance3D = $Bulge
@onready var _aim_marker: MeshInstance3D = $AimMarker
@onready var _reach_preview: MeshInstance3D = $ReachPreview
@onready var _facing_pivot: Node3D = $Facing


func _ready() -> void:
    _tip_query.shape = _tip_shape
    _tip_query.collide_with_bodies = true
    _tip_query.collide_with_areas = false
    _tip_query.exclude = [get_rid()]


func _unhandled_input(event: InputEvent) -> void:
    # 按下事件走 _unhandled_input 而不是在物理帧里轮询 just_pressed：
    # 命中定格时物理帧暂停，轮询会漏掉定格期间的按键
    if event.is_action_pressed(&"pseudopod"):
        _buffer_timer = input_buffer_time
    elif event is InputEventMouseMotion:
        # 小幅抖动不算切换设备，免得手柄玩家碰一下鼠标瞄准就跳
        if (event as InputEventMouseMotion).relative.length() > 2.0:
            _aim_from_mouse = true


func _physics_process(delta: float) -> void:
    _update_facing(delta)
    _update_aim()
    _update_pseudopod(delta)
    _update_movement(delta)
    _update_visuals()


# ---------------------------------------------------------------- 瞄准

func _update_aim() -> void:
    if aim_mode == AimMode.SOULS:
        _aim_dir = _souls_aim()
        return
    var raw_dir: Vector3
    match aim_mode:
        AimMode.RIGHT_STICK:
            raw_dir = _right_stick_aim()
        AimMode.MOVE_DIRECTION:
            raw_dir = _move_direction_aim()
        AimMode.CAMERA_LOOK:
            raw_dir = _camera_look_forward()
        _:
            raw_dir = _camera_flat_forward()
    _aim_dir = _apply_aim_assist(raw_dir, body_radius + _current_reach_length())


## 模式 4 的身体朝向。转身速度按攻击状态分档：
## 待机快速转，蓄力慢慢修正，伪足伸出后完全锁死——出招后不能再改方向，这是类魂的核心约束
func _update_facing(delta: float) -> void:
    var turn_deg: float = 0.0
    match _pod_state:
        PodState.IDLE:
            turn_deg = turn_speed_deg
        PodState.CHARGING:
            turn_deg = charge_turn_speed_deg
    if turn_deg <= 0.0:
        return
    var step: float = deg_to_rad(turn_deg) * delta
    var wish: Vector3 = _move_input_world(1.0)
    var planar_len: float = Vector2(wish.x, wish.z).length()
    if planar_len > 0.0001:
        _facing_yaw = rotate_toward(_facing_yaw, atan2(-wish.x, -wish.z), step)
    # 没有输入时俯仰慢慢回到水平，否则停下来后会一直歪着头
    var pitch_target: float = 0.0
    if wish.length_squared() > 0.0001:
        pitch_target = _clamp_facing_pitch(atan2(wish.y, planar_len))
    _facing_pitch = move_toward(_facing_pitch, pitch_target, step)


func _snap_facing_to_input() -> void:
    var wish: Vector3 = _move_input_world(1.0)
    if wish.length_squared() < 0.0001:
        return
    var planar_len: float = Vector2(wish.x, wish.z).length()
    if planar_len > 0.0001:
        _facing_yaw = atan2(-wish.x, -wish.z)
    _facing_pitch = _clamp_facing_pitch(atan2(wish.y, planar_len))


func _clamp_facing_pitch(pitch: float) -> float:
    var limit: float = deg_to_rad(facing_max_pitch_deg)
    return clampf(pitch, -limit, limit)


func _facing_basis() -> Basis:
    return Basis(Vector3.UP, _facing_yaw) * Basis(Vector3.RIGHT, _facing_pitch)


func _facing_dir() -> Vector3:
    return _facing_basis() * Vector3.FORWARD


## 模式 4 的攻击方向：水平永远是身体正面，上下由三个开关按优先级决定
func _souls_aim() -> Vector3:
    var pitch: float = _facing_pitch
    var vertical: float = Input.get_axis(&"move_down", &"move_up")
    if directional_attacks and absf(vertical) > 0.5:
        pitch = signf(vertical) * deg_to_rad(directional_attack_pitch_deg)
    elif vertical_from_camera:
        pitch += _camera_pitch_offset()
    pitch = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

    var dir: Vector3 = (Basis(Vector3.UP, _facing_yaw) * Basis(Vector3.RIGHT, pitch)) * Vector3.FORWARD
    var reach: float = body_radius + _current_reach_length()
    if vertical_assist_enabled:
        return _apply_vertical_assist(dir, _facing_yaw, pitch, reach)
    return _apply_aim_assist(dir, reach)


## 镜头俯仰相对"默认俯仰"的偏移。以默认俯仰而不是水平为零点，
## 否则镜头本来就俯视 35°，攻击一开始就会朝下 35°
func _camera_pitch_offset() -> float:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null:
        return 0.0
    var cam_pitch: float = asin(clampf(-cam.global_basis.z.y, -1.0, 1.0))
    var neutral: float = 0.0
    var follow := cam as FollowCamera
    if follow != null:
        neutral = deg_to_rad(follow.pitch_deg)
    var offset: float = cam_pitch - neutral
    var deadzone: float = deg_to_rad(camera_pitch_deadzone_deg)
    offset = signf(offset) * maxf(absf(offset) - deadzone, 0.0)
    return offset * camera_pitch_follow_ratio


## 水平和上下分开判断容差，取两个方向偏差（各自按容差归一化）之和最小的目标
func _apply_vertical_assist(dir: Vector3, yaw: float, pitch: float, reach: float) -> Vector3:
    var h_limit: float = deg_to_rad(assist_horizontal_deg)
    var v_limit: float = deg_to_rad(assist_vertical_deg)
    if h_limit <= 0.0 or v_limit <= 0.0:
        return dir
    var max_dist: float = reach + pod_tip_radius + 1.0
    var best_dir: Vector3 = dir
    var best_score: float = INF
    for node: Node in get_tree().get_nodes_in_group(&"target"):
        var t := node as Node3D
        if t == null:
            continue
        var to: Vector3 = t.global_position - global_position
        var dist: float = to.length()
        if dist < 0.001 or dist > max_dist:
            continue
        var flat_len: float = Vector2(to.x, to.z).length()
        var t_pitch: float = atan2(to.y, flat_len)
        # 乘 cos(俯仰)：目标越接近正上/正下，水平角差在空间上越不重要，
        # 不然头顶正上方的目标会因为偏航角算不准而永远吸不到
        var d_yaw: float = absf(angle_difference(yaw, atan2(-to.x, -to.z))) * cos(t_pitch)
        var d_pitch: float = absf(t_pitch - pitch)
        if d_yaw > h_limit or d_pitch > v_limit:
            continue
        var score: float = d_yaw / h_limit + d_pitch / v_limit
        if score < best_score:
            best_score = score
            best_dir = to / dist
    return best_dir


## 模式 1：上升/下降键也算移动输入，所以能朝斜上、正下方出伪足
func _move_direction_aim() -> Vector3:
    var dir: Vector3 = _move_input_world(1.0)
    if dir.length_squared() < 0.0001:
        return _camera_flat_forward()
    return dir.normalized()


## 模式 0
func _right_stick_aim() -> Vector3:
    var stick: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_down", &"aim_up", aim_stick_deadzone)
    if stick != Vector2.ZERO:
        _aim_from_mouse = false
        _last_stick = stick
    elif _aim_from_mouse:
        stick = _mouse_as_stick()
    elif aim_neutral_returns_forward:
        stick = Vector2.ZERO
    else:
        stick = _last_stick
    return _stick_to_world(stick)


## 把鼠标相对主角屏幕位置的偏移换算成"虚拟摇杆"，这样键鼠和手柄共用同一套映射
func _mouse_as_stick() -> Vector2:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null:
        return Vector2.ZERO
    var center: Vector2 = cam.unproject_position(global_position)
    var offset: Vector2 = get_viewport().get_mouse_position() - center
    var stick := Vector2(offset.x, -offset.y) / maxf(mouse_aim_radius_px, 1.0)
    return stick.limit_length(1.0)


## 摇杆偏移量决定偏离前方的角度，摇杆方向决定往哪边偏。
## 用"镜头水平前方 + 世界上方"做参考系而不是镜头完整朝向，
## 这样镜头俯仰变化时，回中的瞄准仍然是水平的，不会忽上忽下。
func _stick_to_world(stick: Vector2) -> Vector3:
    var fwd: Vector3 = _camera_flat_forward()
    var mag: float = stick.length()
    if mag < 0.0001:
        return fwd
    var right: Vector3 = fwd.cross(Vector3.UP).normalized()
    var side: Vector3 = (right * stick.x + Vector3.UP * stick.y) / mag
    var theta: float = deg_to_rad(aim_max_tilt_deg) * mag
    return (fwd * cos(theta) + side * sin(theta)).normalized()


func _apply_aim_assist(dir: Vector3, reach: float) -> Vector3:
    if aim_assist_angle_deg <= 0.0:
        return dir
    var best_dir: Vector3 = dir
    var best_angle: float = deg_to_rad(aim_assist_angle_deg)
    # 多留一点余量，目标本身有体积，球心稍远一点也打得到
    var max_dist: float = reach + pod_tip_radius + 1.0
    for node: Node in get_tree().get_nodes_in_group(&"target"):
        var t := node as Node3D
        if t == null:
            continue
        var to: Vector3 = t.global_position - global_position
        var dist: float = to.length()
        if dist < 0.001 or dist > max_dist:
            continue
        var angle: float = dir.angle_to(to / dist)
        if angle < best_angle:
            best_angle = angle
            best_dir = to / dist
    return best_dir


## 模式 3。镜头默认略微俯视，所以摇杆回中时伪足会稍微朝下
func _camera_look_forward() -> Vector3:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null:
        return Vector3.FORWARD
    return -cam.global_basis.z


func _camera_flat_forward() -> Vector3:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null:
        return Vector3.FORWARD
    var f: Vector3 = -cam.global_basis.z
    f.y = 0.0
    if f.length_squared() < 0.0001:
        return Vector3.FORWARD
    return f.normalized()


# ---------------------------------------------------------------- 伪足

func _update_pseudopod(delta: float) -> void:
    _buffer_timer = maxf(_buffer_timer - delta, 0.0)

    match _pod_state:
        PodState.IDLE:
            if _buffer_timer > 0.0:
                _buffer_timer = 0.0
                _charge_time = 0.0
                if aim_mode == AimMode.SOULS and snap_facing_on_attack:
                    _snap_facing_to_input()
                    # 立刻刷新，否则这一帧的鼓包和瞄准点还指着旧方向
                    _update_aim()
                _pod_state = PodState.CHARGING

        PodState.CHARGING:
            _charge_time += delta
            # 缓冲触发时按键可能早就松开了，那就等同于一次轻点
            if not Input.is_action_pressed(&"pseudopod"):
                _release()

        PodState.EXTENDING:
            var speed: float = lerpf(extend_speed_short, extend_speed_long, _attack_charge)
            var next_length: float = move_toward(_pod_length, _target_length, speed * delta)
            var hit: Dictionary = _sweep_tip(_pod_length, next_length)
            if not hit.is_empty():
                _on_hit(hit)
            else:
                _pod_length = next_length
                if _pod_length >= _target_length:
                    _enter_hold()

        PodState.HOLDING:
            _hold_timer -= delta
            if _hold_timer <= 0.0:
                _pod_state = PodState.RETRACTING

        PodState.RETRACTING:
            var speed: float = lerpf(retract_speed_short, retract_speed_long, _attack_charge)
            _pod_length = move_toward(_pod_length, 0.0, speed * delta)
            if _pod_length <= 0.0:
                _pod_state = PodState.IDLE


func _current_charge() -> float:
    if _pod_state != PodState.CHARGING:
        return 0.0
    var span: float = maxf(charge_time_to_max - tap_threshold, 0.001)
    return clampf((_charge_time - tap_threshold) / span, 0.0, 1.0)


## 当前状态下伪足"能伸到"的长度，用于吸附范围和预告线
func _current_reach_length() -> float:
    match _pod_state:
        PodState.CHARGING:
            return lerpf(pod_min_length, pod_max_length, _current_charge())
        PodState.IDLE:
            return pod_min_length
        _:
            return _target_length


func _release() -> void:
    _attack_charge = _current_charge()
    _target_length = lerpf(pod_min_length, pod_max_length, _attack_charge)
    _attack_dir = _aim_dir
    _pod_length = 0.0
    _pod_state = PodState.EXTENDING


func _enter_hold() -> void:
    _hold_timer = lerpf(hold_time_short, hold_time_long, _attack_charge)
    _pod_state = PodState.HOLDING


## 用球形扫掠检测伪足尖端这一帧走过的路径，避免伸得快时穿过目标
func _sweep_tip(from_length: float, to_length: float) -> Dictionary:
    if to_length <= from_length:
        return {}
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    var from: Vector3 = global_position + _attack_dir * (body_radius + from_length)
    var motion: Vector3 = _attack_dir * (to_length - from_length)

    _tip_shape.radius = pod_tip_radius
    _tip_query.collision_mask = hit_mask
    _tip_query.transform = Transform3D(Basis.IDENTITY, from)
    _tip_query.motion = motion
    var fractions: PackedFloat32Array = space.cast_motion(_tip_query)
    if fractions[1] >= 1.0:
        return {}

    var unsafe: float = fractions[1]
    _tip_query.transform = Transform3D(Basis.IDENTITY, from + motion * unsafe)
    _tip_query.motion = Vector3.ZERO
    var results: Array[Dictionary] = space.intersect_shape(_tip_query, 1)
    if results.is_empty():
        return {}
    var hit: Dictionary = results[0]
    hit["length"] = lerpf(from_length, to_length, fractions[0])
    return hit


func _on_hit(hit: Dictionary) -> void:
    _pod_length = hit["length"]
    var target: Object = hit.get("collider")
    if target != null and target.has_method(&"take_hit"):
        target.call(&"take_hit", _attack_charge, _attack_dir)
    if target is Node:
        hit_landed.emit(target, _attack_charge)
    # 按路径取 autoload 而不是直接写 HitStop：单脚本语法检查不加载 autoload，
    # 直接引用会让 --check-only 报"找不到标识符"
    var hit_stop: Node = get_node_or_null(^"/root/HitStop")
    if hit_stop != null:
        hit_stop.call(&"trigger", lerpf(hitstop_light, hitstop_heavy, _attack_charge))
    _enter_hold()


# ---------------------------------------------------------------- 移动

func _update_movement(delta: float) -> void:
    var wish: Vector3 = _move_input_world(vertical_speed_scale)
    if _vertical_move_locked():
        wish.y = 0.0
    wish = wish.limit_length(1.0)
    var target_velocity: Vector3 = wish * max_speed * _move_scale()
    var rate: float = acceleration if wish.length_squared() > 0.0001 else deceleration
    velocity = velocity.lerp(target_velocity, 1.0 - exp(-rate * delta))

    move_and_slide()
    _apply_arena_bounds()


## 移动输入换算到世界空间（相对镜头水平朝向），未归一化。
## 移动和模式 1 的瞄准共用这一份换算，保证"往哪走"和"往哪打"完全一致
func _move_input_world(vertical_scale: float) -> Vector3:
    var fwd: Vector3 = _camera_flat_forward()
    var right: Vector3 = fwd.cross(Vector3.UP).normalized()
    var planar: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
    var vertical: float = Input.get_axis(&"move_down", &"move_up")
    return right * planar.x - fwd * planar.y + Vector3.UP * vertical * vertical_scale


## 方向攻击下升降键在出招期间被借去定方向，身体不应该同时往上飘
func _vertical_move_locked() -> bool:
    return aim_mode == AimMode.SOULS \
        and directional_attacks \
        and directional_locks_vertical_move \
        and _pod_state != PodState.IDLE


func _move_scale() -> float:
    match _pod_state:
        PodState.CHARGING:
            return move_scale_charging
        PodState.EXTENDING, PodState.HOLDING, PodState.RETRACTING:
            return lerpf(move_scale_extended_short, move_scale_extended_long, _attack_charge)
        _:
            return 1.0


## 球形边界用代码硬约束而不是碰撞体：内凹球面做碰撞容易卡，而且这里只需要"出不去"
func _apply_arena_bounds() -> void:
    var offset: Vector3 = global_position - arena_center
    var limit: float = arena_radius - body_radius
    if offset.length() <= limit:
        return
    var n: Vector3 = offset.normalized()
    global_position = arena_center + n * limit
    var outward: float = velocity.dot(n)
    if outward > 0.0:
        velocity -= n * outward


# ---------------------------------------------------------------- 表现

func _update_visuals() -> void:
    var idle_or_charging: bool = _pod_state == PodState.IDLE or _pod_state == PodState.CHARGING

    # 正面标记只在类魂模式下有意义，其他模式身体没有朝向，显示出来反而误导
    _facing_pivot.visible = aim_mode == AimMode.SOULS
    if _facing_pivot.visible:
        _facing_pivot.basis = _facing_basis()

    _aim_marker.visible = idle_or_charging
    if _aim_marker.visible:
        _aim_marker.position = _aim_dir * (body_radius + 0.35)

    # 蓄力的可读性靠剪影：膜朝攻击方向鼓起、越蓄越长
    _bulge_mesh.visible = _pod_state == PodState.CHARGING
    if _bulge_mesh.visible:
        var c: float = _current_charge()
        var width: float = lerpf(0.35, 0.6, c)
        var length: float = lerpf(0.4, bulge_max_stretch, c)
        _bulge_mesh.transform = Transform3D(
            _basis_y_to(_aim_dir) * Basis.from_scale(Vector3(width, length, width)),
            _aim_dir * (body_radius * 0.6 + length * 0.25)
        )

    _reach_preview.visible = show_reach_preview and _pod_state == PodState.CHARGING
    if _reach_preview.visible:
        var reach: float = _current_reach_length()
        _reach_preview.transform = Transform3D(
            _basis_y_to(_aim_dir) * Basis.from_scale(Vector3(1.0, reach, 1.0)),
            _aim_dir * (body_radius + reach * 0.5)
        )

    _pod_mesh.visible = not idle_or_charging and _pod_length > 0.0
    if _pod_mesh.visible:
        # 伪足从细胞中心长出，总长 = 半径 + 伸出长度；蓄得越满越细，像被拉长
        var total: float = body_radius + _pod_length
        var thickness: float = lerpf(1.0, 0.7, _attack_charge)
        _pod_mesh.transform = Transform3D(
            _basis_y_to(_attack_dir) * Basis.from_scale(Vector3(thickness, total, thickness)),
            _attack_dir * total * 0.5
        )


## 让网格的 Y 轴指向 dir（圆柱、椭球默认沿 Y 轴）
static func _basis_y_to(dir: Vector3) -> Basis:
    var d: Vector3 = dir.normalized()
    # 正好朝下时四元数弧线构造会退化，单独处理
    if d.dot(Vector3.UP) < -0.9999:
        return Basis(Vector3.RIGHT, PI)
    return Basis(Quaternion(Vector3.UP, d))


# ---------------------------------------------------------------- 调试

func get_debug_text() -> String:
    var state_name: String = PodState.keys()[_pod_state]
    var charge: float = _current_charge() if _pod_state == PodState.CHARGING else _attack_charge
    var source: String = ""
    if aim_mode == AimMode.RIGHT_STICK:
        source = "（鼠标）" if _aim_from_mouse else "（摇杆）"
    elif aim_mode == AimMode.SOULS:
        source = "  上下:[%s镜头][%s吸附][%s方向]  攻击俯仰 %+.0f°" % [
            "√" if vertical_from_camera else "×",
            "√" if vertical_assist_enabled else "×",
            "√" if directional_attacks else "×",
            rad_to_deg(asin(clampf(_aim_dir.y, -1.0, 1.0))),
        ]
    return "瞄准模式: %d %s%s\n伪足: %s   蓄力 %.2f   长度 %.1f / %.1f\n速度 %.1f" % [
        aim_mode,
        AimMode.keys()[aim_mode],
        source,
        state_name,
        charge,
        _pod_length,
        _current_reach_length(),
        velocity.length(),
    ]
