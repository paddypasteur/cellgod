extends Node
## 试玩记录器：开发者每次试玩自动写一份 CSV，开发 Claude 事后读出来做统计。
## 目的是用行为数据回答主观问题答不准的事，比如"他躲的时候会不会往上下躲"。
## 文件在 user://playtest/（Windows 上是 %APPDATA%/Godot/app_userdata/CellGod/playtest/）。
##
## 每行一个事件：
##   dodge     玩家闪避；elev_deg = 闪避方向的仰角（正 = 往上）
##   saved     一次攻击被闪避无敌时间躲掉
##   hurt      玩家被打中；rel_y = 打中他的敌人相对玩家的高度差
##   windup    敌人开始起手；on_screen = 起手那一刻是否在镜头视野内
##   sample    每 0.5 秒记一次玩家位置，用来算上下移动的幅度

@export var player: Player
## 关掉就不写文件
@export var enabled: bool = true
@export var sample_interval: float = 0.5

var _file: FileAccess = null
var _time: float = 0.0
var _sample_timer: float = 0.0
var _threatening: Dictionary = {}
var _last_health: float = -1.0

## 给调试面板显示的计数
var dodge_count: int = 0
var dodge_up: int = 0
var dodge_down: int = 0
var dodge_level: int = 0
var saved_count: int = 0


func _ready() -> void:
    add_to_group(&"playtest_logger")
    if not enabled or player == null:
        return
    # 无界面跑自动化测试时不写文件，免得测试数据混进开发者的试玩记录
    if DisplayServer.get_name() == "headless":
        enabled = false
        return
    DirAccess.make_dir_recursive_absolute("user://playtest")
    var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
    var path: String = "user://playtest/session_%s.csv" % stamp
    _file = FileAccess.open(path, FileAccess.WRITE)
    if _file == null:
        enabled = false
        return
    _file.store_line("t,event,x,y,z,elev_deg,rel_y,on_screen,threats")
    print("试玩记录写入 ", ProjectSettings.globalize_path(path))
    player.dodged.connect(_on_dodged)
    player.dodge_saved.connect(_on_dodge_saved)
    player.health_changed.connect(_on_health_changed)
    _last_health = player.health


func _physics_process(delta: float) -> void:
    _time += delta
    if _file == null:
        return
    _sample_timer -= delta
    if _sample_timer <= 0.0:
        _sample_timer = sample_interval
        _write("sample", 0.0, NAN, -1)
    # 轮询敌人状态找"刚开始起手"的那一帧，不改敌人代码
    var cam: Camera3D = get_viewport().get_camera_3d()
    for node: Node in get_tree().get_nodes_in_group(&"enemy"):
        var e := node as Enemy
        if e == null:
            continue
        var now: bool = e.is_threatening()
        if now and not _threatening.get(e, false):
            var on_screen: int = 1 if cam != null and cam.is_position_in_frustum(e.global_position) else 0
            _write("windup", 0.0, e.global_position.y - player.global_position.y, on_screen)
        _threatening[e] = now


func _on_dodged(direction: Vector3) -> void:
    var elev: float = rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
    dodge_count += 1
    if elev >= 20.0:
        dodge_up += 1
    elif elev <= -20.0:
        dodge_down += 1
    else:
        dodge_level += 1
    _write("dodge", elev, _nearest_threat_rel_y(), -1)


func _on_dodge_saved() -> void:
    saved_count += 1
    _write("saved", 0.0, _nearest_threat_rel_y(), -1)


func _on_health_changed(current: float, _maximum: float) -> void:
    # 回满（被击倒重置）不算受击
    if _last_health >= 0.0 and current < _last_health:
        _write("hurt", 0.0, _nearest_threat_rel_y(), -1)
    _last_health = current


func _nearest_threat_rel_y() -> float:
    var best: Enemy = null
    var best_dist: float = INF
    for node: Node in get_tree().get_nodes_in_group(&"enemy"):
        var e := node as Enemy
        if e == null or not e.is_threatening():
            continue
        var d: float = e.global_position.distance_to(player.global_position)
        if d < best_dist:
            best_dist = d
            best = e
    if best == null:
        return NAN
    return best.global_position.y - player.global_position.y


func _threat_count() -> int:
    var n: int = 0
    for node: Node in get_tree().get_nodes_in_group(&"enemy"):
        var e := node as Enemy
        if e != null and e.is_threatening():
            n += 1
    return n


func _write(event: String, elev: float, rel_y: float, on_screen: int) -> void:
    if _file == null:
        return
    var p: Vector3 = player.global_position
    _file.store_line("%.2f,%s,%.2f,%.2f,%.2f,%.1f,%s,%s,%d" % [
        _time, event, p.x, p.y, p.z, elev,
        "" if is_nan(rel_y) else "%.2f" % rel_y,
        "" if on_screen < 0 else str(on_screen),
        _threat_count(),
    ])
    # 每行都落盘：试玩可能直接关窗口，不能指望正常退出时才写
    _file.flush()


## 调试面板用
func get_summary() -> String:
    if dodge_count == 0:
        return "闪避 0 次"
    return "闪避 %d 次（水平 %d / 往上 %d / 往下 %d）  靠无敌躲掉 %d 次" % [
        dodge_count, dodge_level, dodge_up, dodge_down, saved_count]
