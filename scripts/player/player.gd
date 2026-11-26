class_name Player
extends CharacterBody3D
## 原型主角：无定形免疫细胞。
## 类魂操作：身体有正面，转向移动方向；有索敌目标时打目标，没有时朝正面打。
## 攻击形态是挥扫。被淘汰的方案不留开关，从 git 历史找回：
## 四种旧瞄准方案在 3c64973，直刺在 fa090b9。

signal hit_landed(target: Node, charge: float)
signal health_changed(current: float, maximum: float)
## 血量归零。原型阶段不做死亡流程，发完信号直接回满
signal defeated
## 发起一次闪避，direction 是世界空间单位向量（记录垂直分量用）
signal dodged(direction: Vector3)
## 一次攻击正好落在闪避无敌时间里被躲掉（每次闪避最多发一次）
signal dodge_saved
## 发起一次弹射。direction = 朝目标的方向（记录仰角用），chain_index = 这是本条链的第几次弹射
signal bounced(direction: Vector3, chain_index: int)
## 弹射到达后的自动轻击结束，hit = 有没有打中
signal bounce_strike(hit: bool)
## 一条连招链结束。hits = 链里打中了几下（含开链那一下），bounces = 弹射了几次
signal chain_ended(hits: int, bounces: int, reason: String)

enum PodState { IDLE, CHARGING, EXTENDING, SWEEPING, HOLDING, RETRACTING }

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
## 索敌点（也是准星位置）相对屏幕中心的偏移，单位是屏幕高度的比例，负 y = 往上。
## 镜头注视着主角，屏幕正中几乎就是主角自己；上移一点，准星才不会压在主角身上，
## 索敌也会优先选主角前上方的敌人，而不是被主角挡住的那只
@export var aim_point_offset: Vector2 = Vector2(0.0, -0.12)
## 当前目标的屏幕距离乘这个系数（<1 = 在位优势），新目标必须比它更近才抢得走。
## 2026-11-25 A/B：0.75（跟手）vs 0.5（粘手），开发者分不出，取余地更大的 0.75
@export_range(0.1, 1.0) var target_keep_bias: float = 0.75
## 换目标后至少锁这么久（秒），除非目标死亡或丢失
@export var target_min_hold: float = 0.15
## 正在前摇或冲刺的敌人，屏幕距离按这个系数打折：同样远时，扑过来的那只优先被选中
@export_range(0.1, 1.0) var threat_bias: float = 0.7
## 已锁定的目标允许多出多少射程、屏幕半径放宽多少倍才丢失，避免在边界上反复进出
@export var keep_extra_range: float = 1.5
@export var keep_screen_radius_scale: float = 1.3

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
## 伪足的判定半径（粗细）
@export var pod_tip_radius: float = 0.35
## 命中定格时长（秒），按蓄力在轻/重之间插值。重击多冻几帧
@export var hitstop_light: float = 0.05
@export var hitstop_heavy: float = 0.14
## 伪足能打到的物理层
@export_flags_3d_physics var hit_mask: int = 2

@export_group("闪避")
## 一次闪避冲出去多远（米）
@export var dodge_distance: float = 4.5
## 冲刺持续多久（秒）
@export var dodge_duration: float = 0.22
## 从闪避开始算起的无敌时间（秒）
@export var dodge_iframe_time: float = 0.18
## 闪避结束后多久才能再闪（秒）
@export var dodge_cooldown: float = 0.6
## 闪避结束时保留多少冲刺速度（0..1），太小会有急刹车感
@export_range(0.0, 1.0) var dodge_exit_speed_scale: float = 0.35
## 蓄力中能否闪避（会取消这次蓄力）。伪足伸出后一律不能闪：长伪足"门户大开"的代价不能被闪避抵消
@export var dodge_cancels_charge: bool = true
## 提前按下的闪避记住多久（秒）
@export var dodge_buffer_time: float = 0.15

@export_group("连招弹射")
## 命中后弹射窗口开多久（秒，游戏时间）。
## 2026-11-26 A/B：0.25（短）vs 0.5（长），开发者选长："B 更顺手"；行为上 B 的 ≥2 下连招占比也是 A 的两倍
@export var bounce_window_time: float = 0.5
## 在输入方向多大的锥形里找下一个目标（半角，度）。上下和水平一视同仁
@export_range(5.0, 90.0) var bounce_cone_deg: float = 50.0
## 多远以内的敌人能被弹过去（米）
@export var bounce_range: float = 12.0
## 弹射飞行速度（米/秒）。比闪避（约 20）略快，弹射是进攻性的突进
@export var bounce_speed: float = 24.0
## 离目标中心多近算到达（米），到达后自动出一次轻击。要在轻击够得着的范围内
@export var bounce_arrive_distance: float = 2.2
## 到达点往目标侧面偏多少（0 = 沿飞行方向直接停在目标前，1 = 完全停在目标侧面）。
## 不偏的话，从正上方俯冲下去会停在目标正上方，镜头从斜上方看时主角正好挡住目标、两者叠成一团
## （2026-11-26 截图确认）。侧面 = 相对镜头的左右，取玩家飞来的那一侧
@export_range(0.0, 1.0) var bounce_arrive_side_weight: float = 0.8
## 一条链最多弹射几次
@export var bounce_max_chain: int = 3
## 方向输入至少多大才算"指了方向"（0..1）。小于它按攻击 = 普通原地接招
@export_range(0.0, 1.0) var bounce_input_threshold: float = 0.3
## 弹射窗口开着时身体染上这个颜色，提示"现在可以弹"
@export var bounce_window_tint: Color = Color(1.0, 0.85, 0.3)

@export_group("生命与受击")
@export var max_health: float = 100.0
## 受击后的无敌时间（秒），防止同一下攻击连续扣血
@export var hurt_invuln_time: float = 0.5
## 受击后失去操控的时间（秒），期间只被击退带着走
@export var hurt_stun_time: float = 0.2
## 受击失控期间击退速度的衰减响应。越小被打得越远
@export var hurt_knockback_damping: float = 4.0
## 受击时的命中定格（秒）
@export var hurt_hitstop: float = 0.06
## 受击时的镜头震动强度（0..1）
@export_range(0.0, 1.0) var hurt_camera_shake: float = 0.6
## 受击闪红
@export var hurt_flash_color: Color = Color(1.0, 0.2, 0.2)
@export var hurt_flash_time: float = 0.25

@export_group("显示")
## 身体半径。要和碰撞形状、身体网格保持一致
@export var body_radius: float = 0.5
## 蓄力时显示一片扇形，预告将要扫过的范围
@export var show_reach_preview: bool = true
## 蓄满时膜鼓起部分沿攻击方向拉长到多少（相对身体直径）
@export var bulge_max_stretch: float = 1.2

## 竞技场边界由 Arena 在运行时写入，不在这里调
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 20.0

var health: float = 0.0
var _invuln_timer: float = 0.0
var _stun_timer: float = 0.0
var _hurt_flash_timer: float = 0.0
var _body_material: StandardMaterial3D = null
var _body_base_color: Color = Color.WHITE

var _dodge_timer: float = 0.0
var _dodge_cooldown_timer: float = 0.0
var _dodge_buffer: float = 0.0
var _iframe_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.FORWARD
var _dodge_saved_once: bool = false

## 弹射窗口剩余时间（游戏时间：命中定格冻结物理帧，所以定格不会吃掉窗口）
var _bounce_window: float = 0.0
var _bouncing: bool = false
var _bounce_target: Node3D = null
var _bounce_timer: float = 0.0
## 到达点相对目标的偏移，起跳时算好，飞行中跟着目标移动
var _bounce_offset: Vector3 = Vector3.ZERO
## 当前这一击是弹射到达后的自动轻击
var _auto_attack: bool = false
## 当前这一击是否已经打中过东西（第一次打中时开窗口）
var _attack_hit_any: bool = false
var _chain_active: bool = false
var _chain_hits: int = 0
var _chain_bounces: int = 0
## 本条链打过的敌人，不能再弹向它们（逼玩家规划路线）
var _chain_visited: Array[int] = []

var _pod_state: PodState = PodState.IDLE
var _charge_time: float = 0.0
var _hold_timer: float = 0.0
var _buffer_timer: float = 0.0

## 当前瞄准方向（已含索敌），世界空间单位向量
var _aim_dir: Vector3 = Vector3.FORWARD
## 当前选中的目标，没有则为 null
var _target: Node3D = null
## 刚换目标后的最短锁定时间，期间除非目标失效否则不换
var _target_hold_timer: float = 0.0

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

var _pod_capsule: CapsuleShape3D = CapsuleShape3D.new()
var _pod_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()

@onready var _pod_mesh: MeshInstance3D = $Pseudopod
@onready var _bulge_mesh: MeshInstance3D = $Bulge
@onready var _aim_marker: MeshInstance3D = $AimMarker
@onready var _facing_pivot: Node3D = $Facing
@onready var _swing_preview: MeshInstance3D = $SwingPreview
@onready var _target_marker: MeshInstance3D = $TargetMarker
@onready var _body_mesh: MeshInstance3D = $Body


func _ready() -> void:
    add_to_group(&"hud_hint")
    _pod_query.shape = _pod_capsule
    _pod_query.collide_with_bodies = true
    _pod_query.collide_with_areas = false
    _pod_query.exclude = [get_rid()]
    health = max_health
    # 复制身体材质用于受击闪红，不改动场景里的原材质
    var source := _body_mesh.get_active_material(0) as StandardMaterial3D
    if source != null:
        _body_material = source.duplicate() as StandardMaterial3D
        _body_mesh.material_override = _body_material
        _body_base_color = _body_material.albedo_color


func _unhandled_input(event: InputEvent) -> void:
    # 按下事件走 _unhandled_input 而不是在物理帧里轮询 just_pressed：
    # 命中定格时物理帧暂停，轮询会漏掉定格期间的按键
    if event.is_action_pressed(&"pseudopod"):
        _buffer_timer = input_buffer_time
    elif event.is_action_pressed(&"dodge"):
        _dodge_buffer = dodge_buffer_time


func _physics_process(delta: float) -> void:
    _invuln_timer = maxf(_invuln_timer - delta, 0.0)
    _stun_timer = maxf(_stun_timer - delta, 0.0)
    _hurt_flash_timer = maxf(_hurt_flash_timer - delta, 0.0)
    _target_hold_timer = maxf(_target_hold_timer - delta, 0.0)
    _dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
    _dodge_buffer = maxf(_dodge_buffer - delta, 0.0)
    _iframe_timer = maxf(_iframe_timer - delta, 0.0)
    _bounce_timer = maxf(_bounce_timer - delta, 0.0)
    if _bounce_window > 0.0:
        _bounce_window -= delta
        if _bounce_window <= 0.0 and not _bouncing:
            _end_chain("timeout")
    _update_facing(delta)
    _update_aim()
    _try_start_bounce()
    _try_start_dodge()
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

    if directional:
        _target = null
    else:
        _target = _select_target(body_radius + _current_reach_length())
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


## 选投影离准星最近、且伪足够得着的目标，但带粘性：
## 以前每帧从零重选，别的目标只要近 1 像素就抢走选择，这就是"锁定乱跳"的直接原因。
## 现在：当前目标的距离打折（新目标必须明显更近才抢得走）；刚换目标后有最短锁定时间；
## 蓄力中完全不换（不然蓄到一半目标跳走，这一下就打歪了）；扑过来的敌人优先
func _select_target(reach: float) -> Node3D:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null:
        return null
    var screen: Vector2 = get_viewport().get_visible_rect().size
    var max_px: float = screen.y * target_screen_radius
    var max_dist: float = reach + pod_tip_radius + target_reach_slack

    var current: Node3D = _target
    var current_score: float = -1.0
    if current != null and is_instance_valid(current) and current.is_in_group(&"target"):
        # 已锁定的目标用放宽后的范围判定，避免在射程/屏幕边界上反复进出
        current_score = _target_score(cam, current,
            max_dist + keep_extra_range, max_px * keep_screen_radius_scale)
    if current_score < 0.0:
        current = null
    elif _pod_state == PodState.CHARGING or _target_hold_timer > 0.0:
        return current

    var best: Node3D = current
    var best_score: float = INF
    if current != null:
        best_score = current_score * target_keep_bias
    for node: Node in get_tree().get_nodes_in_group(&"target"):
        var t := node as Node3D
        if t == null or t == current:
            continue
        var score: float = _target_score(cam, t, max_dist, max_px)
        if score >= 0.0 and score < best_score:
            best_score = score
            best = t
    if best != current:
        _target_hold_timer = target_min_hold
    return best


## 目标的屏幕距离（越小越优先），不合格返回 -1。正在前摇/冲刺的敌人打折
func _target_score(cam: Camera3D, t: Node3D, max_dist: float, max_px: float) -> float:
    var dist: float = t.global_position.distance_to(global_position)
    if dist < 0.001 or dist > max_dist:
        return -1.0
    if cam.is_position_behind(t.global_position):
        return -1.0
    var px: float = cam.unproject_position(t.global_position).distance_to(get_aim_screen_point())
    if px > max_px:
        return -1.0
    if t.has_method(&"is_threatening") and t.call(&"is_threatening"):
        px *= threat_bias
    return px


func has_target() -> bool:
    return _target != null


## 索敌用的屏幕点，准星画在同一个位置，保证"看到的准星"和"实际索敌点"永远一致
func get_aim_screen_point() -> Vector2:
    var screen: Vector2 = get_viewport().get_visible_rect().size
    return screen * 0.5 + aim_point_offset * screen.y


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
            # 闪避途中不起手，按键留在缓冲里，闪完立刻接
            if _buffer_timer > 0.0 and _dodge_timer <= 0.0 and not _bouncing:
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
            # 伸出阶段相当于抬手，不判定；伸到位后才开始扫
            _pod_length = move_toward(_pod_length, _target_length, speed * delta)
            if _pod_length >= _target_length:
                _pod_state = PodState.SWEEPING
                _play_sfx(&"swing", lerpf(1.15, 0.8, _attack_charge))
                # 先检查起始姿态：伸到位时可能已经压在目标身上
                if _sweep_swing_to(0.0):
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
    _launch_attack(_current_charge(), _aim_dir, false)


## 发出一击。auto = 弹射到达后的自动轻击：它属于当前连招链；玩家自己出的招则开始新的链
func _launch_attack(charge: float, direction: Vector3, auto: bool) -> void:
    if not auto:
        # 窗口里不指方向按攻击 = 原地接招，按规格这不是弹射，旧链到此结束
        _end_chain("followup")
    _auto_attack = auto
    _attack_hit_any = false
    _bounce_window = 0.0
    _attack_charge = charge
    _target_length = lerpf(pod_min_length, pod_max_length, _attack_charge)
    _attack_dir = direction
    if _target != null or auto:
        _face_toward(_attack_dir)
    _pod_length = 0.0
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
    # 挥扫结束：弹射到达后的那一击到这里就知道有没有打中
    if _auto_attack:
        _auto_attack = false
        bounce_strike.emit(_attack_hit_any)
        if not _attack_hit_any:
            _end_chain("miss")


func _deal_hit(target: Object, direction: Vector3) -> void:
    if target == null:
        return
    if target.has_method(&"take_hit"):
        target.call(&"take_hit", _attack_charge, direction)
    if target is Node:
        hit_landed.emit(target, _attack_charge)
    _on_chain_hit(target)
    _play_sfx(&"hit", lerpf(1.2, 0.75, _attack_charge))
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


## 伪足当前实际指向，随挥扫进度转动
func _pod_dir() -> Vector3:
    return _attack_dir.rotated(_swing_axis, lerpf(_swing_start, _swing_end, _swing_t))


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
    if _bouncing:
        _update_bounce_flight()
    elif _dodge_timer > 0.0:
        _dodge_timer -= delta
        velocity = _dodge_dir * (dodge_distance / maxf(dodge_duration, 0.01))
        if _dodge_timer <= 0.0:
            velocity *= dodge_exit_speed_scale
    elif _stun_timer > 0.0:
        # 受击失控：不吃输入，只让击退速度慢慢衰减
        velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-hurt_knockback_damping * delta))
    else:
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


# ---------------------------------------------------------------- 连招弹射
#
# 普通连招是时间上的序列，弹射连招是空间上的序列：命中后指一个方向，把自己甩向那边的下一个敌人，
# 到达自动出一次轻击，打中再开下一个窗口。在球形战场里"打谁"同时决定"我下一秒在哪一层"。
# 风险结构：只有命中才开窗口（打空照样走完收回挨罚）；弹射没有无敌（否则它严格优于闪避）。


## 每一击第一次打中东西时开窗口；同一击扫中多个只算链里的一下，但它们都记为"打过了"
func _on_chain_hit(target: Object) -> void:
    if target != null:
        _chain_visited.append(target.get_instance_id())
    if _attack_hit_any:
        return
    _attack_hit_any = true
    if not _chain_active:
        _chain_active = true
        _chain_hits = 0
        _chain_bounces = 0
        # 刚打中的目标在上面已经记入，这里只清掉更早的
        var keep: int = target.get_instance_id() if target != null else 0
        _chain_visited = [keep]
    _chain_hits += 1
    if _chain_bounces < bounce_max_chain:
        _bounce_window = bounce_window_time
    else:
        _end_chain("max")


## 窗口内 有方向输入 + 按攻击 + 锥形里有没打过的敌人 → 弹射。
## 任何一条不满足都不弹，攻击键留在缓冲里走原来的"原地接招"，玩家永远不会被甩到不想去的地方
func _try_start_bounce() -> void:
    if _bounce_window <= 0.0 or _bouncing or _buffer_timer <= 0.0 or _stun_timer > 0.0:
        return
    var wish: Vector3 = _move_input_world(1.0)
    if wish.length() < bounce_input_threshold:
        return
    var target: Node3D = _find_bounce_target(wish.normalized())
    if target == null:
        return
    _buffer_timer = 0.0
    _bounce_window = 0.0
    # 取消剩下的停留和收回：这正是弹射的价值，否则链条中间有停顿
    _pod_state = PodState.IDLE
    _pod_length = 0.0
    _bouncing = true
    _bounce_target = target
    _bounce_timer = bounce_range / maxf(bounce_speed, 0.1) + 0.3
    _chain_bounces += 1
    var dir: Vector3 = (target.global_position - global_position).normalized()
    _bounce_offset = _compute_arrive_offset(target)
    _face_toward(dir)
    _play_sfx(&"swing", 1.4)
    bounced.emit(dir, _chain_bounces)


## 锥形内找目标；多个时用准星当裁判（复用索敌判据），没在屏幕上的按夹角排在后面
func _find_bounce_target(dir: Vector3) -> Node3D:
    var cam: Camera3D = get_viewport().get_camera_3d()
    var cos_limit: float = cos(deg_to_rad(bounce_cone_deg))
    var best: Node3D = null
    var best_score: float = INF
    for node: Node in get_tree().get_nodes_in_group(&"target"):
        var t := node as Node3D
        if t == null or _chain_visited.has(t.get_instance_id()):
            continue
        var to: Vector3 = t.global_position - global_position
        var dist: float = to.length()
        if dist < 0.001 or dist > bounce_range:
            continue
        var cos_angle: float = dir.dot(to / dist)
        if cos_angle < cos_limit:
            continue
        var score: float = 100000.0 + (1.0 - cos_angle) * 1000.0
        if cam != null and not cam.is_position_behind(t.global_position):
            score = cam.unproject_position(t.global_position).distance_to(get_aim_screen_point())
        if score < best_score:
            best_score = score
            best = t
    return best


func _update_bounce_flight() -> void:
    var target := _bounce_target
    if target == null or not is_instance_valid(target) or not target.is_in_group(&"target"):
        # 目标在路上死了：停下，链结束
        _bouncing = false
        velocity *= 0.3
        _end_chain("lost")
        return
    var goal: Vector3 = target.global_position + _bounce_offset
    var to_goal: Vector3 = goal - global_position
    var dist: float = to_goal.length()
    var to_target: Vector3 = (target.global_position - global_position).normalized()
    if dist <= 0.4 or _bounce_timer <= 0.0:
        _bouncing = false
        # 到达时留一点前冲的惯性，不要急刹
        velocity = to_target * max_speed * 0.5
        _launch_attack(0.0, to_target, true)
        return
    # 每帧重新瞄准：敌人在动，直线飞向出发时的位置会扑空。离到达点很近时减速，避免一帧冲过头
    velocity = to_goal / dist * minf(bounce_speed, dist / maxf(get_physics_process_delta_time(), 0.001))
    _face_toward(to_target)


## 到达点 = 目标 + 偏移。偏移由"沿来路退回"和"往镜头左/右侧让开"按权重混合，长度 = 到达距离
func _compute_arrive_offset(target: Node3D) -> Vector3:
    var from_target: Vector3 = global_position - target.global_position
    var back: Vector3 = from_target.normalized() if from_target.length_squared() > 0.0001 else Vector3.BACK
    var side: Vector3 = back
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam != null:
        var cam_right: Vector3 = cam.global_basis.x
        cam_right.y = 0.0
        if cam_right.length_squared() > 0.0001:
            cam_right = cam_right.normalized()
            var s: float = signf(from_target.dot(cam_right))
            side = cam_right * (s if s != 0.0 else 1.0)
    var mixed: Vector3 = back.lerp(side, bounce_arrive_side_weight)
    if mixed.length_squared() < 0.0001:
        mixed = side
    return mixed.normalized() * bounce_arrive_distance


func _end_chain(reason: String) -> void:
    _bounce_window = 0.0
    if not _chain_active:
        return
    _chain_active = false
    chain_ended.emit(_chain_hits, _chain_bounces, reason)


func is_bouncing() -> bool:
    return _bouncing


## 闪避方向 = 当前移动输入（含上升/下降），所以能往上、往下躲；没推方向就往身后撤。
## 只能在待机或蓄力时闪：伪足伸出去之后"门户大开"是长伪足的代价，不能用闪避抵消
func _try_start_dodge() -> void:
    if _dodge_buffer <= 0.0 or _dodge_timer > 0.0 or _dodge_cooldown_timer > 0.0 or _stun_timer > 0.0:
        return
    # 弹射途中不能闪：两个位移叠在一起读不清，而且弹射本来就是"选择了暴露"
    if _bouncing:
        return
    match _pod_state:
        PodState.IDLE:
            pass
        PodState.CHARGING:
            if not dodge_cancels_charge:
                return
            _pod_state = PodState.IDLE
            _charge_time = 0.0
        _:
            return
    _dodge_buffer = 0.0
    var dir: Vector3 = _move_input_world(1.0)
    if dir.length_squared() < 0.01:
        dir = -(_facing_basis() * Vector3.FORWARD)
    _dodge_dir = dir.normalized()
    _dodge_timer = dodge_duration
    _iframe_timer = dodge_iframe_time
    _dodge_cooldown_timer = dodge_duration + dodge_cooldown
    _dodge_saved_once = false
    _play_sfx(&"swing", 1.7)
    dodged.emit(_dodge_dir)


func is_dodging() -> bool:
    return _dodge_timer > 0.0


## 血条下面那行提示。闪避冷却中才显示；以后有 A/B 在测时，预设名也放这里
func get_hud_hint() -> String:
    if _dodge_cooldown_timer > 0.0:
        return "闪避冷却中"
    return ""


## 敌人攻击命中时调用。返回 false 表示处于无敌时间、这一下没生效
func take_damage(amount: float, knockback: Vector3) -> bool:
    if _iframe_timer > 0.0:
        if not _dodge_saved_once:
            _dodge_saved_once = true
            dodge_saved.emit()
        return false
    if _invuln_timer > 0.0:
        return false
    # 弹射没有无敌：途中被打中就被打断，链结束
    if _bouncing:
        _bouncing = false
        _end_chain("hurt")
    health -= amount
    _invuln_timer = hurt_invuln_time
    _stun_timer = hurt_stun_time
    _hurt_flash_timer = hurt_flash_time
    # 直接替换速度而不是叠加：被打中那一刻原来的移动应该被打断
    velocity = knockback
    _play_sfx(&"hurt", 1.0)

    var cam := get_viewport().get_camera_3d() as FollowCamera
    if cam != null:
        cam.add_shake(hurt_camera_shake)
    var hit_stop: Node = get_node_or_null(^"/root/HitStop")
    if hit_stop != null:
        hit_stop.call(&"trigger", hurt_hitstop)

    if health <= 0.0:
        health = max_health
        defeated.emit()
    health_changed.emit(health, max_health)
    return true


## 音效走 autoload，按路径取，理由同 HitStop
func _play_sfx(sound: StringName, pitch: float) -> void:
    var sfx: Node = get_node_or_null(^"/root/Sfx")
    if sfx != null:
        sfx.call(&"play", sound, pitch)


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

    if _body_material != null:
        var t: float = _hurt_flash_timer / maxf(hurt_flash_time, 0.001)
        var color: Color = _body_base_color.lerp(hurt_flash_color, t)
        # 无敌时间内身体发白，玩家能看出"这段时间被打不到"
        if _iframe_timer > 0.0:
            color = color.lerp(Color.WHITE, 0.6)
        # 弹射窗口开着时身体发黄：窗口只有零点几秒，不提示的话玩家不知道它存在
        elif _bounce_window > 0.0:
            color = color.lerp(bounce_window_tint, 0.7)
        _body_material.albedo_color = color

    _aim_marker.visible = idle_or_charging
    if _aim_marker.visible:
        _aim_marker.position = _aim_dir * (body_radius + 0.35)

    # 标记是 top_level，直接用世界坐标挂在目标头顶
    _target_marker.visible = idle_or_charging and _target != null
    if _target_marker.visible:
        _target_marker.global_position = _target.global_position + Vector3.UP * target_marker_height

    var charging: bool = _pod_state == PodState.CHARGING

    # 蓄力的可读性靠剪影：膜朝伪足将要伸出的方向鼓起、越蓄越长。
    # 鼓在挥扫起点那一侧，顺便预告这一下从哪边扫过来
    _bulge_mesh.visible = charging
    if _bulge_mesh.visible:
        var c: float = _current_charge()
        var bulge_dir: Vector3 = _aim_dir.rotated(_swing_axis_for(_aim_dir), _swing_half_arc(c) * _swing_side)
        var width: float = lerpf(0.35, 0.6, c)
        var length: float = lerpf(0.4, bulge_max_stretch, c)
        _bulge_mesh.transform = Transform3D(
            _basis_y_to(bulge_dir) * Basis.from_scale(Vector3(width, length, width)),
            bulge_dir * (body_radius * 0.6 + length * 0.25)
        )

    _swing_preview.visible = show_reach_preview and charging
    if _swing_preview.visible:
        _draw_swing_preview(_current_reach_length(), _current_charge())

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
    return "目标: %s   上下: [%s镜头] [%s方向]   攻击俯仰 %+.0f°\n伪足: %s   蓄力 %.2f   长度 %.1f / %.1f\n速度 %.1f" % [
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
