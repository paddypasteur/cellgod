extends SceneTree
## 受击形变"先脆后晃"冒烟测试（无界面）。检查：
##   单元：定格中调 update 不产生任何形变；定格结束后才开始弯；回弹不超过 3 次（不是果冻娃娃）；1.5 秒内停下
##   冲击系统：只改主强度所有通道一起变、单项倍率只影响一项
##   集成：真打一下——命中定格期间敌人膜上的形变参数全是 0；定格结束后出现形变；挨打后愣住不转头、之后转回来；
##         接触点在敌人身边（判定沿画面上的刃取样，刀碰到了才算）
## 用法：godot --headless --path . -s tests/hit_wobble_smoke.gd

var _fails: int = 0
var _p: Player
var _enemy: Enemy
var _frame: int = 0
var _hit_seen: bool = false
var _max_during_freeze: float = 0.0
var _max_after: float = 0.0
var _freeze_seen: bool = false
var _after_frames: int = 0
## 命中那一刻敌人的位置（之后会被击退走）
var _enemy_pos_at_hit: Vector3 = Vector3.ZERO
var _held: Vector3 = Vector3.FORWARD
var _held_drift: float = 999.0
var _final_angle: float = 999.0
var _after_time: float = 0.0


func _check(label: String, ok: bool, detail: String = "") -> void:
    print(("PASS " if ok else "FAIL ") + label + " " + detail)
    if not ok:
        _fails += 1


func _initialize() -> void:
    _unit_test()
    _impact_test()
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    scene.get_node("PlaytestLogger").set("enabled", false)
    root.add_child(scene)
    _p = scene.get_node("Player")
    _enemy = scene.get_node("Enemies/EnemySide")
    for path: String in ["Enemies/EnemyAbove", "Enemies/EnemyBelow"]:
        scene.get_node(path).queue_free()
    _p.hit_landed.connect(func(_t: Node, _s: float) -> void:
        if not _hit_seen:
            _enemy_pos_at_hit = _enemy.global_position
        _hit_seen = true)


func _unit_test() -> void:
    var w := HitWobble.new()
    var m := ShaderMaterial.new()
    m.shader = load("res://shaders/cell_membrane.gdshader")
    var mesh := Node3D.new()
    root.add_child(mesh)
    w.hit(mesh, Vector3(0.0, 0.0, -0.5), Vector3.RIGHT, 1.0)
    for i: int in 10:
        w.update(1.0 / 60.0, m, true)
    _check("单元：定格中不形变", float(m.get_shader_parameter(&"hit_bend") if m.get_shader_parameter(&"hit_bend") != null else 0.0) == 0.0)
    var crossings: int = 0
    var last_sign: float = 0.0
    var peak: float = 0.0
    var settled_at: int = -1
    for i: int in 120:
        w.update(1.0 / 60.0, m, false)
        var b: float = m.get_shader_parameter(&"hit_bend")
        peak = maxf(peak, absf(b))
        # 只数看得见的摆动（超过峰值 5%）
        if absf(b) > peak * 0.05:
            var sg: float = signf(b)
            if last_sign != 0.0 and sg != last_sign:
                crossings += 1
            last_sign = sg
        if settled_at < 0 and i > 10 and not w.is_moving():
            settled_at = i
    _check("单元：定格结束后才弯", peak > 0.1, "峰值 %.2f 米" % peak)
    _check("单元：看得见的回弹不超过 3 次", crossings <= 3, "%d 次" % crossings)
    _check("单元：2 秒内停下", settled_at >= 0, "第 %d 帧" % settled_at)
    mesh.queue_free()


## 冲击系统：只改主强度，所有通道一起变；轻击在每一项上都是最低
func _impact_test() -> void:
    var light := HitTier.make("轻", 1.0)
    var heavy := HitTier.make("重", 2.5)
    var getters: Array[String] = ["get_hitstop", "get_shake", "get_recoil", "get_knockback", "get_wobble",
        "get_particle_count", "get_particle_speed", "get_particle_size"]
    var all_up: bool = true
    for g: String in getters:
        if not float(heavy.call(g)) > float(light.call(g)):
            all_up = false
            print("   没有随强度增加：", g)
    _check("冲击系统：只改主强度，所有通道一起变大", all_up)
    _check("冲击系统：轻击定格 0.04、重击 0.12（和换系统前一样）",
        absf(light.get_hitstop() - 0.04) < 0.002 and absf(heavy.get_hitstop() - 0.12) < 0.005,
        "%.3f / %.3f" % [light.get_hitstop(), heavy.get_hitstop()])
    var cfg := ImpactConfig.new()
    cfg.recoil_base = 6.0
    light.config = cfg
    _check("冲击系统：改基准，用这份基准的档一起变", absf(light.get_recoil() - 6.0) < 0.001)
    heavy.knockback_mult = 0.5
    _check("冲击系统：单项倍率只影响那一项", heavy.get_knockback() < HitTier.make("", 2.5).get_knockback()
        and absf(heavy.get_hitstop() - HitTier.make("", 2.5).get_hitstop()) < 0.0001)


func _bend_now() -> float:
    var m: ShaderMaterial = _enemy._material
    return absf(float(m.get_shader_parameter(&"hit_bend"))) + absf(float(m.get_shader_parameter(&"hit_dent")))


# 用 _process：命中定格时物理帧停了，但 _process 还在跑，正好检查"定格期间纹丝不动"
func _process(delta: float) -> bool:
    _frame += 1
    var hit_stop: Node = root.get_node_or_null(^"HitStop")
    var frozen: bool = hit_stop != null and hit_stop.call(&"is_active")
    if _frame < 60:
        _enemy.global_position = Vector3(0.0, 0.0, -2.6)
        _enemy.velocity = Vector3.ZERO
        _p.global_position = Vector3.ZERO
        _p.velocity = Vector3.ZERO
        _p._facing_yaw = 0.0
        return false
    if _frame == 60:
        var ev := InputEventAction.new()
        ev.action = &"pseudopod"
        ev.pressed = true
        Input.parse_input_event(ev)
    if _frame == 62:
        var up := InputEventAction.new()
        up.action = &"pseudopod"
        up.pressed = false
        Input.parse_input_event(up)
    if _hit_seen and frozen:
        _freeze_seen = true
        _max_during_freeze = maxf(_max_during_freeze, _bend_now())
    if _hit_seen and not frozen and _freeze_seen:
        _after_frames += 1
        # 渲染帧比物理帧多，按游戏时间计（定格时 delta = 0）
        _after_time += delta
        _max_after = maxf(_max_after, _bend_now())
        if _after_frames == 1:
            # 定格一结束就把玩家挪到侧面：敌人在愣住期间不该转过来看
            _held = _enemy._current_facing
            _p.global_position = _enemy.global_position + Vector3(4.0, 0.0, 0.0)
        elif _after_frames > 1:
            _p.global_position = _enemy.global_position + Vector3(4.0, 0.0, 0.0)
        if _held_drift > 900.0 and _after_time >= 0.25:
            _held_drift = rad_to_deg(_enemy._current_facing.angle_to(_held))
        if _final_angle > 900.0 and _after_time >= _enemy.hit_facing_hold_time + 1.0:
            _final_angle = rad_to_deg(_enemy._current_facing.angle_to(_enemy._dir_to_player()))
    if _final_angle < 900.0 or _frame > 2000:
        _check("集成：挨打后愣住，玩家绕到侧面也不立刻转头", _held_drift < 5.0, "0.25 秒后转了 %.1f°" % _held_drift)
        _check("集成：愣完之后转回来看玩家", _final_angle < 20.0, "愣完 1 秒后还差 %.1f°" % _final_angle)
        _check("集成：打中了", _hit_seen)
        _check("集成：命中定格期间敌人纹丝不动", _freeze_seen and _max_during_freeze == 0.0, "定格中形变 %.3f" % _max_during_freeze)
        _check("集成：定格结束后才开始晃", _max_after > 0.05, "形变峰值 %.2f" % _max_after)
        var gap: float = _p._last_contact.distance_to(_enemy_pos_at_hit)
        # 敌人碰撞半径 0.6 + 判定胶囊半径 0.35 ≈ 0.95，胶囊两端是半球，接触点取在段上，所以给到 1.1
        _check("集成：接触点在敌人身边（刀碰到了才算）", gap < 1.1, "接触点离敌人中心 %.2f 米" % gap)
        print("结果：%s" % ("全部通过" if _fails == 0 else "%d 项失败" % _fails))
        return true
    return false
