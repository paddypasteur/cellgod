extends SceneTree
## 锁定冒烟测试（无界面）。三只冻住的敌人摆在前方：中、右、左。检查：
##   按锁定键锁上离准星最近的；锁定后攻击方向和身体朝向跟着目标；
##   镜头完整接管：目标转到画面中心区域、在头顶时镜头抬头、视野变宽、右摇杆不起作用；
##   十字键左右按画面上的左右切到相邻目标；目标没了自动解锁；再按一次解锁。
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


## 目标离画面中心多远（屏幕高度的比例）
func _screen_offset(t: Node3D) -> float:
    var cam: Camera3D = root.get_viewport().get_camera_3d()
    if cam.is_position_behind(t.global_position):
        return 99.0
    var size: Vector2 = root.get_viewport().get_visible_rect().size
    return (cam.unproject_position(t.global_position) - size * 0.5).length() / size.y


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
            # 镜头完整接管：0.8 秒内目标已在画面中心区域（左后上方的目标被转到前面）
            _check("镜头把目标转到画面中心区域", _screen_offset(_mid) < 0.25, "离中心 %.2f（屏幕高度）" % _screen_offset(_mid))
            _check("锁定时视野变宽", _cam.fov > _cam._base_fov + 5.0, "fov=%.0f" % _cam.fov)
            # 目标挪到头顶上方：镜头要跟着抬起来
            _mid.global_position = Vector3(0.0, 9.0, -4.0)
        160:
            _check("目标在上方 → 镜头抬头（从下往上看）", _cam._pitch_deg > 20.0, "pitch=%.0f°" % _cam._pitch_deg)
            _check("上方的目标也在画面中心区域", _screen_offset(_mid) < 0.25, "%.2f" % _screen_offset(_mid))
            _place()
        200:
            # 锁定时右摇杆不起作用
            _yaw_mark = _cam._yaw
            Input.action_press(&"camera_left", 1.0)
        230:
            Input.action_release(&"camera_left")
            _check("锁定时推右摇杆，镜头不被拽走", absf(rad_to_deg(_cam._yaw - _yaw_mark)) < 3.0,
                "%.1f°" % rad_to_deg(_cam._yaw - _yaw_mark))
            _check("推右摇杆也不切换目标", _p.get_lock_target() == _mid)
            _press(&"lock_next")
        231:
            _release(&"lock_next")
        232:
            _check("十字键右 = 切到画面右边那只", _p.get_lock_target() == _right, str(_p.get_lock_target()))
        250:
            _press(&"lock_next")
        251:
            _release(&"lock_next")
        252:
            _check("最右边再按右 = 不动", _p.get_lock_target() == _right)
            _press(&"lock_prev")
        253:
            _release(&"lock_prev")
        280:
            _check("十字键左 = 回到中间那只（画面上相邻的）", _p.get_lock_target() == _mid, str(_p.get_lock_target()))
            _press(&"lock_prev")
        281:
            _release(&"lock_prev")
        282:
            _check("再左 = 左边那只", _p.get_lock_target() == _left, str(_p.get_lock_target()))
            _left.remove_from_group(&"target")
        284:
            _check("目标没了自动解锁", _p.get_lock_target() == null)
            _left.add_to_group(&"target")
            _press(&"lock_on")
        285:
            _release(&"lock_on")
        286:
            _check("再锁上", _p.get_lock_target() != null)
            _press(&"lock_on")
        287:
            _release(&"lock_on")
        288:
            _check("再按一次解锁", _p.get_lock_target() == null)
            _check("锁定事件顺序", _events == ["on", "switch", "switch", "switch", "off", "on", "off"], str(_events))
            print("结果：%s" % ("全部通过" if _fails == 0 else "%d 项失败" % _fails))
            return true
    return false
