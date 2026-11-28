class_name HitWobble
extends Resource
## 受击形变："先脆后晃"（DESIGN《受击形变：先脆后晃》，2026-11-28）。
## "清脆"和"果冻"不矛盾，是先后关系：
##   1 定：命中定格期间纹丝不动——这里在定格结束前什么都不做
##   2 凹：定格一结束，接触点凹进去，然后慢慢鼓回来
##   3 弯：接触点被推走，离接触点越远的部分越跟不上 → 整条绕着命中点弓起（杆菌弯腰、球菌压扁，由形状自然决定）
##   4 回弹：弹回、来回两三次、一次比一次小，然后停
## 通用：只往细胞膜着色器（cell_membrane）写 hit_* 参数，不关心是哪种敌人。
## 每只敌人要用自己的一份（Enemy 会在 _ready 里 duplicate）

## 凹陷：最深多少米、影响范围（米）、鼓回来的时间常数（秒）
@export var dent_depth: float = 0.25
@export var dent_radius: float = 0.4
@export var dent_recover_time: float = 0.12
## 弯：接触点被推开多少米（形变倍率 = 1 时，约等于重击）；推力沿身体衰减的距离（米）——越小两端越跟不上、弓得越明显
@export var bend_amount: float = 0.6
@export var bend_falloff: float = 0.6
## 回弹：频率（每秒来回几次）、阻尼比。阻尼比 0.3 ≈ 看得见的回弹两三次（每次约剩上一次的 37%）；
## 0.22 时实测看得见的有 4 次，再小就是果冻娃娃
@export var bounce_hz: float = 3.0
@export_range(0.05, 1.0) var damping_ratio: float = 0.3

var _pending: bool = false
var _pending_amp: float = 0.0
var _hit_pos_local: Vector3 = Vector3.ZERO
var _hit_dir_local: Vector3 = Vector3.FORWARD
var _bend: float = 0.0
var _bend_vel: float = 0.0
var _dent_t: float = -1.0
var _dent_amp: float = 0.0


## 记一次命中。world_point = 接触点，world_dir = 冲击方向（刃的运动方向）；
## amount = 形变倍率，由冲击系统按这一击的主强度算好（HitTier.get_wobble，轻击约 0.6、重击约 1）。
## 这里不改任何形状：定格结束之后 update 才开始动
func hit(mesh: Node3D, world_point: Vector3, world_dir: Vector3, amount: float) -> void:
    var xf: Transform3D = mesh.global_transform if mesh.is_inside_tree() else mesh.transform
    var inv: Transform3D = xf.affine_inverse()
    _hit_pos_local = inv * world_point
    _hit_dir_local = (inv.basis * world_dir).normalized()
    _pending = true
    _pending_amp = maxf(amount, 0.0)


## 每个物理帧调用。frozen = 命中定格中（定格期间不动，保住"脆"）
func update(delta: float, material: ShaderMaterial, frozen: bool) -> void:
    if frozen or delta <= 0.0:
        return
    if _pending:
        _pending = false
        # 给一个初速度，让第一下的峰值约等于 bend_amount × 力度
        var w: float = TAU * bounce_hz
        _bend_vel += bend_amount * _pending_amp * w
        _dent_t = 0.0
        _dent_amp = dent_depth * _pending_amp
    var omega: float = TAU * bounce_hz
    var acc: float = -omega * omega * _bend - 2.0 * damping_ratio * omega * _bend_vel
    _bend_vel += acc * delta
    _bend += _bend_vel * delta
    var dent: float = 0.0
    if _dent_t >= 0.0:
        _dent_t += delta
        # 极短的一下凹进去（30 毫秒），然后指数鼓回来
        dent = _dent_amp * clampf(_dent_t / 0.03, 0.0, 1.0) * exp(-maxf(_dent_t - 0.03, 0.0) / maxf(dent_recover_time, 0.001))
        if _dent_t > dent_recover_time * 8.0:
            _dent_t = -1.0
    if absf(_bend) < 0.0005 and absf(_bend_vel) < 0.005:
        _bend = 0.0
        _bend_vel = 0.0
    material.set_shader_parameter(&"hit_pos", _hit_pos_local)
    material.set_shader_parameter(&"hit_dir", _hit_dir_local)
    material.set_shader_parameter(&"hit_dent", dent)
    material.set_shader_parameter(&"hit_dent_radius", dent_radius)
    material.set_shader_parameter(&"hit_bend", _bend)
    material.set_shader_parameter(&"hit_bend_falloff", bend_falloff)


func is_moving() -> bool:
    return _pending or _bend != 0.0 or _dent_t >= 0.0
