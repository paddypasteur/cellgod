extends CanvasLayer
## 调手感用的文字面板。不是正式 HUD。

@export var player: Player
## 字号。面板只是调试用，字小一点少挡画面
@export var font_size: int = 12
## 启动时是否显示。运行中按 F1 / 手柄 View(Back) 键开关
@export var start_visible: bool = true

var _hits: int = 0
var _defeats: int = 0

@onready var _label: Label = $Label


func _ready() -> void:
    visible = start_visible
    _label.add_theme_font_size_override(&"font_size", font_size)
    if player != null:
        player.hit_landed.connect(_on_hit_landed)
        player.defeated.connect(_on_defeated)


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"toggle_debug"):
        visible = not visible


func _on_hit_landed(_target: Node, _charge: float) -> void:
    _hits += 1


func _on_defeated() -> void:
    _defeats += 1


func _process(_delta: float) -> void:
    var text: String = "%d FPS\n" % Engine.get_frames_per_second()
    if player != null:
        text += player.get_debug_text() + "\n"
    text += "命中 %d   被击倒 %d\n" % [_hits, _defeats]
    var logger: Node = get_tree().get_first_node_in_group(&"playtest_logger")
    if logger != null:
        text += str(logger.call(&"get_summary")) + "\n"
    text += _enemies_text() + "\n"
    text += _joypad_text() + "\n\n"
    text += "手柄: 左摇杆移动  LB/LT 升/降  右摇杆镜头  RT 轻击（连按出连段）  RB 重击  R3 锁定（拨右摇杆切换）  B 闪避（按住 LB/LT 可上下躲）  View 开关本面板\n"
    text += "键鼠(临时): WASD 移动  空格/Shift 升/降  左键轻击  E 重击  Q/中键锁定  右键闪避  F1 开关本面板"
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
