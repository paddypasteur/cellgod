extends Node
## 原型期的默认按键。
## 只在 项目设置→输入映射 里没有同名动作时才注册，
## 所以开发者在编辑器里定义的键位永远优先，这里只是兜底。
##
## 手柄：左摇杆移动，LB/LT 上升/下降，右摇杆转镜头，RT 按住蓄力，B 闪避
## 键鼠（临时占位，方案未定）：WASD 移动，空格/Shift 上升/下降，左键按住蓄力，右键闪避；
##       暂时没有鼠标转镜头

const DEFAULT_DEADZONE: float = 0.2
## 代码 new() 出来的事件 device 默认是 0，只匹配 0 号设备；
## Windows 上 Xbox 手柄不一定是 0 号（有虚拟手柄驱动时常被挤到后面），
## 所以统一改成 -1 = 所有设备，和编辑器里配键位的默认行为一致
const ALL_DEVICES: int = -1


func _enter_tree() -> void:
    # 用 _enter_tree 而不是 _ready，保证主场景里的节点 _ready 时动作已经存在
    _add_action(&"move_left", [_key(KEY_A), _joy_axis(JOY_AXIS_LEFT_X, -1.0)])
    _add_action(&"move_right", [_key(KEY_D), _joy_axis(JOY_AXIS_LEFT_X, 1.0)])
    _add_action(&"move_forward", [_key(KEY_W), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
    _add_action(&"move_back", [_key(KEY_S), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
    # 上下移动全放左手食指（LB 上 / LT 下）：原来上升在 RB，往上闪避要右手同时按 RB + B，
    # 而右拇指还要管镜头，等于"往上躲"和"看画面"二选一（2026-11-25 改）
    _add_action(&"move_up", [_key(KEY_SPACE), _joy_button(JOY_BUTTON_LEFT_SHOULDER)])
    _add_action(&"move_down", [_key(KEY_SHIFT), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])

    _add_action(&"camera_left", [_joy_axis(JOY_AXIS_RIGHT_X, -1.0)])
    _add_action(&"camera_right", [_joy_axis(JOY_AXIS_RIGHT_X, 1.0)])
    _add_action(&"camera_up", [_joy_axis(JOY_AXIS_RIGHT_Y, -1.0)])
    _add_action(&"camera_down", [_joy_axis(JOY_AXIS_RIGHT_Y, 1.0)])

    _add_action(&"toggle_debug", [_key(KEY_F1), _joy_button(JOY_BUTTON_BACK)])
    # A/B 预设切换（当前：打击感 A/B）和能力开关（当前：弹射），给开发者当场对比用
    _add_action(&"cycle_preset", [_key(KEY_F2), _joy_button(JOY_BUTTON_DPAD_UP)])
    _add_action(&"toggle_ability", [_key(KEY_F3), _joy_button(JOY_BUTTON_DPAD_DOWN)])
    # 闪避：手柄 B（类魂惯例），键鼠临时用右键
    _add_action(&"dodge", [_mouse(MOUSE_BUTTON_RIGHT), _joy_button(JOY_BUTTON_B)])

    _add_action(&"pseudopod", [_mouse(MOUSE_BUTTON_LEFT), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])


func _add_action(action: StringName, events: Array) -> void:
    if InputMap.has_action(action):
        return
    InputMap.add_action(action, DEFAULT_DEADZONE)
    for e: InputEvent in events:
        e.device = ALL_DEVICES
        InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
    var e := InputEventKey.new()
    # 物理键位：换键盘布局（AZERTY 等）时 WASD 仍在同一个位置
    e.physical_keycode = code
    return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
    var e := InputEventMouseButton.new()
    e.button_index = button
    return e


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
    var e := InputEventJoypadButton.new()
    e.button_index = button
    return e


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
    var e := InputEventJoypadMotion.new()
    e.axis = axis
    e.axis_value = value
    return e
