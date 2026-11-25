extends SceneTree
## 闪避冒烟测试（无界面）：往上躲、不推方向后撤、冷却、无敌帧、蓄力可闪、伪足伸出后不可闪。
## 用法：godot --headless --path . -s tests/dodge_smoke.gd

var _frame: int = 0
var _p: Player
var _saved: int = 0
var _y0: float = 0.0
var _z0: float = 0.0


func _initialize() -> void:
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    # 把敌人挪走，免得它们的攻击干扰测试
    scene.get_node("Enemies").queue_free()
    root.add_child(scene)
    _p = scene.get_node("Player")
    _p.dodge_saved.connect(func() -> void: _saved += 1)


func _press(action: StringName) -> void:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    Input.parse_input_event(ev)
    Input.action_press(action)


func _release(action: StringName) -> void:
    Input.action_release(action)


func _check(label: String, ok: bool, detail: String = "") -> void:
    print("%s %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_process(_delta: float) -> bool:
    _frame += 1
    # 预热 1 秒：开场第一帧很慢时引擎会在一帧里补跑多个物理步，
    # 按键事件要到下一个空闲帧才处理，太早的检查会读到"还没按"的状态
    var f: int = _frame - 60
    match f:
        5:
            _y0 = _p.global_position.y
            Input.action_press(&"move_up")
            _press(&"dodge")
        7:
            _check("按住上升闪避 = 往上冲", _p.is_dodging() and _p.velocity.y > 10.0, "vy=%.1f" % _p.velocity.y)
            _check("无敌帧挡住伤害", not _p.take_damage(10.0, Vector3.ZERO) and _saved == 1, "saved=%d hp=%d" % [_saved, _p.health])
        9:
            _release(&"dodge")
            _press(&"dodge")
        11:
            _check("冷却中不能连闪", _p._dodge_cooldown_timer > 0.0 and _p._dodge_timer < _p.dodge_duration - 0.05)
        30:
            Input.action_release(&"move_up")
            _check("往上移动了约 4.5 米", _p.global_position.y - _y0 > 3.5, "dy=%.2f" % (_p.global_position.y - _y0))
        80:
            _z0 = _p.global_position.z
            _release(&"dodge")
            _press(&"dodge")
        84:
            # 默认身体朝 -Z，不推方向 = 往身后（+Z）撤
            _check("不推方向 = 后撤", _p.velocity.z > 10.0, "vz=%.1f" % _p.velocity.z)
        140:
            _release(&"dodge")
            _press(&"pseudopod")
        150:
            _check("开始蓄力", _p._pod_state == Player.PodState.CHARGING)
            _press(&"dodge")
        152:
            _check("蓄力中闪避会取消蓄力", _p.is_dodging() and _p._pod_state == Player.PodState.IDLE)
            _release(&"pseudopod")
            _release(&"dodge")
        220:
            _press(&"pseudopod")
        223:
            _release(&"pseudopod")
        232:
            _check("伪足已伸出", _p._pod_state != Player.PodState.IDLE and _p._pod_state != Player.PodState.CHARGING,
                Player.PodState.keys()[_p._pod_state])
            _press(&"dodge")
        234:
            _check("伪足伸出后不能闪避", not _p.is_dodging())
            return true
    return false
