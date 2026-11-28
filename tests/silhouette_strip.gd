extends SceneTree
## 逐帧剪影（DESIGN《攻击动作 = 全细胞惯性》的自检方法）：
## 只放一个主角，透明背景，轻击、重击各拍 16 帧，俯视和玩家视角（游戏里的默认镜头）两个角度。
## 存出带透明通道的单帧 PNG，再由 tests/silhouette_strip.py 拼成纯色剪影条。
## 用法（窗口模式，会弹窗十来秒）：
##   godot --path . --resolution 400x400 -s tests/silhouette_strip.gd -- --out=输出目录
##   python tests/silhouette_strip.py 输出目录

const FRAMES: int = 16
## 每隔几个物理帧拍一张：轻击整个动作约 0.8 秒、重击约 1.6 秒
const LIGHT_STEP: int = 3
const HEAVY_STEP: int = 6
const SETTLE: int = 90

var _out_dir: String = ""
var _vp: SubViewport
var _cam: Camera3D
var _p: Player
var _frame: int = 0
## 每一条：[视角, 招式, 起始帧]
var _plan: Array = []


func _initialize() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--out="):
            _out_dir = arg.trim_prefix("--out=")
    DirAccess.make_dir_recursive_absolute(_out_dir)
    _vp = SubViewport.new()
    _vp.size = Vector2i(400, 400)
    _vp.transparent_bg = true
    _vp.own_world_3d = true
    _vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(_vp)
    _cam = Camera3D.new()
    _vp.add_child(_cam)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
    _vp.add_child(light)
    _p = (load("res://scenes/player.tscn") as PackedScene).instantiate()
    _vp.add_child(_p)
    # 攻击的上下角度平时跟镜头俯仰走；俯视镜头会让它朝正下方打，剪影就不是游戏里的样子了
    _p.vertical_from_camera = false
    # 重击的扇形预告是半透明的辅助图形，不属于细胞本身，剪影里不要它
    _p.show_reach_preview = false
    var t: int = 60
    for view: String in ["top", "game"]:
        for kind: String in ["light", "heavy"]:
            _plan.append([view, kind, t])
            t += FRAMES * (LIGHT_STEP if kind == "light" else HEAVY_STEP) + SETTLE


func _set_view(view: String) -> void:
    if view == "top":
        _cam.projection = Camera3D.PROJECTION_ORTHOGONAL
        _cam.size = 10.0
        _cam.position = Vector3(0.0, 15.0, -1.5)
        _cam.look_at(Vector3(0.0, 0.0, -1.5), Vector3.FORWARD)
    else:
        # 玩家视角：按 arena.tscn 里 FollowCamera 的运行时默认值摆（俯角 35°、距离 7 米、注视点高 0.8 米、肩后偏移）。
        # 2026-11-28 策划指出：以前"身后"那行俯角只有 14°，和玩家看到的不是一回事。合格与否以这一行为准
        var arena: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
        var fc: FollowCamera = arena.get_node("FollowCamera")
        var pitch: float = deg_to_rad(fc.pitch_deg)
        var orbit := Basis(Vector3.RIGHT, pitch)
        var look := Vector3.UP * fc.look_height_offset + orbit.x * fc.shoulder_offset
        _cam.projection = Camera3D.PROJECTION_PERSPECTIVE
        _cam.fov = fc.fov
        _cam.position = look + orbit * Vector3(0.0, 0.0, fc.distance)
        _cam.look_at(look, Vector3.UP)
        arena.free()


func _physics_process(_delta: float) -> bool:
    _frame += 1
    _p.global_position = Vector3.ZERO
    _p.velocity = Vector3.ZERO
    for entry: Array in _plan:
        var start: int = entry[2]
        var step: int = LIGHT_STEP if entry[1] == "light" else HEAVY_STEP
        if _frame == start - 10:
            _set_view(entry[0])
        if _frame == start:
            # 主角在 SubViewport 里，收不到根视口的输入事件，直接写进它的输入缓冲
            if entry[1] == "light":
                _p._buffer_timer = 0.2
            else:
                _p._heavy_buffer = 0.2
        var k: int = _frame - start
        if k >= 0 and k % step == 0 and k / step < FRAMES:
            var img: Image = _vp.get_texture().get_image()
            img.save_png(_out_dir.path_join("%s_%s_%02d.png" % [entry[0], entry[1], k / step]))
    var last: Array = _plan[-1]
    return _frame > int(last[2]) + FRAMES * HEAVY_STEP + 5
