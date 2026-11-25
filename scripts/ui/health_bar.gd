class_name HealthBar
extends Control
## 屏幕底部的玩家血条。白盒阶段直接自绘，不引入主题和贴图。
## 血条下面再画一行当前 A/B 预设，调试面板关掉时开发者也知道自己在试哪一组。

@export var player: Player

@export_group("外观")
@export var bar_size: Vector2 = Vector2(320.0, 18.0)
## 血条离屏幕底边的距离（像素）
@export var bottom_margin: float = 40.0
@export var color_back: Color = Color(0.0, 0.0, 0.0, 0.5)
@export var color_fill: Color = Color(0.85, 0.25, 0.25, 0.9)
@export var color_text: Color = Color(1.0, 1.0, 1.0)
@export var font_size: int = 14


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)


func _process(_delta: float) -> void:
    # 预设随时可能被切换，血量也会变，每帧重画最省事，开销可以忽略
    queue_redraw()


func _draw() -> void:
    if player == null:
        return
    var pos := Vector2((size.x - bar_size.x) * 0.5, size.y - bottom_margin - bar_size.y)
    draw_rect(Rect2(pos, bar_size), color_back)
    var ratio: float = clampf(player.health / maxf(player.max_health, 0.001), 0.0, 1.0)
    draw_rect(Rect2(pos, Vector2(bar_size.x * ratio, bar_size.y)), color_fill)
    var text: String = "HP %d / %d" % [ceili(player.health), ceili(player.max_health)]
    draw_string(ThemeDB.fallback_font, pos + Vector2(6.0, bar_size.y - 4.0), text,
        HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color_text)
    draw_string(ThemeDB.fallback_font, pos + Vector2(0.0, bar_size.y + font_size + 6.0),
        player.get_preset_hint(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color_text)
