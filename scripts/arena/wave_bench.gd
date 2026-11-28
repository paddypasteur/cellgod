class_name WaveBench
extends Node
## 波次测试台（DESIGN《波次测试台》第一步，2026-11-28）。**它是测试台，不是游戏模式**：
## 给战斗一个赌注和一个能比较的成绩。规则只有三条：
##   1 固定血量（波与波之间不回血）
##   2 死了这一局就结束
##   3 撑过 N 波，一波比一波多，全清就赢
## 刻意不做：ATP、敌人种类（第二、三步才做）、波间强化、积分、解锁、局外成长（那是另一个游戏）。
## 开发者 11-28："你要是没个目标，真不行。"
## 结束时暂停整个游戏，显示结果，按 A / 回车 / 空格重开一局

signal wave_started(index: int, count: int)
signal run_ended(won: bool, wave: int, seconds: float)

## 每一波的敌人数（从第 1 波开始）
@export var waves: PackedInt32Array = PackedInt32Array([2, 3, 4, 5, 6])
## 开局、每两波之间的间隔（秒）
@export var break_time: float = 3.0
## 新敌人出现在离玩家多远的地方（米），方向随机，上下也随机（球形战场）
@export var spawn_distance: float = 9.0
## 出生方向的上下范围：-1..1 之间的高度分量上限。1 = 正上正下都可能
@export_range(0.0, 1.0) var spawn_vertical_spread: float = 0.7
@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")

enum Phase { BREAK, FIGHT, WON, LOST }

var player: Player
## 敌人挂在哪个节点下（Arena 的 Enemies）
var enemy_parent: Node3D
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 20.0

var _phase: Phase = Phase.BREAK
var _wave: int = 0
var _alive: int = 0
var _timer: float = 0.0
var _run_time: float = 0.0
var _hud: Control


func _ready() -> void:
    # 结束时整个游戏暂停，自己（和结果画面）还得能动，才能接"再来一局"
    process_mode = Node.PROCESS_MODE_ALWAYS
    add_to_group(&"wave_bench")
    _timer = break_time
    var layer := CanvasLayer.new()
    layer.layer = 5
    add_child(layer)
    _hud = WaveBenchHud.new()
    _hud.bench = self
    layer.add_child(_hud)
    if player != null:
        player.defeated.connect(_on_player_defeated)


func _process(delta: float) -> void:
    match _phase:
        Phase.BREAK:
            _run_time += delta
            _timer -= delta
            if _timer <= 0.0:
                _start_wave()
        Phase.FIGHT:
            _run_time += delta
        Phase.WON, Phase.LOST:
            pass


func _unhandled_input(event: InputEvent) -> void:
    if _phase != Phase.WON and _phase != Phase.LOST:
        return
    if event.is_action_pressed(&"ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
        get_tree().paused = false
        get_tree().reload_current_scene()


func _start_wave() -> void:
    var count: int = waves[_wave]
    _wave += 1
    _phase = Phase.FIGHT
    _alive = count
    for i: int in count:
        _spawn_enemy()
    wave_started.emit(_wave, count)
    _log("wave", "%d/%d" % [_wave, count])


func _spawn_enemy() -> void:
    var e := enemy_scene.instantiate() as Enemy
    # 测试台里敌人死了就是死了
    e.respawn_delay = 0.0
    var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-spawn_vertical_spread, spawn_vertical_spread), randf_range(-1.0, 1.0))
    if dir.length_squared() < 0.01:
        dir = Vector3.FORWARD
    var from: Vector3 = player.global_position if player != null else arena_center
    var pos: Vector3 = from + dir.normalized() * spawn_distance
    # 不能出生在竞技场外面：拉回球内，留 2 米余量
    var off: Vector3 = pos - arena_center
    if off.length() > arena_radius - 2.0:
        pos = arena_center + off.normalized() * (arena_radius - 2.0)
    enemy_parent.add_child(e)
    e.global_position = pos
    e.died.connect(_on_enemy_died.bind(e))


func _on_enemy_died(e: Enemy) -> void:
    _alive -= 1
    # 晚一点再删：玩家这一帧可能还拿着它当目标，Enemy 死时已经退出 target 组，删掉之前有足够时间让引用失效
    get_tree().create_timer(1.0, false).timeout.connect(e.queue_free)
    if _alive > 0 or _phase != Phase.FIGHT:
        return
    if _wave >= waves.size():
        _end(true)
    else:
        _phase = Phase.BREAK
        _timer = break_time


func _on_player_defeated() -> void:
    if _phase == Phase.WON or _phase == Phase.LOST:
        return
    # 沙盒里玩家倒下会立刻满血继续；测试台里这一局到此为止，血条应该显示空的
    player.health = 0.0
    _end(false)


func _end(won: bool) -> void:
    _phase = Phase.WON if won else Phase.LOST
    run_ended.emit(won, _wave, _run_time)
    _log("run_end", "%s/%d/%.1f" % ["win" if won else "lose", _wave, _run_time])
    # 结束就停下：敌人、玩家、镜头都不再动，只剩结果画面
    get_tree().paused = true


func _log(event: String, info: String) -> void:
    var logger: Node = get_tree().get_first_node_in_group(&"playtest_logger")
    if logger != null:
        logger.call(&"log_event", event, info)


# ---------------------------------------------------------------- 给 HUD 用

func get_phase() -> Phase:
    return _phase


func get_wave() -> int:
    return _wave


func get_wave_count() -> int:
    return waves.size()


func get_alive() -> int:
    return _alive


func get_break_left() -> float:
    return _timer


func get_run_time() -> float:
    return _run_time
