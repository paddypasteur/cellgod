"""统计一份试玩记录（PlaytestLogger 写的 CSV）。

用法：python tests/analyze_playtest.py [csv 路径]
不给路径就取 %APPDATA%/Godot/app_userdata/CellGod/playtest/ 里最新的一份。
高度差超过 2 米算"上方/下方"，以内算"同层"。
"""
import csv
import glob
import os
import statistics
import sys
from collections import Counter

sys.stdout.reconfigure(encoding="utf-8")


def latest_log() -> str:
    folder = os.path.join(os.environ["APPDATA"], "Godot", "app_userdata", "CellGod", "playtest")
    files = glob.glob(os.path.join(folder, "session_*.csv"))
    if not files:
        sys.exit("没有找到试玩记录")
    return max(files, key=os.path.getmtime)


def layer(rel_y: str) -> str:
    if rel_y == "":
        return "未知"
    v = float(rel_y)
    return "上方" if v > 2 else ("下方" if v < -2 else "同层")


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else latest_log()
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    events = lambda name: [r for r in rows if r["event"] == name]
    print(f"文件 {os.path.basename(path)}，时长 {max(float(r['t']) for r in rows):.0f} 秒")

    def dodge_line(dodges: list) -> str:
        elev = [float(r["elev_deg"]) for r in dodges]
        up = sum(e >= 20 for e in elev)
        down = sum(e <= -20 for e in elev)
        share = 100 * (up + down) / len(elev) if elev else 0
        return f"{len(elev)} 次：水平 {len(elev) - up - down} / 往上 {up} / 往下 {down}（垂直占 {share:.0f}%）"

    dodges = events("dodge")
    print("闪避 " + dodge_line(dodges))
    elev_all = [float(r["elev_deg"]) for r in dodges]
    if elev_all:
        steep = sum(abs(e) >= 45 for e in elev_all)
        print(f"  仰角 ≥45°（明确的垂直决策）：{steep} 次，占全部闪避 {100 * steep / len(elev_all):.0f}%")
        # 按 10° 一档的直方图。20° 左右多半是"斜着走位"的副产品，70° 以上才是明确往上/下躲；
        # 也用来判断新鲜感：试新鲜的人会按出夸张角度，真在用的人按出"刚好够躲开"的角度
        # 注意：升降是数字键（按下 = 满输入），摇杆推满时合成角正好 45°，不推摇杆只按升降就是 90°，
        # 所以角度会集中在 0 / ±45 / ±90 几个值上，不是连续分布
        print("  仰角分布（10° 一档，正 = 往上；0 那档 = -5°~+5°）：")
        def bucket(e: float) -> int:
            if abs(e) < 5:
                return 0
            return int(e // 10) * 10 if e > 0 else -int((-e) // 10) * 10
        counts = Counter(bucket(e) for e in elev_all)
        for b in sorted(counts, reverse=True):
            if b == 0:
                label = "     -5~+5"
            elif b > 0:
                label = f"{b:+4d}~{b + 10:+d}"
            else:
                label = f"{b - 10:+4d}~{b:+d}"
            print(f"    {label:>10}° {'█' * counts[b]} {counts[b]}")
    print(f"靠无敌时间躲掉 {len(events('saved'))} 次")

    hurt = events("hurt")
    print(f"受击 {len(hurt)} 次，攻击者起手位置：{dict(Counter(layer(r['rel_y']) for r in hurt))}")

    windup = events("windup")
    on = [r for r in windup if r["on_screen"] == "1"]
    print(f"敌人起手 {len(windup)} 次，起手时在屏幕内 {len(on)} 次")
    for k in ("上方", "同层", "下方"):
        group = [r for r in windup if layer(r["rel_y"]) == k]
        seen = sum(r["on_screen"] == "1" for r in group)
        print(f"  {k}：{len(group)} 次起手，其中 {seen} 次在屏幕内")
    print(f"起手时同时在出招的敌人数：{dict(sorted(Counter(r['threats'] for r in windup).items()))}")

    ys = [float(r["y"]) for r in events("sample")]
    if len(ys) > 1:
        moves = [abs(a - b) for a, b in zip(ys, ys[1:])]
        moving = sum(m > 0.5 for m in moves)
        print(f"玩家高度：{min(ys):.1f} ~ {max(ys):.1f} 米；"
              f"每 0.5 秒里有上下移动（>0.5 米）的占 {100 * moving / len(moves):.0f}%")


if __name__ == "__main__":
    main()
