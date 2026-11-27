extends Node3D
## 白盒球形竞技场。负责把边界半径同步给主角和边界网格，
## 保证"看到的边界"和"实际的边界"永远是同一个数。

## 竞技场球体半径（米）
@export var radius: float = 20.0
@export var player: Player
## 是否保留那 8 个不动的靶子。默认不保留：它们会和敌人一起参与索敌，
## 是"锁定乱跳"的放大因素之一，现在有了真敌人，靶子只剩干扰
@export var show_dummies: bool = false

@onready var _boundary: MeshInstance3D = $Boundary


func _ready() -> void:
    if player != null:
        player.arena_center = global_position
        player.arena_radius = radius
    var sphere := _boundary.mesh as SphereMesh
    if sphere != null:
        sphere.radius = radius
        sphere.height = radius * 2.0
    var dummies: Node = get_node_or_null(^"Dummies")
    if dummies != null and not show_dummies:
        # 直接释放而不是隐藏：隐藏的靶子仍在 target 组里、仍有碰撞，会继续被索敌和挡路。
        # queue_free 要等到帧末才真正删除，先立刻退出 target 组，免得这一帧被玩家锁定、下一帧变成悬空引用
        for d: Node in dummies.get_children():
            d.remove_from_group(&"target")
        dummies.queue_free()
