extends SceneTree
## 打击感冒烟测试（无界面）。正前方 2 米冻住一只敌人，轻击和重击它。
## 检查：轻击没有伸出段、命中会抖镜头、命中会急停；重击仍有伸出段且抖得更明显；
##       弹射默认关闭时命中不开窗口；命中音已合成。
## （2026-11-27 打击感 A/B 选定 B，A 已删除，这里只测现在这一套）
## 用法：godot --headless --path . -s tests/hit_feel_smoke.gd

var _frame: int = 0
var _phase: int = 0
var _phase_frame: int = 0
var _p: Player
var _cam: FollowCamera
var _enemy: Enemy
var _states_seen: Array[String] = []
var _hits: int = 0
var _hit_seen_this_attack: bool = false
var _trauma_at_hit: float = -1.0
var _speed_before_hit: float = -1.0
var _speed_after_hit: float = -1.0
var _press_frame: int = 0
var _sweep_frame: int = -1


func _initialize() -> void:
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    root.add_child(scene)
    _p = scene.get_node("Player")
    _cam = scene.get_node("FollowCamera")
    _enemy = scene.get_node("Enemies/EnemySide")
    for path: String in ["Enemies/EnemyAbove", "Enemies/EnemyBelow"]:
        scene.get_node(path).queue_free()
    _p.hit_landed.connect(_on_hit)


func _on_hit(_t: Node, _c: float) -> void:
    _hits += 1
    _hit_seen_this_attack = true
    # 信号在 _deal_hit 里发出，此时急停还没执行；下一个物理帧再读速度
    _trauma_at_hit = -1.0


func _press(action: StringName) -> void:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    Input.parse_input_event(ev)
    Input.action_press(action)


func _check(label: String, ok: bool, detail: String = "") -> void:
    print("%s %s %s" % ["PASS" if ok else "FAIL", label, detail])


## 开始一次攻击：按住 hold_frames 帧后松开。同时推着前进，用来检验命中急停
func _start_attack(hold_frames: int) -> void:
    _enemy.global_position = Vector3(0.0, 0.0, -2.2)
    _enemy.health = _enemy.max_health
    _p.global_position = Vector3.ZERO
    _p.velocity = Vector3.ZERO
    _cam._trauma = 0.0
    _states_seen.clear()
    _hit_seen_this_attack = false
    _speed_before_hit = -1.0
    _speed_after_hit = -1.0
    _sweep_frame = -1
    _press_frame = _frame
    _press(&"pseudopod")
    _phase_frame = 0
    set_meta("hold", hold_frames)


## 跟踪攻击过程，返回 true 表示这次攻击已收回结束
func _track_attack() -> bool:
    if _phase_frame == int(get_meta("hold")):
        Input.action_release(&"pseudopod")
    var st: String = Player.PodState.keys()[_p._pod_state]
    if _states_seen.is_empty() or _states_seen[-1] != st:
        _states_seen.append(st)
        if st == "SWEEPING" and _sweep_frame < 0:
            _sweep_frame = _frame
    if _hit_seen_this_attack and _speed_after_hit < 0.0:
        _speed_after_hit = _p.velocity.length()
        _trauma_at_hit = _cam._trauma
    elif not _hit_seen_this_attack:
        _speed_before_hit = _p.velocity.length()
    return _phase_frame > 10 and st == "IDLE"


func _physics_process(_delta: float) -> bool:
    _frame += 1
    _phase_frame += 1
    if _frame == 40:
        _enemy.set_physics_process(false)
        _check("弹射默认关闭", not _p.ability_chain_launch)
        var sfx: Node = root.get_node_or_null(^"Sfx")
        _check("命中音已合成", sfx != null and (sfx.get("_streams") as Dictionary).has(&"hit_crisp"))
    if _frame < 60:
        return false

    match _phase:
        0:
            Input.action_press(&"move_forward")
            _start_attack(3)
            _phase = 1
        1:
            if _track_attack():
                _check("轻击：没有伸出段", not _states_seen.has("EXTENDING"), " -> ".join(_states_seen))
                _check("轻击：打中", _hit_seen_this_attack)
                _check("轻击：命中抖镜头（很小）", _trauma_at_hit > 0.0 and _trauma_at_hit < 0.3, "trauma=%.2f" % _trauma_at_hit)
                _check("命中急停", _speed_after_hit < _speed_before_hit * 0.5,
                    "命中前 %.2f → 命中后 %.2f 米/秒" % [_speed_before_hit, _speed_after_hit])
                _check("命中不开弹射窗口（能力关）", _p._bounce_window <= 0.0)
                print("     轻击：按下到开始挥 %.0f ms" % ((_sweep_frame - _press_frame) * 1000.0 / 60.0))
                _start_attack(40)
                _phase = 2
        2:
            if _track_attack():
                _check("重击：保留伸出段", _states_seen.has("EXTENDING"), " -> ".join(_states_seen))
                _check("重击：抖得比轻击明显", _trauma_at_hit > 0.3, "trauma=%.2f" % _trauma_at_hit)
                Input.action_release(&"move_forward")
                return true
    return false
