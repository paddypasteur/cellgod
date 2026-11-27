extends SceneTree
## 攻击冒烟测试（无界面），2026-11-27 起的攻击方式：连续轻击 + 独立重击，没有蓄力。
## 正前方冻住一只敌人。检查：
##   轻击按下即出手、没有伸出段；中等距离（4 米外）也打得到；连按三下打出 L1→L2→L3，连段结束报 3 段；
##   打满一套后有收招；命中会把玩家往后推（后坐力）；命中出粒子特效；
##   重击走聚合 → 伸出 → 挥扫，镜头抖比轻击明显；弹射默认关；受击档位比以前重。
## 用法：godot --headless --path . -s tests/combat_smoke.gd
## 截图检查命中特效（窗口模式，会弹窗几秒）：加 -- --out=输出目录，轻击和重击命中后各存三帧

var _frame: int = 0
var _phase: int = 0
var _pf: int = 0
var _p: Player
var _cam: FollowCamera
var _enemy: Enemy
var _kinds: Array[String] = []
var _combos: Array[int] = []
var _states: Array[String] = []
var _hit_this: bool = false
var _vel_after_hit: Vector3 = Vector3.ZERO
var _trauma_after_hit: float = -1.0
var _press_frame: int = 0
var _sweep_frame: int = -1
var _out_dir: String = ""
var _hit_frame: int = -1
var _shot_tag: String = ""


func _initialize() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            _out_dir = arg.trim_prefix("--out=")
            DirAccess.make_dir_recursive_absolute(_out_dir)
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    scene.get_node("PlaytestLogger").set("enabled", false)
    root.add_child(scene)
    _p = scene.get_node("Player")
    _cam = scene.get_node("FollowCamera")
    _enemy = scene.get_node("Enemies/EnemySide")
    for path: String in ["Enemies/EnemyAbove", "Enemies/EnemyBelow"]:
        scene.get_node(path).queue_free()
    _p.attack_launched.connect(func(k: String) -> void: _kinds.append(k))
    _p.combo_ended.connect(func(n: int) -> void: _combos.append(n))
    _p.hit_landed.connect(func(_t: Node, _s: float) -> void: _hit_this = true)


func _press(action: StringName) -> void:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    Input.parse_input_event(ev)
    Input.action_press(action)


func _check(label: String, ok: bool, detail: String = "") -> void:
    print("%s %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _reset(enemy_dist: float) -> void:
    _enemy.global_position = Vector3(0.0, 0.0, -enemy_dist)
    _enemy.health = 1000.0
    _p.global_position = Vector3.ZERO
    _p.velocity = Vector3.ZERO
    _p._facing_yaw = 0.0
    _cam._trauma = 0.0
    _states.clear()
    _hit_this = false
    _trauma_after_hit = -1.0
    _sweep_frame = -1
    _hit_frame = -1
    _pf = 0


func _track() -> void:
    var st: String = Player.PodState.keys()[_p._pod_state]
    if _states.is_empty() or _states[-1] != st:
        _states.append(st)
        if st == "SWEEPING" and _sweep_frame < 0:
            _sweep_frame = _frame
    if _hit_this and _trauma_after_hit < 0.0:
        _vel_after_hit = _p.velocity
        _trauma_after_hit = _cam._trauma
        _hit_frame = _frame
    if not _out_dir.is_empty() and _hit_frame > 0 and _frame - _hit_frame in [0, 4, 12]:
        root.get_viewport().get_texture().get_image().save_png(
            _out_dir.path_join("%s_%02d.png" % [_shot_tag, _frame - _hit_frame]))


func _fx_count() -> int:
    var n: int = 0
    for c: Node in current_scene_root().get_children():
        if c is HitFx:
            n += 1
    return n


func current_scene_root() -> Node:
    return root.get_child(root.get_child_count() - 1)


func _physics_process(_delta: float) -> bool:
    _frame += 1
    _pf += 1
    if _frame == 40:
        _enemy.set_physics_process(false)
        _check("弹射默认关闭", not _p.ability_chain_launch)
        _check("受击档位比以前重（定格 >0.06，抖 >0.6）",
            _p.tier_player_hurt.hitstop > 0.06 and _p.tier_player_hurt.camera_shake > 0.6,
            "定格 %.2f 抖 %.2f" % [_p.tier_player_hurt.hitstop, _p.tier_player_hurt.camera_shake])
        _check("轻击档位在最低（定格、抖动都低于重击）",
            _p.tier_light_hit.hitstop < _p.tier_heavy_hit.hitstop and _p.tier_light_hit.camera_shake < _p.tier_heavy_hit.camera_shake)
    if _frame < 60:
        return false

    match _phase:
        0:
            _reset(4.0)
            _shot_tag = "light"
            _press_frame = _frame
            _press(&"pseudopod")
            _phase = 1
        1:
            if _pf == 2:
                Input.action_release(&"pseudopod")
            _track()
            if _pf == 20:
                _check("轻击按下即出手、没有伸出段", not _states.has("EXTENDING") and _sweep_frame > 0,
                    "按下到开始挥 %.0f ms；%s" % [(_sweep_frame - _press_frame) * 1000.0 / 60.0, " -> ".join(_states)])
                _check("中等距离（敌人中心 4 米）打得到", _hit_this)
                _check("后坐力：命中后玩家往后退", _vel_after_hit.z > 0.5,
                    "命中后速度 z=%+.2f（敌人在 -z 方向）" % _vel_after_hit.z)
                _check("轻击命中镜头抖很小", _trauma_after_hit > 0.0 and _trauma_after_hit < 0.15, "%.2f" % _trauma_after_hit)
                _check("命中出了特效", _fx_count() > 0, "%d 个" % _fx_count())
        2:
            pass
    if _phase == 1 and _pf == 60:
        # 连按三下：每下间隔 8 帧（约 0.13 秒），都落在上一段的挥扫或收招里
        _reset(2.5)
        _kinds.clear()
        _combos.clear()
        _phase = 2
    if _phase == 2:
        if _pf in [1, 9, 17]:
            _press(&"pseudopod")
        elif _pf in [2, 10, 18]:
            Input.action_release(&"pseudopod")
        elif _pf == 50:
            _check("连按三下 = L1 → L2 → L3", _kinds == ["L1", "L2", "L3"], str(_kinds))
            _check("连段结束报 3 段", _combos == [3], str(_combos))
            _check("打满一套后有收招", _p._finisher_timer > 0.0 or _p._pod_state != Player.PodState.IDLE)
            _press(&"pseudopod")
        elif _pf == 51:
            Input.action_release(&"pseudopod")
        elif _pf == 80:
            _check("收招后再按是新的一套（L1）", _kinds.size() == 4 and _kinds[3] == "L1", str(_kinds))
            _reset(3.5)
            _shot_tag = "heavy"
            _kinds.clear()
            _press(&"heavy_attack")
            _phase = 3
    elif _phase == 3:
        if _pf == 2:
            Input.action_release(&"heavy_attack")
        _track()
        if _pf == 70:
            _check("重击：聚合 → 伸出 → 挥扫", _kinds == ["H"] and _states.has("WINDUP") and _states.has("EXTENDING"),
                " -> ".join(_states))
            _check("重击命中镜头抖比轻击明显", _trauma_after_hit > 0.2, "%.2f" % _trauma_after_hit)
            _check("重击后坐力比轻击大", _vel_after_hit.z > 3.0, "z=%+.2f" % _vel_after_hit.z)
            return true
    return false
