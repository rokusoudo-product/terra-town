"""tools/pack-builder/hex_neighbors.py — ヘクス隣接関係の計算ロジック（Issue #152）。

## 背景

Issue #151（開放ポイントの消費）の隣接制約「開放済みヘクスに隣接するヘクスのみ
開放できる」（docs/opening_points.md §5.2）を実装するには「あるヘクスの隣は誰か」が
分かる必要がある。H3（ヘクスの計算）は Issue #108 で Kotlin 側に寄せたため、Dart側
（`packages/location`・`packages/core`）には隣接を計算する手段がない。

2026-09-13 代表決定（Issue #151・#152）: パック生成時（本ツール）に隣接関係を
事前計算して `region_pack.sqlite` に同梱し、実行時にH3を呼ばない
（plan.md §4「実行時のタイルクエリはしない・CI で事前計算する」と同じ方針）。

## モジュール分割の理由（テスト容易性・Issue #118 の方針を踏襲）

`h3_ring_neighbors`（実際にH3ライブラリでセルの隣接候補を求める部分）と
`filter_and_sort_intra_pack_neighbors`（候補からパック範囲外を除外し昇順に並べる
純粋関数）を分離している。後者は標準ライブラリのみで完結する純粋関数であり、
`hex_bridge.py` の単体テスト方針（h3パッケージへの依存を
`requirements-dev.txt`（軽量なPR CI用）に増やさないため、合成の整数IDでテストする）
と揃えるため、`h3` のimportを `h3_ring_neighbors` 内に閉じ込めている
（モジュールを `import hex_neighbors` するだけではh3を要求しない）。

## パック範囲外の隣接を含めない理由（Issue #152 受け入れ基準）

パック範囲外のヘクスは同梱パックに存在せず（`hex_terrain` に行がない）、
そのヘクスを開放することもできない。したがって「パック範囲外へ出る隣接」を
一覧に含めても実行時に使い道がなく、むしろ「存在しないヘクスを指す隣接」という
不整合なデータになる。範囲の縁のヘクスは、この除外の結果として隣接が6件未満に
なりうる（H3の通常セルは最大6個の隣接を持つ。ペンタゴンセルは対象エリア外のため
考慮不要）。この扱いは `tools/pack-builder/README.md`「ヘクス隣接関係」節に明記する。
"""

from __future__ import annotations


def h3_ring_neighbors(hex_id_int: int) -> list[int]:
    """H3 index（整数）の距離1の隣接ヘクス候補を整数のリストで返す（順不同）。

    候補には「パックに含まれるかどうか」の判定は含まない
    （`filter_and_sort_intra_pack_neighbors` が別途行う）。
    通常セルは6個、ペンタゴンセル（対象エリアには存在しない）は5個を返す。
    """
    import h3  # 遅延import。モジュール自体をh3なしでimportできるようにするため（本ファイルdocstring参照）。

    h3_str = h3.int_to_str(hex_id_int)
    ring = h3.grid_ring(h3_str, 1)
    return [h3.str_to_int(s) for s in ring]


def filter_and_sort_intra_pack_neighbors(
    hex_id: int,
    candidate_neighbor_ids: list[int],
    pack_hex_id_set: set[int],
) -> list[int]:
    """候補隣接ヘクスのうち、パック範囲内（`pack_hex_id_set`）のものだけを昇順で返す。

    - パック範囲外へ出る隣接は含めない（Issue #152 受け入れ基準）。
    - 自分自身が候補に混入していても除外する（`h3.grid_ring` は通常自分自身を
      含まないが、念のための防御。`filter_and_sort_intra_pack_neighbors` を
      直接呼ぶテスト・将来の呼び出し元の双方に対する安全策）。
    - 決定論のため常に昇順ソート済みの結果を返す（`hex_id` 側と同じソート方針。
      `classify_terrain.py`・`extract_districts.py` の「昇順ソートして書き込む」
      方針と揃える）。
    """
    return sorted(
        n for n in candidate_neighbor_ids if n != hex_id and n in pack_hex_id_set
    )
