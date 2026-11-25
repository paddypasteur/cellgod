extends Node3D
## 高度标记：让玩家一眼看出每只敌人比自己高还是低。两种画法做 A/B，F2 / 十字键上切换：
##
## A 投到地面：主角和敌人都往下方参照地面投一个圆点，物体离圆点多远 = 它的高度。
##   问题：地面在竞技场球体下方约 22 米，镜头俯视 35° 时主角正下方的地面在画面外，
##   主角自己的圆点基本看不到（2026-11-25 截图确认）。
## B 投到玩家高度：每只敌人在"和玩家一样高"的平面上放一个圆点，再拉一根竖线连到敌人。
##   线朝上 = 比我高，朝下 = 比我低，线越长差得越多。圆点就在玩家周围，始终在画面里。

enum Mode { FLOOR, PLAYER_PLANE }

const MODE_NAMES: PackedStringArray = ["A 投到地面", "B 投到你的高度"]

@export var mode: Mode = Mode.FLOOR
## 参照地面（A 模式下圆点贴在它上面）
@export var floor_node: Node3D
@export var player_color: Color = Color(0.55, 0.95, 0.85)
@export var enemy_color: Color = Color(0.85, 1.0, 0.35)
## 圆点半径（米）
@export var marker_radius: float = 0.6
## A 模式下是否额外画竖线（B 模式总是画）
@export var floor_drop_lines: bool = false

## 被跟踪的节点 -> [圆点, 竖线]
var _markers: Dictionary = {}
var _materials: Dictionary = {}


func _ready() -> void:
    # 血条下方那行提示会收集这个组里的 get_hud_hint()
    add_to_group(&"hud_hint")


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"cycle_preset"):
        mode = (mode + 1) % MODE_NAMES.size() as Mode


func get_hud_hint() -> String:
    return "高度标记：%s（F2 / 十字键上 切换）" % MODE_NAMES[mode]


func _process(_delta: float) -> void:
    var player := get_tree().get_first_node_in_group(&"player") as Node3D
    if player == null:
        return
    var floor_y: float = (floor_node.global_position.y if floor_node != null else -22.0) + 0.05
    var tracked: Array[Node] = get_tree().get_nodes_in_group(&"player") + get_tree().get_nodes_in_group(&"enemy")
    for node: Node in tracked:
        var t := node as Node3D
        if t == null:
            continue
        if not _markers.has(t):
            _markers[t] = _create_marker(enemy_color if t is Enemy else player_color)
        var parts: Array = _markers[t]
        var dot: MeshInstance3D = parts[0]
        var line: MeshInstance3D = parts[1]
        # 死掉的敌人（退出了 target 组）不显示
        var alive: bool = not (t is Enemy) or t.is_in_group(&"target")
        var pos: Vector3 = t.global_position

        var base_y: float = floor_y
        var draw_line: bool = floor_drop_lines
        if mode == Mode.PLAYER_PLANE:
            base_y = player.global_position.y
            draw_line = true
            # B 模式下玩家自己就是参照，不需要标记
            if t == player:
                alive = false

        dot.visible = alive
        dot.global_position = Vector3(pos.x, base_y, pos.z)
        var height: float = pos.y - base_y
        line.visible = alive and draw_line and absf(height) > 0.05
        if line.visible:
            line.global_transform = Transform3D(Basis.from_scale(Vector3(1.0, absf(height), 1.0)),
                Vector3(pos.x, base_y + height * 0.5, pos.z))


func _create_marker(color: Color) -> Array:
    var material: StandardMaterial3D = _materials.get(color)
    if material == null:
        material = StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color = color
        _materials[color] = material

    var disc_mesh := CylinderMesh.new()
    disc_mesh.top_radius = marker_radius
    disc_mesh.bottom_radius = marker_radius
    disc_mesh.height = 0.02
    disc_mesh.material = material
    var dot := MeshInstance3D.new()
    dot.mesh = disc_mesh
    dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    dot.top_level = true
    add_child(dot)

    var line_mesh := CylinderMesh.new()
    line_mesh.top_radius = 0.03
    line_mesh.bottom_radius = 0.03
    line_mesh.height = 1.0
    line_mesh.material = material
    var line := MeshInstance3D.new()
    line.mesh = line_mesh
    line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    line.top_level = true
    add_child(line)
    return [dot, line]
