class_name Crosshair
extends Control
## 屏幕中心准星。索敌以"离屏幕中心最近"为准，准星就是告诉玩家中心在哪；
## 有目标被选中时变色，让玩家不用盯着目标头顶的标记也知道"这一下有人接"。

@export var player: Player

@export_group("外观")
## 每一臂的长度（像素）
@export var arm_length_px: float = 10.0
## 中心留空的半径（像素），留空是为了不挡住正中的目标
@export var gap_px: float = 5.0
## 线宽（像素）
@export var thickness_px: float = 2.0
## 没有选中目标时的颜色
@export var color_idle: Color = Color(1.0, 1.0, 1.0, 0.7)
## 选中目标时的颜色（和目标头顶的标记同色）
@export var color_targeted: Color = Color(1.0, 0.9, 0.3, 1.0)
## 画出索敌半径圈，方便调 Player 的 target_screen_radius
@export var show_target_radius: bool = false

var _targeted: bool = false


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    # 准星只是显示，不能吃掉鼠标点击
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)


func _process(_delta: float) -> void:
    var targeted: bool = player != null and player.has_target()
    if targeted != _targeted:
        _targeted = targeted
        queue_redraw()


func _draw() -> void:
    var center: Vector2 = size * 0.5
    var color: Color = color_targeted if _targeted else color_idle
    for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
        draw_line(center + dir * gap_px, center + dir * (gap_px + arm_length_px), color, thickness_px, true)
    if show_target_radius and player != null:
        var radius: float = size.y * player.target_screen_radius
        draw_arc(center, radius, 0.0, TAU, 64, Color(color, 0.3), 1.0, true)
