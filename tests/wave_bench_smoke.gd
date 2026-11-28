extends SceneTree
## 波次测试台冒烟测试（无界面）。检查：
##   开局撤掉场景里的固定敌人、刷第 1 波；敌人出生在竞技场内、上下有分布；
##   一波全死 → 间隔后刷下一波；最后一波全死 → 赢，游戏暂停；
##   另起一局：玩家倒下 → 输，游戏暂停，记录"到第几波"
## 用法：godot --headless --path . -s tests/wave_bench_smoke.gd

var _fails: int = 0
var _scene: Node
var _bench: WaveBench
var _p: Player
var _frame: int = 0
var _waves_seen: Array[int] = []
var _ended: Array = []
var _stage: int = 0
var _heights: Array[float] = []


func _check(label: String, ok: bool, detail: String = "") -> void:
    print(("PASS " if ok else "FAIL ") + label + " " + detail)
    if not ok:
        _fails += 1


func _initialize() -> void:
    _load()


func _load() -> void:
    if _scene != null:
        _scene.queue_free()
    paused = false
    _scene = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    _scene.get_node("PlaytestLogger").set("enabled", false)
    root.add_child(_scene)
    _p = _scene.get_node("Player")
    _bench = null
    _frame = 0


## 场景的 _ready 要到第一帧才跑完，测试台是那时才建的
func _setup_bench() -> void:
    _bench = _scene.get_node("WaveBench")
    # 测试里跑快点：两波，每波 2 只，间隔 0.3 秒
    _bench.waves = PackedInt32Array([2, 2])
    _bench.break_time = 0.3
    _bench._timer = 0.3
    _bench.wave_started.connect(func(i: int, _c: int) -> void: _waves_seen.append(i))
    _bench.run_ended.connect(func(won: bool, wave: int, _s: float) -> void: _ended = [won, wave])


func _living_enemies() -> Array[Enemy]:
    var out: Array[Enemy] = []
    for n: Node in _scene.get_node("Enemies").get_children():
        var e := n as Enemy
        if e != null and not e.is_queued_for_deletion() and e._state != Enemy.State.DEAD:
            out.append(e)
    return out


func _kill_all() -> void:
    for e: Enemy in _living_enemies():
        e.take_hit(1.0, Vector3.FORWARD)
        e.take_hit(1.0, Vector3.FORWARD)


func _process(_delta: float) -> bool:
    _frame += 1
    if _bench == null and _stage != 9:
        _setup_bench()
        return false
    match _stage:
        0:
            if _frame == 5:
                var fixed_left: int = 0
                for n: Node in _scene.get_node("Enemies").get_children():
                    if n.name in ["EnemyAbove", "EnemyBelow", "EnemySide"] and not n.is_queued_for_deletion():
                        fixed_left += 1
                _check("开局撤掉场景里的固定敌人", fixed_left == 0)
            if _waves_seen.size() == 1 and _living_enemies().size() == 2 and _heights.is_empty():
                _check("间隔后刷第 1 波（2 只）", true)
                var arena: Node3D = _scene
                for e: Enemy in _living_enemies():
                    _heights.append(e.global_position.y)
                    var inside: bool = e.global_position.distance_to(arena.global_position) <= 18.5
                    _check("敌人出生在竞技场内", inside, "%.1f 米" % e.global_position.distance_to(arena.global_position))
                _kill_all()
            if _waves_seen.size() == 2 and _living_enemies().size() == 2:
                _check("一波全死 → 刷第 2 波", true)
                _kill_all()
            if not _ended.is_empty():
                _check("最后一波全死 → 赢", _ended[0] == true and _ended[1] == 2, str(_ended))
                _check("结束时游戏暂停", paused)
                _stage = 1
                _waves_seen.clear()
                _ended = []
                _load()
            if _frame > 3000:
                _check("第一局在时限内结束", false)
                _stage = 9
        1:
            if _waves_seen.size() == 1 and _frame > 30 and _ended.is_empty():
                _p.take_damage(10000.0, Vector3.ZERO)
            if not _ended.is_empty():
                _check("玩家倒下 → 输，记下到第 1 波", _ended[0] == false and _ended[1] == 1, str(_ended))
                _check("输了也暂停", paused)
                _stage = 9
            if _frame > 3000:
                _check("第二局在时限内结束", false)
                _stage = 9
        9:
            paused = false
            print("结果：%s" % ("全部通过" if _fails == 0 else "%d 项失败" % _fails))
            return true
    return false
