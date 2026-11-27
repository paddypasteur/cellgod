extends SceneTree
## 窗口模式跑主场景，按固定时间点存截图，给看不到画面的 Claude 自查可读性用。
## 用法（会在屏幕上弹出窗口几秒）：
##   godot --path . --resolution 960x540 -s tests/screenshot.gd -- --out=输出目录
## 存：开局待机、锁定后、轻击前摇/挥扫/后摇、重击聚合/挥扫。

var _frame: int = 0
var _out_dir: String = "user://screenshots"


func _initialize() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            _out_dir = arg.trim_prefix("--out=")
    DirAccess.make_dir_recursive_absolute(_out_dir)
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    # 截图不是真人试玩，不写试玩记录，免得混进开发者的数据
    scene.get_node("PlaytestLogger").set("enabled", false)
    root.add_child(scene)


func _process(_delta: float) -> bool:
    _frame += 1
    match _frame:
        30:
            _shot("idle")
            _tap(&"lock_on")
        40:
            _shot("locked")
            _tap(&"pseudopod")
        43:
            _shot("light_windup")
        49:
            _shot("light_swing")
        58:
            _shot("light_recovery")
        100:
            _tap(&"heavy_attack")
        115:
            _shot("heavy_windup")
        130:
            _shot("heavy_swing")
        140:
            return true
    return false


func _tap(action: StringName) -> void:
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    Input.parse_input_event(ev)
    var up := InputEventAction.new()
    up.action = action
    up.pressed = false
    Input.parse_input_event(up)


func _shot(name: String) -> void:
    var path: String = _out_dir.path_join("%s.png" % name)
    root.get_viewport().get_texture().get_image().save_png(path)
    print("saved ", path)
