#!/usr/bin/env python3
"""生成済みパック（out/pack.sqlite）に対して、H3 index → feature_id 橋渡し方式
（下位52bitマスク。docs/terrain.md §4.4・hex_bridge.py）の性質を検証する。

確認する項目（Issue #38・2026-09-08 代表決定の要求事項）:
  1. hex_id（H3 index）が2**63未満で、SQLiteのINTEGER(64bit符号付き)にそのまま入ること
  2. 全ヘクスの上位12bit（reserved+mode+resolution）が単一の定数であること
     （＝同一パック内は単一解像度であるという前提が成り立っていること）
  3. feature_id（下位52bitマスク後）が2**53未満で、JSONの安全整数に収まること
  4. feature_id がパック内で衝突していないこと（hex_terrain.feature_id の UNIQUE INDEX が
     書き込み時点でも保証している。本スクリプトはそれを実行時にも再確認する）
  5. (header << 52) | feature_id で元の hex_id に復元できること（可逆性）

使い方:
    ./.venv/bin/python verify_feature_id.py [--db out/pack.sqlite]
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

from hex_bridge import FEATURE_ID_BITS, feature_id_to_h3, h3_to_feature_id, header_bits_of

HERE = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(HERE / "out" / "pack.sqlite"))
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        print(f"DB not found: {db_path}. 先に classify_terrain.py を実行してください。", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(str(db_path))
    rows = conn.execute("SELECT hex_id, feature_id FROM hex_terrain").fetchall()
    conn.close()

    if not rows:
        print("hex_terrain が空です。", file=sys.stderr)
        sys.exit(1)

    hex_ids = [r[0] for r in rows]
    feature_ids_stored = [r[1] for r in rows]
    n = len(rows)

    ok = True

    max_hex_id = max(hex_ids)
    check1 = max_hex_id < (1 << 63)
    print(f"[1] hex_id が2**63未満か: max={max_hex_id} -> {'OK' if check1 else 'NG'}")
    ok &= check1

    headers = {header_bits_of(h) for h in hex_ids}
    check2 = len(headers) == 1
    print(f"[2] 全ヘクスの上位ヘッダビットが単一定数か: {sorted(headers)} -> {'OK' if check2 else 'NG'}")
    ok &= check2

    recomputed_feature_ids = [h3_to_feature_id(h) for h in hex_ids]
    check3a = recomputed_feature_ids == feature_ids_stored
    print(f"[3a] SQLite保存済みfeature_idとhex_bridge.h3_to_feature_id()の再計算が一致するか: "
          f"{'OK' if check3a else 'NG'}")
    ok &= check3a

    max_feature_id = max(feature_ids_stored)
    check3b = max_feature_id < (1 << 53) - 1
    print(f"[3b] feature_id が2**53-1未満か（JSON安全整数）: max={max_feature_id} -> "
          f"{'OK' if check3b else 'NG'}")
    ok &= check3b

    distinct = len(set(feature_ids_stored))
    check4 = distinct == n
    print(f"[4] feature_id の衝突なし: {n}ヘクス中 distinct={distinct} -> {'OK' if check4 else 'NG'}")
    ok &= check4

    if check2:
        header = next(iter(headers))
        reconstructed = [feature_id_to_h3(f, header) for f in feature_ids_stored]
        check5 = reconstructed == hex_ids
    else:
        check5 = False
    print(f"[5] (header << {FEATURE_ID_BITS}) | feature_id で hex_id に復元できるか: "
          f"{'OK' if check5 else 'NG'}")
    ok &= check5

    print()
    if ok:
        print(f"PASS: {n}ヘクスすべてでH3 index <-> feature_id の橋渡しが検証条件を満たしました。")
    else:
        print("FAIL: 上記のいずれかがNGです。")
        sys.exit(1)


if __name__ == "__main__":
    main()
