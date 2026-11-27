extends SceneTree
## 锁定冒烟测试（无界面）。三只冻住的敌人摆在前方：中、右、左。检查：
##   按锁定键锁上离准星最近的；锁定后攻击方向和身体朝向跟着目标；
##   右摇杆快速拨一下 = 切到右边的目标，且镜头基本不动；推住不放 = 转镜头，不切换；
##   镜头只是轻微偏向目标，不会被一下拽过去；目标没了自动解锁；再按一次解锁。
## 用法：godot --headless --path . -s tests/lock_smoke.gd

var _frame: int = 0
var _p: Player
var _cam: FollowCamera
var _mid: Enemy
var _right: Enemy
var _left: Enemy
var _fails: int = 0
var _yaw_mark: float = 0.0
var _events: Array[String] = []


func _initialize() -> void:
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    scene.get_node("PlaytestLogger").set("enabled", false)
    root.add_child(scene)
    _p = scene.get_node("Player")
    _cam = scene.get_node("FollowCamera")
    _mid = scene.get_node("Enemies/EnemySide")
    _right = scene.get_node("Enemies/EnemyAbove")
    _left = scene.get_node("Enemies/EnemyBelow")
    _p.lock_changed.connect(func(k: String) -> void: _events.append(k))


func _press(action: StringName) -> void:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    Input.parse_input_event(ev)
    Input.action_press(action)


func _release(action: StringName) -> void:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = false
    Input.parse_input_event(ev)
    Input.action_release(action)


func _check(label: String, ok: bool, detail: String = "") -> void:
    print(("PASS " if ok else "FAIL ") + label + " " + detail)
    if not ok:
        _fails += 1


func _place() -> void:
    _p.global_position = Vector3.ZERO
    _p.velocity = Vector3.ZERO
    _mid.global_position = Vector3(0.0, 0.0, -7.0)
    _right.global_position = Vector3(4.5, 0.0, -7.0)
    _left.global_position = Vector3(-4.5, 0.0, -7.0)


func _physics_process(_delta: float) -> bool:
    _frame += 1
    if _frame == 1:
        for e: Enemy in [_mid, _right, _left]:
            e.set_physics_process(false)
            e.health = 1000.0
    if _frame < 60:
        _place()
        return false
    match _frame:
        60:
            _check("一开始没有锁定", _p.get_lock_target() == null)
            _press(&"lock_on")
        61:
            _release(&"lock_on")
        62:
            _check("锁上离准星最近的（正中那只）", _p.get_lock_target() == _mid, str(_p.get_lock_target()))
            # 敌人被冻住了，不会自己刷新外观
            _mid._update_visuals()
            _right._update_visuals()
            var rim: Color = _mid._material.get_shader_parameter(&"rim_color")
            var rim_other: float = _right._material.get_shader_parameter(&"rim_strength")
            var rim_locked: float = _mid._material.get_shader_parameter(&"rim_strength")
            _check("被锁的描边换成锁定色、比别的亮", rim.is_equal_approx(_p.lock_color) and rim_locked > rim_other,
                "锁定 %.1f / 普通 %.1f" % [rim_locked, rim_other])
            # 把目标挪到玩家左后方，看身体和攻击方向会不会跟过去
            _mid.global_position = Vector3(-5.0, 1.5, 3.0)
        110:
            var to: Vector3 = (_mid.global_position - _p.global_position).normalized()
            _check("锁定后攻击方向对着目标", _p._aim_dir.dot(to) > 0.99, "dot=%.3f" % _p._aim_dir.dot(to))
            var fwd: Vector3 = _p._facing_basis() * Vector3.FORWARD
            _check("锁定后身体转向目标", Vector2(fwd.x, fwd.z).normalized().dot(Vector2(to.x, to.z).normalized()) > 0.95)
            # 镜头只是轻微偏向，0.8 秒内不该完全转到身后的目标
            var cam_fwd := Vector3(-sin(_cam._yaw), 0.0, -cos(_cam._yaw))
            _check("镜头没被一下拽到目标", cam_fwd.dot(Vector2(to.x, to.z).normalized().x * Vector3.RIGHT
                + Vector2(to.x, to.z).normalized().y * Vector3.BACK) < 0.9, "yaw=%.0f°" % rad_to_deg(_cam._yaw))
            _place()
            _cam._yaw = 0.0
            _cam._manual_cooldown = 0.0
        130:
            # 快速拨一下右摇杆（往右）
            _yaw_mark = _cam._yaw
            Input.action_press(&"camera_right", 1.0)
        134:
            Input.action_release(&"camera_right")
        136:
            _check("往右拨一下 = 切到右边那只", _p.get_lock_target() == _right, str(_p.get_lock_target()))
            _check("拨摇杆切换时镜头基本不动", absf(rad_to_deg(_cam._yaw - _yaw_mark)) < 3.0,
                "%.1f°" % rad_to_deg(_cam._yaw - _yaw_mark))
            _place()
            _yaw_mark = _cam._yaw
            Input.action_press(&"camera_left", 1.0)
        180:
            Input.action_release(&"camera_left")
        182:
            _check("推住右摇杆 = 转镜头张望，不切换", _p.get_lock_target() == _right, str(_p.get_lock_target()))
            _check("推住时镜头确实转了", absf(rad_to_deg(_cam._yaw - _yaw_mark)) > 20.0,
                "%.0f°" % rad_to_deg(_cam._yaw - _yaw_mark))
            _right.remove_from_group(&"target")
        184:
            _check("目标没了自动解锁", _p.get_lock_target() == null)
            _right.add_to_group(&"target")
            _press(&"lock_on")
        185:
            _release(&"lock_on")
        186:
            _check("再锁上", _p.get_lock_target() != null)
            _press(&"lock_on")
        187:
            _release(&"lock_on")
        188:
            _check("再按一次解锁", _p.get_lock_target() == null)
            _check("锁定事件顺序", _events == ["on", "switch", "off", "on", "off"], str(_events))
            print("结果：%s" % ("全部通过" if _fails == 0 else "%d 项失败" % _fails))
            return true
    return false
