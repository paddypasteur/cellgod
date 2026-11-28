extends SceneTree
## 锁定稳定性统计（无界面）：玩家原地反复蓄力出招 30 秒，敌人照常游走攻击，
## 统计目标切换次数，以及"切走后 0.5 秒内又切回来"的次数——后者就是开发者说的"乱跳"。
## 用法：godot --headless --path . -s tests/lock_stability.gd -- --preset=0

const DURATION_FRAMES: int = 60 * 30
const FLIP_WINDOW_FRAMES: int = 30

var _frame: int = 0
var _player: Node = null
var _last_target: Object = null
var _prev_target: Object = null
var _last_switch_frame: int = -1000
var _switches: int = 0
var _flipbacks: int = 0
var _frames_with_target: int = 0


func _initialize() -> void:
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    # 冒烟测试在沙盒里跑（固定的 3 只敌人），不开波次测试台
    scene.set("wave_mode", false)
    root.add_child(scene)
    _player = scene.get_node("Player")
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--preset=") and "lock_preset" in _player:
            _player.set("lock_preset", int(arg.trim_prefix("--preset=")))


func _physics_process(_delta: float) -> bool:
    _frame += 1
    # 每 1.2 秒一个循环：按住 0.6 秒蓄力，松开等 0.6 秒
    var phase: int = _frame % 72
    if phase == 1:
        Input.action_press(&"pseudopod")
        var ev := InputEventAction.new()
        ev.action = &"pseudopod"
        ev.pressed = true
        Input.parse_input_event(ev)
    elif phase == 37:
        Input.action_release(&"pseudopod")

    var t: Object = _player.get("_target")
    if t != null:
        _frames_with_target += 1
    if t != _last_target:
        if t != null and _last_target != null:
            _switches += 1
            if t == _prev_target and _frame - _last_switch_frame <= FLIP_WINDOW_FRAMES:
                _flipbacks += 1
            _prev_target = _last_target
            _last_switch_frame = _frame
        _last_target = t

    if _frame >= DURATION_FRAMES:
        print("有目标的时间占比 %.0f%%   目标之间直接切换 %d 次   其中半秒内切回原目标（乱跳）%d 次" % [
            100.0 * _frames_with_target / DURATION_FRAMES, _switches, _flipbacks])
        return true
    return false
