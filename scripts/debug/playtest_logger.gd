extends Node
## 试玩记录器：开发者每次试玩自动写一份 CSV，开发 Claude 事后读出来做统计。
## 目的是用行为数据回答主观问题答不准的事，比如"他躲的时候会不会往上下躲"。
## 文件在 user://playtest/（Windows 上是 %APPDATA%/Godot/app_userdata/CellGod/playtest/）。
##
## 每行一个事件：
##   dodge     玩家闪避；elev_deg = 闪避方向的仰角（正 = 往上）
##   saved     一次攻击被闪避无敌时间躲掉
##   hurt      玩家被打中；rel_y = 打中他的敌人**起手时**相对玩家的高度差
##             （不能用命中那一刻的高度：冲刺已经扑到玩家身边，永远接近 0）
##   windup    敌人开始起手；on_screen = 起手那一刻是否在镜头视野内
##   sample    每 0.5 秒记一次玩家位置，用来算上下移动的幅度
##   bounce    玩家弹射；elev_deg = 朝目标方向的仰角；info = 本链第几次弹射
##   strike    弹射到达后的自动轻击结束；info = 1 打中 / 0 落空（经常落空 = 到达时是懵的）
##   chain     一条连招链结束；info = "打中几下/弹射几次/结束原因"
##   arrive    弹射飞到目标身边（算"落地后 1 秒内被打中"用）
##   attack    玩家出了一击；info = L1/L2/L3…（轻击第几段）、H（重击）、auto（弹射到达后的自动轻击）。
##             2026-11-27 之前的记录这里是蓄力值（≤0.25 算轻击）
##   result    一击挥完；info = "类型/1 或 0"（打中没有），算命中率用
##   combo     一套轻击连段结束；info = 这套打了几段
##   hit       打中一个目标；info = 力度（轻 0 / 重 1）
##   lock      锁定状态变化；info = on / off / switch
##   wave      波次测试台：第几波开始；info = 波次/该波敌人数
##   run_end   一局结束；info = win|lose/到第几波/用时秒数
## sample 的 info = L 表示当时处于锁定状态；hurt 的 info = locked 表示挨打时处于锁定状态
##   input     玩家按下攻击或闪避；info = 动作名（算"命中后到下一次输入的间隔"用）
## preset 列 = 当时在测的 A/B（2026-11-28 刃的软/硬 A/B 删除后暂时为空）；bounce 列 = 弹射能力开（1）/关（0）
##   chain 的结束原因 no_target = 窗口里推了方向按了攻击，但锥形里没目标（想弹没弹出来）

@export var player: Player
## 关掉就不写文件
@export var enabled: bool = true
@export var sample_interval: float = 0.5

var _file: FileAccess = null
var _time: float = 0.0
var _sample_timer: float = 0.0
var _threatening: Dictionary = {}
## 每只敌人最近一次起手时的相对高度
var _windup_rel_y: Dictionary = {}
var _last_health: float = -1.0
var _held: Dictionary = {}

## 给调试面板显示的计数
var dodge_count: int = 0
var dodge_up: int = 0
var dodge_down: int = 0
var dodge_level: int = 0
var saved_count: int = 0
var bounce_count: int = 0
var chain_count: int = 0
var longest_chain: int = 0


func _ready() -> void:
    add_to_group(&"playtest_logger")
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
    _file.store_line("t,event,x,y,z,elev_deg,rel_y,on_screen,threats,preset,info,bounce")
    print("试玩记录写入 ", ProjectSettings.globalize_path(path))
    player.dodged.connect(_on_dodged)
    player.dodge_saved.connect(_on_dodge_saved)
    player.bounced.connect(_on_bounced)
    player.bounce_strike.connect(_on_bounce_strike)
    player.chain_ended.connect(_on_chain_ended)
    player.bounce_arrived.connect(func() -> void: _write("arrive", 0.0, NAN, -1))
    player.attack_launched.connect(func(kind: String) -> void: _write("attack", 0.0, NAN, -1, kind))
    player.attack_resolved.connect(func(kind: String, hit: bool) -> void:
        _write("result", 0.0, NAN, -1, "%s/%d" % [kind, 1 if hit else 0]))
    player.lock_changed.connect(func(kind: String) -> void: _write("lock", 0.0, NAN, -1, kind))
    player.combo_ended.connect(func(length: int) -> void: _write("combo", 0.0, NAN, -1, str(length)))
    player.hit_landed.connect(func(_t: Node, charge: float) -> void: _write("hit", 0.0, NAN, -1, "%.2f" % charge))
    player.health_changed.connect(_on_health_changed)
    _last_health = player.health


func _physics_process(delta: float) -> void:
    _time += delta
    if _file == null:
        return
    _sample_timer -= delta
    if _sample_timer <= 0.0:
        _sample_timer = sample_interval
        _write("sample", 0.0, NAN, -1, "L" if player.get_lock_target() != null else "")
    # 轮询敌人状态找"刚开始起手"的那一帧，不改敌人代码
    var cam: Camera3D = get_viewport().get_camera_3d()
    for node: Node in get_tree().get_nodes_in_group(&"enemy"):
        var e := node as Enemy
        if e == null:
            continue
        var now: bool = e.is_threatening()
        if now and not _threatening.get(e, false):
            var on_screen: int = 1 if cam != null and cam.is_position_in_frustum(e.global_position) else 0
            var rel_y: float = e.global_position.y - player.global_position.y
            _windup_rel_y[e] = rel_y
            _write("windup", 0.0, rel_y, on_screen)
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


## 用 _input 而不是 _unhandled_input：记录器只旁听，不能和玩家抢事件
func _input(event: InputEvent) -> void:
    if _file == null:
        return
    for pair: Array in [[&"pseudopod", "attack"], [&"heavy_attack", "heavy"], [&"dodge", "dodge"]]:
        var action: StringName = pair[0]
        if not event.is_action(action):
            continue
        # 只记"从没按到按下"的那一刻：扳机拉一次会上报好几次 is_action_pressed（见 Player._is_fresh_press）。
        # 2026-11-27 之前的记录里 input 事件因此偏多
        if event.is_action_released(action):
            _held.erase(action)
        elif event.is_action_pressed(action) and not _held.has(action):
            _held[action] = true
            _write("input", 0.0, NAN, -1, pair[1])


func _on_bounced(direction: Vector3, chain_index: int) -> void:
    bounce_count += 1
    var elev: float = rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
    _write("bounce", elev, NAN, -1, str(chain_index))


func _on_bounce_strike(hit: bool) -> void:
    _write("strike", 0.0, NAN, -1, "1" if hit else "0")


func _on_chain_ended(hits: int, bounces: int, reason: String) -> void:
    chain_count += 1
    longest_chain = maxi(longest_chain, hits)
    _write("chain", 0.0, NAN, -1, "%d/%d/%s" % [hits, bounces, reason])


func _on_dodge_saved() -> void:
    saved_count += 1
    _write("saved", 0.0, _nearest_threat_rel_y(), -1)


func _on_health_changed(current: float, _maximum: float) -> void:
    # 回满（被击倒重置）不算受击
    if _last_health >= 0.0 and current < _last_health:
        var attacker: Enemy = _nearest_threat()
        var rel_y: float = NAN
        if attacker != null:
            rel_y = _windup_rel_y.get(attacker, attacker.global_position.y - player.global_position.y)
        _write("hurt", 0.0, rel_y, -1, "locked" if player.get_lock_target() != null else "")
    _last_health = current


func _nearest_threat() -> Enemy:
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
    return best


func _nearest_threat_rel_y() -> float:
    var best: Enemy = _nearest_threat()
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


func _write(event: String, elev: float, rel_y: float, on_screen: int, info: String = "") -> void:
    if _file == null:
        return
    var p: Vector3 = player.global_position
    _file.store_line("%.2f,%s,%.2f,%.2f,%.2f,%.1f,%s,%s,%d,%s,%s,%d" % [
        _time, event, p.x, p.y, p.z, elev,
        "" if is_nan(rel_y) else "%.2f" % rel_y,
        "" if on_screen < 0 else str(on_screen),
        _threat_count(),
        "",
        info,
        1 if player.ability_chain_launch else 0,
    ])
    # 每行都落盘：试玩可能直接关窗口，不能指望正常退出时才写
    _file.flush()


## 给别的系统（波次测试台）记一条事件
func log_event(event: String, info: String) -> void:
    _write(event, 0.0, NAN, -1, info)


## 调试面板用
func get_summary() -> String:
    return "闪避 %d 次（水平 %d / 往上 %d / 往下 %d）  靠无敌躲掉 %d 次   弹射 %d 次  连招 %d 条（最长 %d 下）" % [
        dodge_count, dodge_level, dodge_up, dodge_down, saved_count, bounce_count, chain_count, longest_chain]
