class_name Enemy
extends CharacterBody3D
## 原型敌人：只有一种、只有一招，用来解除"场上没有威胁"这个测试盲区。
## 行为：在玩家周围某个方位悬浮游走 → 前摇（膨胀变色）→ 朝玩家冲刺 → 硬直 → 回到游走。
## 每只敌人记住自己相对玩家的方位（上方的一直在上方、下方的一直在下方），
## 这样才能检验"被上下方的敌人攻击时反应得过来吗"。
## 刻意不做寻路、多招式、互相配合，见 CLAUDE.md《下一步》第 2 步。

enum State { APPROACH, WINDUP, ATTACK, RECOVER, HITSTUN, DEAD }

const STATE_LABELS: PackedStringArray = ["接近", "前摇", "攻击", "硬直", "受击", "死亡"]

@export_group("生命")
@export var max_health: float = 40.0
## 死后多少秒在出生点复活（方便连续测试）。0 = 不复活
@export var respawn_delay: float = 3.0

@export_group("被玩家打")
## 玩家轻点/蓄满命中时扣多少血
@export var damage_from_light: float = 8.0
@export var damage_from_heavy: float = 25.0
## 被击退的初速度（米/秒），按玩家蓄力插值
@export var knockback_light: float = 3.0
@export var knockback_heavy: float = 10.0
## 受击硬直时长（秒）
@export var hitstun_time: float = 0.35
## 前摇中被打会不会被打断。关掉 = 前摇有霸体，玩家必须躲
@export var hit_interrupts_windup: bool = true
## 冲刺中被打会不会被打断
@export var hit_interrupts_attack: bool = false
## 击退速度的衰减响应
@export var knockback_damping: float = 5.0

@export_group("游走")
@export var move_speed: float = 5.0
## 速度跟随响应。越小越"飘"
@export var acceleration: float = 3.0
## 和玩家保持的距离（米）
@export var preferred_distance: float = 5.0
## 绕玩家水平游走的角速度（度/秒）。只绕竖直轴转，所以上方的敌人始终在上方
@export var orbit_speed_deg: float = 20.0
## 离玩家的距离和 preferred_distance 相差多少以内，才允许发起攻击
@export var engage_tolerance: float = 1.5

@export_group("攻击")
## 两次攻击之间的间隔（秒），每次在范围内随机，免得几只敌人同时出手
@export var attack_cooldown_min: float = 1.5
@export var attack_cooldown_max: float = 3.5
## 同一时间最多几只敌人处于前摇或冲刺。0 = 不限制（默认：上下夹击正是要考的题，先不消掉）
@export var max_concurrent_attackers: int = 0
## 前摇时长（秒）。玩家靠它读招
@export var windup_time: float = 0.8
## 前摇进行到多少比例时锁定冲刺方向。之后玩家移动就能躲开
@export_range(0.0, 1.0) var windup_track_until: float = 0.75
## 前摇期间的移动速度倍率
@export_range(0.0, 1.0) var windup_move_scale: float = 0.2
## 冲刺速度（米/秒）
@export var lunge_speed: float = 16.0
## 冲刺距离（米）
@export var lunge_distance: float = 7.0
## 冲刺时离玩家中心多近算命中（米）。
## 必须大于 敌人半径 + 玩家半径（0.6 + 0.5 = 1.1）：两个碰撞体贴住时正好停在 1.1，等于判不中
@export var attack_hit_radius: float = 1.35
@export var attack_damage: float = 15.0
## 命中后把玩家击退的初速度（米/秒）
@export var attack_knockback: float = 9.0
## 攻击后的硬直（秒）：玩家反击的窗口
@export var recover_time: float = 0.9

@export_group("表现")
## 细胞观感（细菌族配色：暖色、病态，膜起伏更快更碎）。为空时用默认值。
## 下面的状态颜色是染在膜上的
@export var look: CellLook
## 受击形变"先脆后晃"（通用组件，每只敌人一份）。为空时用默认值
@export var hit_wobble: HitWobble
## 前摇结束时膨胀到多大
@export var windup_swell: float = 1.35
## 前摇结束时边缘高光增强到几倍：膨胀 + 变色 + 发亮，起手一眼可读
@export var windup_rim_boost: float = 2.5
## 描边分三档（2026-11-28 开发者："所有敌人都顶着醒目的黄边"等于没有重点）：
## 普通 = look 里的低调细边；被准星选中 = 中等；被锁定 = 最醒目、换成锁定色（颜色取 Player.lock_color）
@export var targeted_rim_color: Color = Color(1.0, 0.9, 0.45)
@export var targeted_rim_strength: float = 1.8
@export var targeted_rim_pixels: float = 2.5
@export var locked_rim_strength: float = 3.5
@export var locked_rim_pixels: float = 4.0
@export var color_idle: Color = Color(0.55, 0.62, 0.22)
@export var color_windup: Color = Color(1.0, 0.45, 0.1)
@export var color_attack: Color = Color(1.0, 0.15, 0.1)
@export var color_recover: Color = Color(0.3, 0.35, 0.25)
@export var color_hurt: Color = Color(1.0, 1.0, 1.0)
## 受击闪白的时长（秒）
@export var hurt_flash_time: float = 0.12
## 头顶文字里的 ↑ / ↓：比玩家高/低超过这么多米才显示。只是"看不清时的兜底"，不取代空间感知
@export var label_height_threshold: float = 1.5
## 用于竞技场边界约束的半径，要和碰撞形状一致
@export var body_radius: float = 0.6

var health: float = 0.0

var _state: State = State.APPROACH
var _state_timer: float = 0.0
var _cooldown: float = 0.0
var _flash_timer: float = 0.0
## 相对玩家的方位，游走时绕竖直轴慢慢转
var _home_dir: Vector3 = Vector3.FORWARD
var _orbit_sign: float = 1.0
var _attack_dir: Vector3 = Vector3.FORWARD
var _lunge_travelled: float = 0.0
var _attack_landed: bool = false
var _spawn_position: Vector3 = Vector3.ZERO
var _player: Player = null
var _material: ShaderMaterial = null

@onready var _visual: Node3D = $Visual
@onready var _mesh: MeshInstance3D = $Visual/Mesh
var _anim_time: float = 0.0
@onready var _label: Label3D = $StateLabel
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
    add_to_group(&"target")
    # "target" 组死了会退出（不再被索敌），"enemy" 组始终保留，供 HUD 列出全部敌人
    add_to_group(&"enemy")
    health = max_health
    _spawn_position = global_position
    _orbit_sign = 1.0 if randf() < 0.5 else -1.0
    _cooldown = randf_range(attack_cooldown_min, attack_cooldown_max)
    hit_wobble = hit_wobble.duplicate() if hit_wobble != null else HitWobble.new()
    _apply_look()
    _find_player()


func _find_player() -> void:
    _player = get_tree().get_first_node_in_group(&"player") as Player
    if _player == null:
        return
    var offset: Vector3 = global_position - _player.global_position
    if offset.length_squared() > 0.01:
        _home_dir = offset.normalized()


func get_state_label() -> String:
    return STATE_LABELS[_state]


## 正在前摇或冲刺。玩家索敌时优先选这种：扑过来的那只最该被打
func is_threatening() -> bool:
    return _state == State.WINDUP or _state == State.ATTACK


func _physics_process(delta: float) -> void:
    # 膜的动画时间按游戏时间走：命中定格时一起停住
    _anim_time += delta
    _material.set_shader_parameter(&"anim_time", _anim_time)
    var hit_stop: Node = get_node_or_null(^"/root/HitStop")
    hit_wobble.update(delta, _material, hit_stop != null and hit_stop.call(&"is_active"))
    if _player == null:
        _find_player()
        if _player == null:
            return
    _state_timer -= delta
    _flash_timer = maxf(_flash_timer - delta, 0.0)
    # 冲刺的最后一帧状态会切到硬直，但这一帧的位移仍属于冲刺，所以在状态机之前记下来
    var was_attacking: bool = _state == State.ATTACK

    match _state:
        State.APPROACH:
            _cooldown -= delta
            _steer_to_post(delta, 1.0)
            if _cooldown <= 0.0 and _in_engage_range():
                if _attack_slot_free():
                    _enter(State.WINDUP)
                else:
                    # 名额被占就稍等再试，加随机避免几只同时醒来又挤在一起
                    _cooldown = randf_range(0.2, 0.6)

        State.WINDUP:
            _steer_to_post(delta, windup_move_scale)
            if _windup_progress() < windup_track_until:
                _attack_dir = _dir_to_player()
            if _state_timer <= 0.0:
                _enter(State.ATTACK)

        State.ATTACK:
            velocity = _attack_dir * lunge_speed
            _lunge_travelled += lunge_speed * delta
            if _lunge_travelled >= lunge_distance:
                _enter(State.RECOVER)

        State.RECOVER, State.HITSTUN:
            velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-knockback_damping * delta))
            if _state_timer <= 0.0:
                _enter(State.APPROACH)

        State.DEAD:
            if respawn_delay > 0.0 and _state_timer <= 0.0:
                _respawn()
            return

    move_and_slide()
    _apply_arena_bounds()
    # 判定放在移动之后：冲刺最后一帧才贴上玩家的情况也要算到
    if was_attacking:
        _check_lunge_hit()
    _update_visuals()


# ---------------------------------------------------------------- 行为

func _enter(state: State) -> void:
    _state = state
    match state:
        State.APPROACH:
            _cooldown = randf_range(attack_cooldown_min, attack_cooldown_max)
        State.WINDUP:
            _state_timer = windup_time
            _attack_dir = _dir_to_player()
            # 3D 定位音效：在屏幕外起手的敌人，玩家也能听出它在上面还是下面
            var sfx: Node = get_node_or_null(^"/root/Sfx")
            if sfx != null:
                sfx.call(&"play_at", &"windup", global_position, windup_time)
        State.ATTACK:
            _lunge_travelled = 0.0
            _attack_landed = false
        State.RECOVER:
            _state_timer = recover_time
        State.HITSTUN:
            _state_timer = hitstun_time
        State.DEAD:
            _state_timer = respawn_delay
            velocity = Vector3.ZERO
            # 死了就不能再被索敌、被打中、挡路
            remove_from_group(&"target")
            _collision.set_deferred(&"disabled", true)
            _visual.visible = false
            _label.visible = false


func _respawn() -> void:
    global_position = _spawn_position
    health = max_health
    add_to_group(&"target")
    _collision.set_deferred(&"disabled", false)
    _visual.visible = true
    _label.visible = true
    _find_player()
    _enter(State.APPROACH)


## 朝"玩家位置 + 自己方位 × 保持距离"这个岗位飘过去，带减速到达，避免在岗位上来回震荡
func _steer_to_post(delta: float, speed_scale: float) -> void:
    _home_dir = _home_dir.rotated(Vector3.UP, deg_to_rad(orbit_speed_deg) * _orbit_sign * delta)
    var post: Vector3 = _player.global_position + _home_dir * preferred_distance
    var to_post: Vector3 = post - global_position
    var arrive: float = clampf(to_post.length() / 2.0, 0.0, 1.0)
    var desired: Vector3 = to_post.normalized() * move_speed * arrive * speed_scale
    velocity = velocity.lerp(desired, 1.0 - exp(-acceleration * delta))


## 用和玩家的距离而不是"到没到岗位"来判断：玩家贴着竞技场边缘时岗位可能在界外，永远到不了
func _in_engage_range() -> bool:
    var dist: float = global_position.distance_to(_player.global_position)
    return absf(dist - preferred_distance) <= engage_tolerance


func _attack_slot_free() -> bool:
    if max_concurrent_attackers <= 0:
        return true
    var busy: int = 0
    for node: Node in get_tree().get_nodes_in_group(&"enemy"):
        var e := node as Enemy
        if e != null and e != self and e.is_threatening():
            busy += 1
    return busy < max_concurrent_attackers


func _windup_progress() -> float:
    return clampf(1.0 - _state_timer / maxf(windup_time, 0.001), 0.0, 1.0)


func _dir_to_player() -> Vector3:
    var to: Vector3 = _player.global_position - global_position
    if to.length_squared() < 0.0001:
        return _attack_dir
    return to.normalized()


## 用距离判定而不是物理碰撞：冲刺很快，碰撞回调容易漏，距离判定简单可靠
func _check_lunge_hit() -> void:
    if _attack_landed:
        return
    if global_position.distance_to(_player.global_position) <= attack_hit_radius:
        _attack_landed = _player.take_damage(attack_damage, _attack_dir * attack_knockback)


func _apply_arena_bounds() -> void:
    var offset: Vector3 = global_position - _player.arena_center
    var limit: float = _player.arena_radius - body_radius
    if offset.length() <= limit:
        return
    var n: Vector3 = offset.normalized()
    global_position = _player.arena_center + n * limit
    var outward: float = velocity.dot(n)
    if outward > 0.0:
        velocity -= n * outward


## 玩家伪足命中时调用（和靶子同一个接口）
## contact = 接触点（世界坐标），impulse = 冲击方向（刃的运动方向）；不给时按 direction 从正面打
func take_hit(strength: float, direction: Vector3, contact: Vector3 = Vector3.INF, impulse: Vector3 = Vector3.ZERO) -> void:
    if _state == State.DEAD:
        return
    var push: Vector3 = impulse if impulse.length_squared() > 0.0001 else direction
    var point: Vector3 = contact if contact.is_finite() else global_position - direction.normalized()
    hit_wobble.hit(_mesh, point, push.normalized(), strength)
    health -= lerpf(damage_from_light, damage_from_heavy, strength)
    _flash_timer = hurt_flash_time
    if health <= 0.0:
        _enter(State.DEAD)
        return
    if _state == State.WINDUP and not hit_interrupts_windup:
        return
    if _state == State.ATTACK and not hit_interrupts_attack:
        return
    velocity = direction.normalized() * lerpf(knockback_light, knockback_heavy, strength)
    _enter(State.HITSTUN)


# ---------------------------------------------------------------- 表现

## 每只敌人一份膜材质（否则一只变色全部变色），再在杆状身体里放一个实核
func _apply_look() -> void:
    if look == null:
        look = CellLook.bacteria_default()
    _material = look.make_membrane_material()
    _mesh.material_override = _material
    var body := _mesh.mesh as CapsuleMesh
    if body != null:
        # 受击时整条要能弯：沿长度需要足够多的环，默认的环数弯不出弧线
        body = body.duplicate()
        body.rings = 24
        body.radial_segments = 32
        _mesh.mesh = body
    var core_mesh := CapsuleMesh.new()
    var r: float = (body.radius if body != null else 0.45) * look.core_scale
    core_mesh.radius = r
    core_mesh.height = maxf((body.height if body != null else 1.8) * look.core_scale, r * 2.0)
    core_mesh.material = look.make_core_material()
    var core := MeshInstance3D.new()
    core.name = "Core"
    core.mesh = core_mesh
    _mesh.add_child(core)


func _update_visuals() -> void:
    var facing: Vector3 = _attack_dir if _state == State.WINDUP or _state == State.ATTACK else _dir_to_player()
    var scale_factor: float = 1.0
    var color: Color = color_idle
    # 描边档位：普通 / 被准星选中 / 被锁定
    var rim: float = look.rim_strength
    var rim_color: Color = look.rim_color
    var rim_pixels: float = look.rim_pixels
    if _player.get_lock_target() == self:
        rim = locked_rim_strength
        rim_color = _player.lock_color
        rim_pixels = locked_rim_pixels
    elif _player.get_screen_target() == self:
        rim = targeted_rim_strength
        rim_color = targeted_rim_color
        rim_pixels = targeted_rim_pixels
    match _state:
        State.WINDUP:
            var p: float = _windup_progress()
            scale_factor = lerpf(1.0, windup_swell, p)
            color = color_idle.lerp(color_windup, p)
            rim = lerpf(rim, rim * windup_rim_boost, p)
        State.ATTACK:
            color = color_attack
        State.RECOVER, State.HITSTUN:
            color = color_recover
    if _flash_timer > 0.0:
        color = color_hurt
    _material.set_shader_parameter(&"base_color", color)
    _material.set_shader_parameter(&"rim_strength", rim)
    _material.set_shader_parameter(&"rim_color", rim_color)
    _material.set_shader_parameter(&"rim_pixels", rim_pixels)
    # 杆状身体的长轴指向攻击/玩家方向，冲刺方向一眼可读
    _visual.basis = _basis_facing(facing).scaled(Vector3.ONE * scale_factor)
    var arrow: String = ""
    var rel_y: float = global_position.y - _player.global_position.y
    if rel_y > label_height_threshold:
        arrow = "↑ "
    elif rel_y < -label_height_threshold:
        arrow = "↓ "
    _label.text = "%s%s  %d" % [arrow, STATE_LABELS[_state], ceili(health)]
    _label.modulate = color.lightened(0.3)


static func _basis_facing(dir: Vector3) -> Basis:
    # 正上/正下时 looking_at 的上方向和视线平行会报错，换一个参考上方向
    var up: Vector3 = Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
    return Basis.looking_at(dir, up)
