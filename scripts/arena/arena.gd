extends Node3D
## 白盒球形竞技场。只负责把边界半径同步给主角和边界网格，
## 保证"看到的边界"和"实际的边界"永远是同一个数。

## 竞技场球体半径（米）
@export var radius: float = 20.0
@export var player: Player

@onready var _boundary: MeshInstance3D = $Boundary


func _ready() -> void:
    if player != null:
        player.arena_center = global_position
        player.arena_radius = radius
    var sphere := _boundary.mesh as SphereMesh
    if sphere != null:
        sphere.radius = radius
        sphere.height = radius * 2.0
