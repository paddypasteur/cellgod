class_name Player
extends CharacterBody3D
## 原型主角：无定形免疫细胞。
## 当前操作采用类魂方案：身体有正面，转向移动方向，攻击永远朝正面打；
## 攻击的上下角度由三个可组合的开关决定（镜头俯仰 / 不对称吸附 / 方向攻击）。
## 早期试过的另外四种瞄准方案（右摇杆瞄准、移动方向、镜头水平前方、镜头实际朝向）
## 已删除，需要时可从 git 历史 3c64973 找回。

signal hit_landed(target: Node, charge: float)

enum PodState { IDLE, CHARGING, EXTENDING, SWEEPING, HOLDING, RETRACTING }

## 攻击形态。保留直刺用于 A/B 对比
enum AttackShape {
    THRUST,  ## 0 = 直线前刺：从背后看伪足和视线几乎共线，难读
    SWING,   ## 1 = 伸出后挥扫一个弧：轨迹落在身体轮廓之外，从背后看得清
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

@export_group("朝向")
## 待机/移动时身体转向的速度（度/秒）
@export var turn_speed_deg: float = 720.0
## 蓄力期间还能慢慢修正朝向的速度（度/秒）。0 = 蓄力时完全锁死
@export var charge_turn_speed_deg: float = 180.0
## 按下攻击时若推着方向，立刻转过去再出招（类魂的"按方向+攻击"）
@export var snap_facing_on_attack: bool = true
## 朝向最多能抬头/低头多少度。上升/下降输入会让正面倾斜，0 = 正面永远水平
@export_range(0.0, 89.0) var facing_max_pitch_deg: float = 60.0

@export_group("索敌")
## 只有投影到屏幕上、离屏幕中心不超过"屏幕高度 × 此比例"的敌人才会被选中。
## 选中后攻击直接打向它，身体也转过去：镜头对准谁就打谁
@export_range(0.0, 1.0) var target_screen_radius: float = 0.3
## 伪足射程之外再多给多少米的余量（目标本身有体积，球心稍远一点也打得到）
@export var target_reach_slack: float = 1.0
## 选中标记悬在目标中心上方多高
@export var target_marker_height: float = 1.0

@export_group("上下方向（没有选中目标时）")
## 开关 1：攻击的上下角度跟随镜头俯仰。右摇杆往上看，伪足就往上打
@export var vertical_from_camera: bool = true
## 镜头每偏离默认俯仰 1°，攻击抬高/压低多少度
@export_range(0.0, 2.0) var camera_pitch_follow_ratio: float = 1.0
## 镜头俯仰在默认值附近多少度内不影响攻击，免得轻碰右摇杆攻击就歪
@export_range(0.0, 30.0) var camera_pitch_deadzone_deg: float = 5.0
## 开关 3：方向攻击。按住上升/下降键出招 = 上挑/下砸（丝之歌式）。
## 优先级最高：按着方向时不自动选目标，玩家明确的输入压过自动索敌
@export var directional_attacks: bool = true
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

@export_group("伪足 · 挥扫")
## 攻击形态。运行中切换，下一次出招生效
@export var attack_shape: AttackShape = AttackShape.SWING
## 轻点时挥扫的总角度（度）
@export_range(0.0, 300.0) var swing_arc_short_deg: float = 70.0
## 蓄满时挥扫的总角度（度）
@export_range(0.0, 300.0) var swing_arc_long_deg: float = 150.0
## 轻点时扫完整个弧所用的时间（秒）
@export var swing_time_short: float = 0.08
## 蓄满时扫完整个弧所用的时间（秒）。长伪足扫得慢 = 破绽大
@export var swing_time_long: float = 0.25
## 挥扫平面的倾角（度）。0 = 水平左右扫；90 = 竖直从上往下劈；45 = 斜劈；负数反向倾斜
@export_range(-90.0, 90.0) var swing_plane_deg: float = 0.0
## 连续出招时左右（或上下）交替挥扫
@export var swing_alternate: bool = true
## true = 一次挥扫打中路径上所有目标（每个只算一次）；false = 碰到第一个就停住
@export var swing_pass_through: bool = true
## 判定的角度步长（度）。挥得快、弧度大时防止一帧扫过头跳过目标；越小越准
@export_range(1.0, 20.0) var swing_check_step_deg: float = 4.0

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
## 蓄力时显示预告：直刺是一条射程细线，挥扫是一片扇形
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

## 当前瞄准方向（已含索敌），世界空间单位向量
var _aim_dir: Vector3 = Vector3.FORWARD
## 当前选中的目标，没有则为 null
var _target: Node3D = null

## 身体正面。存成偏航+俯仰两个角而不是向量，
## 这样转身用 rotate_toward 就不会遇到"正好转 180°时方向不确定"的问题
var _facing_yaw: float = 0.0
var _facing_pitch: float = 0.0

## 本次攻击在松手时锁定的参数
var _attack_dir: Vector3 = Vector3.FORWARD
var _attack_charge: float = 0.0
var _target_length: float = 0.0
## 当前伪足从膜表面伸出的长度
var _pod_length: float = 0.0

## 本次攻击是否挥扫（松手时锁定，出招中途切换形态不影响这一下）
var _attack_is_swing: bool = false
## 挥扫绕这根轴转；_attack_dir 是弧的正中，起点/终点是相对正中的角度
var _swing_axis: Vector3 = Vector3.UP
var _swing_start: float = 0.0
var _swing_end: float = 0.0
var _swing_duration: float = 0.1
## 挥扫进度 0..1
var _swing_t: float = 0.0
## 下一次挥扫从哪一侧开始，+1 / -1
var _swing_side: float = 1.0
## 本次挥扫已经打中过的目标，避免同一个目标被一次挥扫判定多次
var _swing_hit_ids: Array[int] = []

var _tip_shape: SphereShape3D = SphereShape3D.new()
var _tip_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _pod_capsule: CapsuleShape3D = CapsuleShape3D.new()
var _pod_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()

@onready var _pod_mesh: MeshInstance3D = $Pseudopod
@onready var _bulge_mesh: MeshInstance3D = $Bulge
@onready var _aim_marker: MeshInstance3D = $AimMarker
@onready var _reach_preview: MeshInstance3D = $ReachPreview
@onready var _facing_pivot: Node3D = $Facing
@onready var _swing_preview: MeshInstance3D = $SwingPreview
@onready var _target_marker: MeshInstance3D = $TargetMarker


func _ready() -> void:
    _tip_query.shape = _tip_shape
    _tip_query.collide_with_bodies = true
    _tip_query.collide_with_areas = false
    _tip_query.exclude = [get_rid()]
    _pod_query.shape = _pod_capsule
    _pod_query.collide_with_bodies = true
    _pod_query.collide_with_areas = false
    _pod_query.exclude = [get_rid()]


func _unhandled_input(event: InputEvent) -> void:
    # 按下事件走 _unhandled_input 而不是在物理帧里轮询 just_pressed：
    # 命中定格时物理帧暂停，轮询会漏掉定格期间的按键
    if event.is_action_pressed(&"pseudopod"):
        _buffer_timer = input_buffer_time


func _physics_process(delta: float) -> void:
    _update_facing(delta)
    _update_aim()
    _update_pseudopod(delta)
    _update_movement(delta)
    _update_visuals()


# ---------------------------------------------------------------- 朝向

## 转身速度按攻击状态分档：待机快速转，蓄力慢慢修正，
## 伪足伸出后完全锁死——出招后不能再改方向，这是类魂的核心约束
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


# ---------------------------------------------------------------- 瞄准

## 优先级：方向攻击（按着升降键）> 屏幕中心索敌 > 身体正面（俯仰叠加镜头偏移）
func _update_aim() -> void:
    var vertical: float = Input.get_axis(&"move_down", &"move_up")
    var directional: bool = directional_attacks and absf(vertical) > 0.5

    _target = null
    if not directional:
        _target = _find_screen_target(body_radius + _current_reach_length())
    if _target != null:
        _aim_dir = (_target.global_position - global_position).normalized()
        return

    var pitch: float = _facing_pitch
    if directional:
        pitch = signf(vertical) * deg_to_rad(directional_attack_pitch_deg)
    elif vertical_from_camera:
        pitch += _camera_pitch_offset()
    pitch = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
    _aim_dir = (Basis(Vector3.UP, _facing_yaw) * Basis(Vector3.RIGHT, pitch)) * Vector3.FORWARD


## 选投影离屏幕中心最近、且伪足够得着的目标。
## 按屏幕距离而不是按身体朝向挑：玩家用镜头"看"谁，就是想打谁
func _find_screen_target(reach: float) -> Node3D:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null:
        return null
    var screen: Vector2 = get_viewport().get_visible_rect().size
    var center: Vector2 = screen * 0.5
    var best_px: float = screen.y * target_screen_radius
    var max_dist: float = reach + pod_tip_radius + target_reach_slack
    var best: Node3D = null
    for node: Node in get_tree().get_nodes_in_group(&"target"):
        var t := node as Node3D
        if t == null:
            continue
        var dist: float = t.global_position.distance_to(global_position)
        if dist < 0.001 or dist > max_dist:
            continue
        if cam.is_position_behind(t.global_position):
            continue
        var px: float = cam.unproject_position(t.global_position).distance_to(center)
        if px < best_px:
            best_px = px
            best = t
    return best


func has_target() -> bool:
    return _target != null


## 有目标时身体直接转向攻击方向，让"正面"和"打向哪"保持一致，否则小方块指着别处会误导
func _face_toward(dir: Vector3) -> void:
    var flat_len: float = Vector2(dir.x, dir.z).length()
    if flat_len > 0.0001:
        _facing_yaw = atan2(-dir.x, -dir.z)
    _facing_pitch = _clamp_facing_pitch(atan2(dir.y, flat_len))


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
                if snap_facing_on_attack:
                    _snap_facing_to_input()
                    # 立刻刷新，否则这一帧的鼓包和瞄准点还指着旧方向
                    _update_aim()
                _pod_state = PodState.CHARGING
                if _target != null:
                    _face_toward(_aim_dir)

        PodState.CHARGING:
            _charge_time += delta
            if _target != null:
                _face_toward(_aim_dir)
            # 缓冲触发时按键可能早就松开了，那就等同于一次轻点
            if not Input.is_action_pressed(&"pseudopod"):
                _release()

        PodState.EXTENDING:
            var speed: float = lerpf(extend_speed_short, extend_speed_long, _attack_charge)
            var next_length: float = move_toward(_pod_length, _target_length, speed * delta)
            if _attack_is_swing:
                # 挥扫的伸出阶段相当于抬手，不判定；伸到位后才开始扫
                _pod_length = next_length
                if _pod_length >= _target_length:
                    _pod_state = PodState.SWEEPING
                    # 先检查起始姿态：伸到位时可能已经压在目标身上
                    if _sweep_swing_to(0.0):
                        _enter_hold()
            else:
                var hit: Dictionary = _sweep_tip(_pod_length, next_length)
                if not hit.is_empty():
                    _on_thrust_hit(hit)
                else:
                    _pod_length = next_length
                    if _pod_length >= _target_length:
                        _enter_hold()

        PodState.SWEEPING:
            var next_t: float = 1.0
            if _swing_duration > 0.0:
                next_t = minf(_swing_t + delta / _swing_duration, 1.0)
            var stopped: bool = _sweep_swing_to(next_t)
            if stopped or _swing_t >= 1.0:
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


## 当前状态下伪足"能伸到"的长度，用于索敌范围和预告线
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
    if _target != null:
        _face_toward(_attack_dir)
    _pod_length = 0.0
    _attack_is_swing = attack_shape == AttackShape.SWING
    if _attack_is_swing:
        _swing_axis = _swing_axis_for(_attack_dir)
        var half: float = _swing_half_arc(_attack_charge)
        _swing_start = half * _swing_side
        _swing_end = -half * _swing_side
        _swing_duration = lerpf(swing_time_short, swing_time_long, _attack_charge)
        _swing_t = 0.0
        _swing_hit_ids.clear()
        if swing_alternate:
            _swing_side = -_swing_side
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


func _on_thrust_hit(hit: Dictionary) -> void:
    _pod_length = hit["length"]
    _deal_hit(hit.get("collider"), _attack_dir)
    _enter_hold()


func _deal_hit(target: Object, direction: Vector3) -> void:
    if target == null:
        return
    if target.has_method(&"take_hit"):
        target.call(&"take_hit", _attack_charge, direction)
    if target is Node:
        hit_landed.emit(target, _attack_charge)
    # 按路径取 autoload 而不是直接写 HitStop：单脚本语法检查不加载 autoload，
    # 直接引用会让 --check-only 报"找不到标识符"
    var hit_stop: Node = get_node_or_null(^"/root/HitStop")
    if hit_stop != null:
        hit_stop.call(&"trigger", lerpf(hitstop_light, hitstop_heavy, _attack_charge))


# ---------------------------------------------------------------- 挥扫

## 挥扫轴：默认取"攻击方向的上方"，绕它转就是左右扫；
## 按倾角把轴往"攻击方向的右方"转，就变成斜劈或竖劈
func _swing_axis_for(dir: Vector3) -> Vector3:
    var right: Vector3 = dir.cross(Vector3.UP)
    if right.length_squared() < 0.0001:
        # 正朝上/下打时"右方"没定义，借用身体正面的右方
        right = _facing_basis().x
    right = right.normalized()
    var up: Vector3 = right.cross(dir).normalized()
    var tilt: float = deg_to_rad(swing_plane_deg)
    return (up * cos(tilt) + right * sin(tilt)).normalized()


func _swing_half_arc(charge: float) -> float:
    return deg_to_rad(lerpf(swing_arc_short_deg, swing_arc_long_deg, charge)) * 0.5


## 伪足当前实际指向。挥扫时随进度转动，直刺时就是攻击方向
func _pod_dir() -> Vector3:
    if _attack_is_swing:
        return _attack_dir.rotated(_swing_axis, lerpf(_swing_start, _swing_end, _swing_t))
    return _attack_dir


## 把挥扫推进到 to_t，按角度步长逐段检测，防止一帧扫过头跳过目标。
## 返回 true 表示碰到目标且不穿透，挥扫应当停在这里
func _sweep_swing_to(to_t: float) -> bool:
    var from_t: float = _swing_t
    var swept_deg: float = rad_to_deg(absf(_swing_end - _swing_start) * (to_t - from_t))
    var steps: int = maxi(1, ceili(swept_deg / swing_check_step_deg))
    for i: int in range(1, steps + 1):
        _swing_t = lerpf(from_t, to_t, float(i) / float(steps))
        if _check_pod_overlap() and not swing_pass_through:
            return true
    _swing_t = to_t
    return false


## 用一根胶囊体覆盖整条伪足做重叠检测：挥扫时打中的可能是伪足中段，不只是尖端
func _check_pod_overlap() -> bool:
    var dir: Vector3 = _pod_dir()
    var total: float = body_radius + _pod_length
    _pod_capsule.radius = pod_tip_radius
    _pod_capsule.height = maxf(total, pod_tip_radius * 2.0)
    _pod_query.collision_mask = hit_mask
    _pod_query.transform = Transform3D(_basis_y_to(dir), global_position + dir * total * 0.5)
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    var hit_any: bool = false
    for result: Dictionary in space.intersect_shape(_pod_query, 8):
        var target: Object = result.get("collider")
        if target == null:
            continue
        var id: int = target.get_instance_id()
        if _swing_hit_ids.has(id):
            continue
        _swing_hit_ids.append(id)
        _deal_hit(target, dir)
        hit_any = true
    return hit_any


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
## 移动和转身共用这一份换算，保证"往哪走"和"往哪转"完全一致
func _move_input_world(vertical_scale: float) -> Vector3:
    var fwd: Vector3 = _camera_flat_forward()
    var right: Vector3 = fwd.cross(Vector3.UP).normalized()
    var planar: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
    var vertical: float = Input.get_axis(&"move_down", &"move_up")
    return right * planar.x - fwd * planar.y + Vector3.UP * vertical * vertical_scale


## 方向攻击下升降键在出招期间被借去定方向，身体不应该同时往上飘
func _vertical_move_locked() -> bool:
    return directional_attacks \
        and directional_locks_vertical_move \
        and _pod_state != PodState.IDLE


func _move_scale() -> float:
    match _pod_state:
        PodState.CHARGING:
            return move_scale_charging
        PodState.EXTENDING, PodState.SWEEPING, PodState.HOLDING, PodState.RETRACTING:
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

    _facing_pivot.basis = _facing_basis()

    _aim_marker.visible = idle_or_charging
    if _aim_marker.visible:
        _aim_marker.position = _aim_dir * (body_radius + 0.35)

    # 标记是 top_level，直接用世界坐标挂在目标头顶
    _target_marker.visible = idle_or_charging and _target != null
    if _target_marker.visible:
        _target_marker.global_position = _target.global_position + Vector3.UP * target_marker_height

    var charging: bool = _pod_state == PodState.CHARGING
    var swing_selected: bool = attack_shape == AttackShape.SWING

    # 蓄力的可读性靠剪影：膜朝伪足将要伸出的方向鼓起、越蓄越长。
    # 挥扫时鼓在起点那一侧，顺便预告这一下从哪边扫过来
    _bulge_mesh.visible = charging
    if _bulge_mesh.visible:
        var c: float = _current_charge()
        var bulge_dir: Vector3 = _aim_dir
        if swing_selected:
            bulge_dir = _aim_dir.rotated(_swing_axis_for(_aim_dir), _swing_half_arc(c) * _swing_side)
        var width: float = lerpf(0.35, 0.6, c)
        var length: float = lerpf(0.4, bulge_max_stretch, c)
        _bulge_mesh.transform = Transform3D(
            _basis_y_to(bulge_dir) * Basis.from_scale(Vector3(width, length, width)),
            bulge_dir * (body_radius * 0.6 + length * 0.25)
        )

    _swing_preview.visible = show_reach_preview and charging and swing_selected
    if _swing_preview.visible:
        _draw_swing_preview(_current_reach_length(), _current_charge())

    _reach_preview.visible = show_reach_preview and charging and not swing_selected
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
        var dir: Vector3 = _pod_dir()
        _pod_mesh.transform = Transform3D(
            _basis_y_to(dir) * Basis.from_scale(Vector3(thickness, total, thickness)),
            dir * total * 0.5
        )


## 扇形环带：从膜表面到伪足能伸到的距离，覆盖即将扫过的整个弧
func _draw_swing_preview(reach: float, charge: float) -> void:
    var mesh := _swing_preview.mesh as ImmediateMesh
    if mesh == null:
        return
    mesh.clear_surfaces()
    var axis: Vector3 = _swing_axis_for(_aim_dir)
    var half: float = _swing_half_arc(charge)
    var segments: int = maxi(2, ceili(rad_to_deg(half * 2.0) / 5.0))
    var inner: float = body_radius
    var outer: float = body_radius + reach
    mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
    for i: int in segments:
        var d0: Vector3 = _aim_dir.rotated(axis, lerpf(half, -half, float(i) / segments))
        var d1: Vector3 = _aim_dir.rotated(axis, lerpf(half, -half, float(i + 1) / segments))
        mesh.surface_add_vertex(d0 * inner)
        mesh.surface_add_vertex(d0 * outer)
        mesh.surface_add_vertex(d1 * outer)
        mesh.surface_add_vertex(d0 * inner)
        mesh.surface_add_vertex(d1 * outer)
        mesh.surface_add_vertex(d1 * inner)
    mesh.surface_end()


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
    return "形态: %s   目标: %s   上下: [%s镜头] [%s方向]   攻击俯仰 %+.0f°\n伪足: %s   蓄力 %.2f   长度 %.1f / %.1f\n速度 %.1f" % [
        "挥扫" if attack_shape == AttackShape.SWING else "直刺",
        str(_target.name) if _target != null else "无",
        "√" if vertical_from_camera else "×",
        "√" if directional_attacks else "×",
        rad_to_deg(asin(clampf(_aim_dir.y, -1.0, 1.0))),
        state_name,
        charge,
        _pod_length,
        _current_reach_length(),
        velocity.length(),
    ]
