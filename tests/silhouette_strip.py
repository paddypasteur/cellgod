"""把 silhouette_strip.gd 拍的单帧拼成纯色剪影条：每个 视角×招式 一行、16 帧排开。
透明通道 > 阈值的像素涂黑，其余涂白——只看形状，不看颜色和材质。
用法：python tests/silhouette_strip.py 帧目录 [输出文件] [--rows=wobble]
--rows=wobble：拼 hit_wobble_strip.gd 拍的敌人受击形变（一行 17 帧，第 0 帧是挨打前）
"""
import os
import sys

from PIL import Image, ImageDraw

# 玩家视角放前两行：合格与否以它为准，俯视只是参考
ROWS = [("game", "light"), ("game", "heavy"), ("top", "light"), ("top", "heavy")]
FRAMES = 16
CELL = 160  # 每帧缩到多大（像素）
THRESHOLD = 20


def main() -> None:
    global ROWS, FRAMES
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--rows=wobble" in sys.argv:
        ROWS = [("wobble", "hit")]
        FRAMES = 17
    src = args[0]
    out = args[1] if len(args) > 1 else os.path.join(src, "strip.png")
    label_w = 90
    sheet = Image.new("L", (label_w + FRAMES * CELL, len(ROWS) * CELL), 255)
    draw = ImageDraw.Draw(sheet)
    for r, (view, kind) in enumerate(ROWS):
        draw.text((6, r * CELL + CELL // 2 - 6), f"{kind}\n{view}", fill=0)
        for i in range(FRAMES):
            path = os.path.join(src, f"{view}_{kind}_{i:02d}.png")
            if not os.path.exists(path):
                continue
            alpha = Image.open(path).convert("RGBA").getchannel("A")
            sil = alpha.point(lambda a: 0 if a > THRESHOLD else 255)
            sil = sil.resize((CELL, CELL), Image.LANCZOS)
            x = label_w + i * CELL
            sheet.paste(sil, (x, r * CELL))
            draw.rectangle([x, r * CELL, x + CELL - 1, (r + 1) * CELL - 1], outline=200)
            draw.text((x + 3, r * CELL + 2), str(i), fill=120)
    sheet.save(out)
    print("saved", out)


if __name__ == "__main__":
    main()
