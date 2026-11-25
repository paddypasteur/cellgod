extends SceneTree
## 窗口模式跑主场景，按固定时间点存截图，给看不到画面的 Claude 自查可读性用。
## 用法（会在屏幕上弹出窗口几秒）：
##   godot --path . --resolution 960x540 -s tests/screenshot.gd -- --out=输出目录 [--markers=0|1]
## --markers 选高度标记的画法（0 = 投到地面，1 = 投到玩家高度）
## 存三张：开局待机、蓄力中、挥扫中。

var _frame: int = 0
var _out_dir: String = "user://screenshots"


func _initialize() -> void:
    var markers_mode: int = -1
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            _out_dir = arg.trim_prefix("--out=")
        elif arg.begins_with("--markers="):
            markers_mode = int(arg.trim_prefix("--markers="))
    DirAccess.make_dir_recursive_absolute(_out_dir)
    var scene: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
    if markers_mode >= 0:
        scene.get_node("HeightMarkers").set("mode", markers_mode)
    # 截图不是真人试玩，不写试玩记录，免得混进开发者的数据
    scene.get_node("PlaytestLogger").set("enabled", false)
    root.add_child(scene)


func _process(_delta: float) -> bool:
    _frame += 1
    match _frame:
        30:
            _shot("idle")
            Input.action_press(&"pseudopod")
            var ev := InputEventAction.new()
            ev.action = &"pseudopod"
            ev.pressed = true
            Input.parse_input_event(ev)
        60:
            _shot("charging")
            Input.action_release(&"pseudopod")
        78:
            _shot("swing")
        90:
            return true
    return false


func _shot(name: String) -> void:
    var path: String = _out_dir.path_join("%s.png" % name)
    root.get_viewport().get_texture().get_image().save_png(path)
    print("saved ", path)
