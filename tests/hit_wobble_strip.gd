extends SceneTree
## 受击形变逐帧剪影：只放一只敌人，从正上方看，挨一下重击（从侧面横着打中腰）后每 3 帧拍一张，共 16 张。
## 用来自查"先脆后晃"：第 0 帧（定格中）应该和挨打前一样；之后弓起、回弹两三次、停下。
## 用法（窗口模式）：
##   godot --path . --resolution 400x400 -s tests/hit_wobble_strip.gd -- --out=输出目录
##   python tests/silhouette_strip.py 输出目录 --rows=wobble

const FRAMES: int = 16
const STEP: int = 3

var _out_dir: String = ""
var _vp: SubViewport
var _enemy: Enemy
var _frame: int = 0
var _hit_frame: int = 30


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
    var cam := Camera3D.new()
    cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    cam.size = 4.0
    # 场景树还没开始跑，look_at 用不了，直接给朝下看的朝向（屏幕上方 = -Z）
    cam.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 10.0, 0.0))
    _vp.add_child(cam)
    _enemy = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
    _vp.add_child(_enemy)
    # 没有玩家时敌人不走状态机，只跑膜和受击形变，正好拿来单独看形变


func _physics_process(_delta: float) -> bool:
    _frame += 1
    _enemy.global_position = Vector3.ZERO
    if _frame == _hit_frame:
        # 从 +X 一侧打中腰部，冲击朝 -X（刃横扫过去的方向）
        _enemy.take_hit(1.0, Vector3.LEFT, Vector3(0.45, 0.0, 0.0), Vector3.LEFT)
    var k: int = _frame - _hit_frame
    if k >= -STEP and k % STEP == 0 and k / STEP < FRAMES:
        var idx: int = k / STEP + 1
        _vp.get_texture().get_image().save_png(_out_dir.path_join("wobble_hit_%02d.png" % idx))
    return k > FRAMES * STEP + 2
