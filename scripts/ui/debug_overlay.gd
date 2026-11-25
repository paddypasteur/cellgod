extends CanvasLayer
## 调手感用的文字面板。不是正式 HUD。

@export var player: Player

var _hits: int = 0

@onready var _label: Label = $Label


func _ready() -> void:
    if player != null:
        player.hit_landed.connect(_on_hit_landed)


func _on_hit_landed(_target: Node, _charge: float) -> void:
    _hits += 1


func _process(_delta: float) -> void:
    var text: String = "%d FPS\n" % Engine.get_frames_per_second()
    if player != null:
        text += player.get_debug_text() + "\n"
    text += "命中 %d\n" % _hits
    text += _joypad_text() + "\n\n"
    text += "手柄: 左摇杆移动  RB/LB 升/降  右摇杆瞄准  RT 按住蓄力\n"
    text += "键鼠(临时): WASD 移动  空格/Shift 升/降  鼠标瞄准  左键按住蓄力"
    _label.text = text


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
