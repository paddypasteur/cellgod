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
    duration_min = max(float(r["t"]) for r in rows) / 60.0
    print(f"闪避频率 {len(dodges) / max(duration_min, 0.01):.1f} 次/分钟（弹射上线后骤减 = 弹射太安全）")

    # 2026-11-27 起的记录有 bounce 列，preset 列的含义是"打击感 A/B"；
    # 之前（11-26 晚）的记录 preset 列是"弹射窗口 A 短 / B 长"，两者不能混着读
    new_format = "bounce" in (rows[0].keys() if rows else [])
    bounces = events("bounce")

    # ---- 垂直使用率（2026-11-26 策划定：闪避和弹射合起来算，同时分别报）
    def is_vertical(r: dict) -> bool:
        return abs(float(r["elev_deg"])) >= 20
    moves_3d = dodges + bounces
    if moves_3d:
        v_d = sum(map(is_vertical, dodges))
        v_b = sum(map(is_vertical, bounces))
        print(f"垂直使用率（闪避+弹射）{100 * (v_d + v_b) / len(moves_3d):.0f}%："
              f"闪避 {v_d}/{len(dodges)}，弹射 {v_b}/{len(bounces)}")

    # ---- 连招弹射
    chains = events("chain")
    if bounces or chains:
        print("—— 连招弹射 ——")
        if new_format:
            groups = [(None, "全部")]
        else:
            letters = sorted({r.get("preset") or "" for r in rows} - {""})
            groups = [(p, f"弹射窗口 {p}") for p in letters] or [(None, "全部")]
        for letter, label in groups:
            match = (lambda r: True) if letter is None else (lambda r, p=letter: r.get("preset") == p)
            sub_chains = [r for r in chains if match(r)]
            secs = sum(r["event"] == "sample" and match(r) for r in rows) * 0.5
            if not sub_chains:
                continue
            lengths = Counter(int(r["info"].split("/")[0]) for r in sub_chains)
            reasons = Counter(r["info"].split("/")[2] for r in sub_chains)
            print(f"  [{label}] 约 {secs:.0f} 秒，连招链 {len(sub_chains)} 条；"
                  f"链长（打中几下）{dict(sorted(lengths.items()))}；结束原因 {dict(reasons)}")
        # 落地后 1 秒内被打中的比例，对比"不在弹射时任意 1 秒被打中的概率"（基线）。
        # 单看落地数字没意义——可能只是当时敌人本来就在打；差值才说明"落地那一刻看不清周围"
        arrivals = [float(r["t"]) for r in events("arrive")]
        hurt_t = [float(r["t"]) for r in events("hurt")]
        if arrivals:
            hit_after = sum(any(a < h <= a + 1.0 for h in hurt_t) for a in arrivals)
            bounce_starts = [float(r["t"]) for r in bounces]
            def in_bounce_or_aftermath(t: float) -> bool:
                return any(a - 0.0 <= t <= a + 1.0 for a in arrivals) or \
                    any(b <= t <= min([a for a in arrivals if a >= b], default=b + 1.0) for b in bounce_starts)
            base = [float(r["t"]) for r in events("sample") if not in_bounce_or_aftermath(float(r["t"]))]
            base_hit = sum(any(t < h <= t + 1.0 for h in hurt_t) for t in base)
            print(f"  落地后 1 秒内被打中：{hit_after}/{len(arrivals)} = {100 * hit_after / len(arrivals):.0f}%；"
                  f"基线（不在弹射时任意 1 秒）：{100 * base_hit / max(len(base), 1):.0f}%"
                  f"（落地明显高于基线 = 落地那一刻看不清周围）")

    # ---- 打击感 A/B 与"有无弹射"（2026-11-27 起）
    if new_format:
        def segment_report(title: str, key: str, values: list, names: dict) -> None:
            print(f"—— {title} ——")
            for v in values:
                sub = [r for r in rows if r.get(key) == v]
                secs = sum(r["event"] == "sample" for r in sub) * 0.5
                if secs < 1:
                    continue
                per_min = lambda n: n / (secs / 60.0)
                attacks = [r for r in sub if r["event"] == "attack" and not r["info"].startswith("auto")]
                # 2026-11-27 之后 info 是 L1/L2…/H；之前是蓄力值（≤0.25 算轻击）
                def is_light(info: str) -> bool:
                    return info.startswith("L") if info[:1].isalpha() else float(info) <= 0.25
                light = sum(is_light(r["info"]) for r in attacks)
                heavy = len(attacks) - light
                hits = sum(r["event"] == "hit" for r in sub)
                hurts = sum(r["event"] == "hurt" for r in sub)
                dodges_n = sum(r["event"] == "dodge" for r in sub)
                # 命中后到下一次按键（攻击或闪避）的间隔；同一时刻扫中多个只算一次；超过 3 秒不算（那是停手了）
                hit_times = sorted({float(r["t"]) for r in sub if r["event"] == "hit"})
                input_times = sorted(float(r["t"]) for r in sub if r["event"] == "input")
                gaps = []
                for h in hit_times:
                    nxt = next((t for t in input_times if t > h), None)
                    if nxt is not None and nxt - h <= 3.0:
                        gaps.append(nxt - h)
                gap_txt = f"{statistics.median(gaps) * 1000:.0f} ms（{len(gaps)} 次）" if gaps else "无数据"
                print(f"  [{names.get(v, v)}] 约 {secs:.0f} 秒：轻击 {per_min(light):.1f} / 重击 {per_min(heavy):.1f} 次/分钟，"
                      f"命中 {per_min(hits):.1f} / 受击 {per_min(hurts):.1f} / 闪避 {per_min(dodges_n):.1f} 次/分钟；"
                      f"命中后到下一次按键 中位数 {gap_txt}")
                # 2026-11-27 起：每一击挥完记 result（打中没有），每套轻击连段结束记 combo（打了几段）
                results = [r for r in sub if r["event"] == "result" and not r["info"].startswith("auto")]
                if results:
                    def rate(prefix: str) -> str:
                        rs = [r for r in results if r["info"].startswith(prefix)]
                        if not rs:
                            return "—"
                        hit_n = sum(r["info"].endswith("/1") for r in rs)
                        return f"{hit_n}/{len(rs)}={100 * hit_n / len(rs):.0f}%"
                    combos = Counter(int(r["info"]) for r in sub if r["event"] == "combo")
                    print(f"      命中率 轻击 {rate('L')}，重击 {rate('H')}；"
                          f"连段长度（打了几段）{dict(sorted(combos.items()))}")
        if any(r.get("preset") for r in rows):
            segment_report("打击感 A/B", "preset", ["A", "B"], {"A": "A 原来", "B": "B 新"})
        segment_report("有无弹射（底盘自己站不站得住）", "bounce", ["0", "1"], {"0": "弹射关", "1": "弹射开"})

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
