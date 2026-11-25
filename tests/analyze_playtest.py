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

    elev = [float(r["elev_deg"]) for r in events("dodge")]
    up = sum(e >= 20 for e in elev)
    down = sum(e <= -20 for e in elev)
    print(f"闪避 {len(elev)} 次：水平 {len(elev) - up - down} / 往上 {up} / 往下 {down}")
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
