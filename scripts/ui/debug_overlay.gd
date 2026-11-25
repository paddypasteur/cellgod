extends CanvasLayer
## 调手感用的文字面板。不是正式 HUD。

@export var player: Player

var _hits: int = 0
var _defeats: int = 0

@onready var _label: Label = $Label


func _ready() -> void:
    if player != null:
        player.hit_landed.connect(_on_hit_landed)
        player.defeated.connect(_on_defeated)


func _on_hit_landed(_target: Node, _charge: float) -> void:
    _hits += 1


func _on_defeated() -> void:
    _defeats += 1


func _process(_delta: float) -> void:
    var text: String = "%d FPS\n" % Engine.get_frames_per_second()
    if player != null:
        text += player.get_debug_text() + "\n"
    text += "命中 %d   被击倒 %d\n" % [_hits, _defeats]
    text += _enemies_text() + "\n"
    text += _joypad_text() + "\n\n"
    text += "手柄: 左摇杆移动  RB/LB 升/降  右摇杆镜头  RT 按住蓄力（按住 RB/LB 出招 = 上挑/下砸）\n"
    text += "键鼠(临时): WASD 移动  空格/Shift 升/降  左键按住蓄力（无鼠标转镜头）"
    _label.text = text


## 头顶标签在屏幕外时看不到，这里列出全部敌人的状态，屏幕外的也能知道它在干什么
func _enemies_text() -> String:
    var parts: PackedStringArray = []
    for node: Node in get_tree().get_nodes_in_group(&"enemy"):
        var e := node as Enemy
        if e != null:
            parts.append("%s:%s" % [e.name, e.get_state_label()])
    if parts.is_empty():
        return "敌人: 无"
    return "敌人: " + "  ".join(parts)


## 列出 Godot 识别到的手柄和左右摇杆原始值，用来区分"没识别到"和"识别到但没映射上"
func _joypad_text() -> String:
    var pads: Array[int] = Input.get_connected_joypads()
    if pads.is_empty():
        return "手柄: 未检测到"
    var lines: PackedStringArray = []
    for id: int in pads:
        lines.append("手柄 #%d %s  L(%.2f, %.2f) R(%.2f, %.2f) RT %.2f" % [
            id,
            Input.get_joy_name(id),
            Input.get_joy_axis(id, JOY_AXIS_LEFT_X),
            Input.get_joy_axis(id, JOY_AXIS_LEFT_Y),
            Input.get_joy_axis(id, JOY_AXIS_RIGHT_X),
            Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y),
            Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT),
        ])
    return "\n".join(lines)
