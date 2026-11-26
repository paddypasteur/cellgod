extends SceneTree
## 连招弹射冒烟测试（无界面）。三只敌人冻住摆好：A 正前方、B 右上方、C 左下方。
## 流程：轻击打中 A → 窗口内按住上升+前推+攻击 → 弹向 B → 自动轻击打中 B →
##       窗口内按住下降+攻击 → 弹向 C → 打中 C → 窗口超时，链结束（3 下 / 弹 2 次）。
## 用法：godot --headless --path . -s tests/bounce_smoke.gd
## 截图检查镜头（窗口模式，会弹窗几秒）：
##   godot --path . --resolution 960x540 -s tests/bounce_smoke.gd -- --out=输出目录
## 每次弹射存三张：起跳、飞行途中、到达出手

var _frame: int = 0
var _phase: int = 0
var _phase_frame: int = 0
var _p: Player
var _a: Enemy
var _b: Enemy
var _c: Enemy
var _bounces: Array = []
var _strikes: Array = []
var _chains: Array = []
var _out_dir: String = ""
var _was_bouncing: bool = false
var _flight_frames: int = 0


func _initialize() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            _out_dir = arg.trim_prefix("--out=")
            DirAccess.make_dir_recursive_absolute(_out_dir)
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    scene.get_node("PlaytestLogger").set("enabled", false)
    root.add_child(scene)
    _p = scene.get_node("Player")
    _a = scene.get_node("Enemies/EnemySide")
    _b = scene.get_node("Enemies/EnemyAbove")
    _c = scene.get_node("Enemies/EnemyBelow")
    _p.bounced.connect(func(d: Vector3, i: int) -> void: _bounces.append([d, i]))
    _p.bounce_strike.connect(func(hit: bool) -> void: _strikes.append(hit))
    _p.chain_ended.connect(func(h: int, b: int, r: String) -> void: _chains.append([h, b, r]))


func _press(action: StringName) -> void:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    Input.parse_input_event(ev)
    Input.action_press(action)


func _check(label: String, ok: bool, detail: String = "") -> void:
    print("%s %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _next() -> void:
    _phase += 1
    _phase_frame = 0


func _shoot(name: String) -> void:
    if _out_dir.is_empty():
        return
    root.get_viewport().get_texture().get_image().save_png(_out_dir.path_join(name + ".png"))


func _physics_process(_delta: float) -> bool:
    _frame += 1
    _phase_frame += 1
    if _p != null:
        var bouncing: bool = _p.is_bouncing()
        if bouncing:
            _flight_frames += 1
            if _flight_frames == 1:
                _shoot("bounce%d_1_start" % _bounces.size())
            elif _flight_frames == 6:
                _shoot("bounce%d_2_flight" % _bounces.size())
        elif _was_bouncing:
            # 刚到达：自动轻击刚出手
            _shoot("bounce%d_3_arrive" % _bounces.size())
            _flight_frames = 0
        _was_bouncing = bouncing
    if _frame == 50:
        # 冻住敌人：只测弹射本身，不让它们游走和出手
        for e: Enemy in [_a, _b, _c]:
            e.set_physics_process(false)
            e.velocity = Vector3.ZERO
        _a.global_position = Vector3(0.0, 0.0, -2.0)
        _b.global_position = Vector3(3.0, 5.0, -3.0)
        _c.global_position = Vector3(-3.0, -5.0, -3.0)
        _p.global_position = Vector3.ZERO
    if _frame < 60:
        return false

    match _phase:
        0:
            _press(&"pseudopod")
            _next()
        1:
            if _phase_frame == 3:
                Input.action_release(&"pseudopod")
            if _p._bounce_window > 0.0:
                _check("轻击打中 A 后开窗口", true, "window=%.2f" % _p._bounce_window)
                Input.action_press(&"move_up")
                Input.action_press(&"move_forward")
                _press(&"pseudopod")
                _next()
            elif _phase_frame > 60:
                _check("轻击打中 A 后开窗口", false)
                return true
        2:
            if _phase_frame == 2:
                _check("窗口内 方向+攻击 = 弹射", _p.is_bouncing() and _p._bounce_target == _b,
                    "target=%s" % (_p._bounce_target.name if _p._bounce_target else "无"))
                _check("弹射没有无敌", _p._iframe_timer <= 0.0)
                Input.action_release(&"pseudopod")
                Input.action_release(&"move_up")
                Input.action_release(&"move_forward")
            if _strikes.size() >= 1:
                _check("到达 B 后自动轻击打中", _strikes[0] == true,
                    "离 B %.2f 米" % _p.global_position.distance_to(_b.global_position))
                _next()
            elif _phase_frame > 90:
                _check("到达 B 后自动轻击", false, "没有发生")
                return true
        3:
            if _p._bounce_window > 0.0 and _phase_frame > 1:
                Input.action_press(&"move_down")
                _press(&"pseudopod")
                _next()
            elif _phase_frame > 60:
                _check("打中 B 后开下一个窗口", false)
                return true
        4:
            if _phase_frame == 2:
                _check("往下弹向 C（不会弹回 A/B）", _p.is_bouncing() and _p._bounce_target == _c,
                    "target=%s" % (_p._bounce_target.name if _p._bounce_target else "无"))
                Input.action_release(&"pseudopod")
                Input.action_release(&"move_down")
            if _strikes.size() >= 2:
                _check("到达 C 后自动轻击打中", _strikes[1] == true)
                _next()
            elif _phase_frame > 90:
                _check("到达 C 后自动轻击", false, "没有发生")
                return true
        5:
            if not _chains.is_empty():
                var c: Array = _chains[0]
                _check("窗口超时后链结束：3 下 / 弹 2 次", c[0] == 3 and c[1] == 2 and c[2] == "timeout",
                    "hits=%d bounces=%d reason=%s" % [c[0], c[1], c[2]])
                var elevs: Array = _bounces.map(func(x: Array) -> float: return rad_to_deg(asin((x[0] as Vector3).y)))
                _check("弹射仰角一上一下", elevs.size() == 2 and elevs[0] > 20.0 and elevs[1] < -20.0, str(elevs))
                return true
            elif _phase_frame > 120:
                _check("链结束", false, "没有发生")
                return true
    return false
