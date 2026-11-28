class_name WaveBenchHud
extends Control
## 波次测试台的屏幕显示：顶部"第几波 / 还剩几只 / 用时"，波间大字倒数，结束时结果画面。
## 白盒阶段直接自绘，不引入主题和贴图

var bench: WaveBench

const BIG: int = 44
const MID: int = 22
const SMALL: int = 16


func _ready() -> void:
    # 运行时才加进来的 Control，光设锚点不会撑满屏幕（尺寸还是 0），锚点和偏移要一起设
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    if bench == null:
        return
    var font: Font = ThemeDB.fallback_font
    var w: float = size.x
    var phase: WaveBench.Phase = bench.get_phase()
    var t: float = bench.get_run_time()
    var clock: String = "%d:%02d" % [int(t) / 60, int(t) % 60]
    var top: String = "第 %d / %d 波    还剩 %d 只    %s" % [maxi(bench.get_wave(), 1), bench.get_wave_count(), bench.get_alive(), clock]
    if phase == WaveBench.Phase.BREAK and bench.get_wave() == 0:
        top = "波次测试台：撑过 %d 波，死了就结束    %s" % [bench.get_wave_count(), clock]
    if phase == WaveBench.Phase.BREAK or phase == WaveBench.Phase.FIGHT:
        _text_center(font, top, 34.0, MID, Color(1, 1, 1, 0.9))
    match phase:
        WaveBench.Phase.BREAK:
            var next: int = bench.get_wave() + 1
            _text_center(font, "第 %d 波" % next, size.y * 0.32, BIG, Color(1, 1, 1))
            _text_center(font, "%.0f" % ceilf(bench.get_break_left()), size.y * 0.32 + 44.0, MID, Color(1, 1, 1, 0.8))
        WaveBench.Phase.WON, WaveBench.Phase.LOST:
            draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
            var won: bool = phase == WaveBench.Phase.WON
            var title: String = "全清！" if won else "倒下了"
            var line: String = ("%d 波全部撑过    用时 %s" % [bench.get_wave_count(), clock]) if won \
                else ("撑到第 %d / %d 波    用时 %s" % [bench.get_wave(), bench.get_wave_count(), clock])
            # 放在屏幕中间偏下：上半部分是调试面板（F1 开关）
            var y: float = size.y * 0.52
            _text_center(font, title, y, BIG, Color(1, 0.9, 0.5) if won else Color(1, 0.5, 0.5))
            _text_center(font, line, y + 50.0, MID, Color(1, 1, 1))
            _text_center(font, "按 A / 回车 / 空格 再来一局", y + 90.0, SMALL, Color(1, 1, 1, 0.8))


func _text_center(font: Font, text: String, y: float, font_size: int, color: Color) -> void:
    var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
    draw_string_outline(font, Vector2((size.x - tw) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 6, Color(0, 0, 0, 0.8))
    draw_string(font, Vector2((size.x - tw) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
