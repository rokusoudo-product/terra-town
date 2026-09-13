"""hex_neighbors.py の単体テスト（Issue #152）。

`filter_and_sort_intra_pack_neighbors` は純粋関数（h3ライブラリを呼ばない）であり、
実際のH3セル値を使わず合成の整数IDでテストする（`test_hex_bridge.py` と同じ方針。
h3パッケージへの依存を`requirements-dev.txt`（軽量なPR CI用）に増やさないため）。

`h3_ring_neighbors`（実際にh3ライブラリを呼ぶ側）は本テストの対象外
（`verify_hex_neighbor_determinism.py`・`compute_hex_neighbors.py` の
手動/CI実行〔`pack-build.yml`〕で実データを用いて検証する）。
"""

from __future__ import annotations

import hex_neighbors


def test_filters_out_ids_not_in_pack():
    """パック範囲外へ出る隣接は含めない（Issue #152 受け入れ基準）。"""
    result = hex_neighbors.filter_and_sort_intra_pack_neighbors(
        hex_id=1, candidate_neighbor_ids=[2, 3, 99], pack_hex_id_set={1, 2, 3}
    )
    assert result == [2, 3]


def test_excludes_self_even_if_present_in_candidates():
    result = hex_neighbors.filter_and_sort_intra_pack_neighbors(
        hex_id=1, candidate_neighbor_ids=[1, 2], pack_hex_id_set={1, 2}
    )
    assert result == [2]


def test_sorted_ascending_regardless_of_input_order():
    result = hex_neighbors.filter_and_sort_intra_pack_neighbors(
        hex_id=1, candidate_neighbor_ids=[5, 2, 4], pack_hex_id_set={1, 2, 4, 5}
    )
    assert result == [2, 4, 5]


def test_edge_hex_has_fewer_than_six_neighbors():
    """パック範囲の縁のヘクスは、6個の候補のうち範囲外を除外した結果、
    6件未満になる（Issue #152 受け入れ基準「範囲外へ出る隣接が含まれていないことの
    縁のヘクスのテスト」）。"""
    candidates_including_3_outside = [11, 12, 13, 900, 901, 902]
    result = hex_neighbors.filter_and_sort_intra_pack_neighbors(
        hex_id=10,
        candidate_neighbor_ids=candidates_including_3_outside,
        pack_hex_id_set={10, 11, 12, 13},
    )
    assert result == [11, 12, 13]
    assert len(result) < 6


def test_interior_hex_keeps_all_six_neighbors():
    """パック内部のヘクスは6個すべての候補がパック範囲内なので6件のまま。"""
    candidates = [2, 3, 4, 5, 6, 7]
    result = hex_neighbors.filter_and_sort_intra_pack_neighbors(
        hex_id=1,
        candidate_neighbor_ids=candidates,
        pack_hex_id_set={1, 2, 3, 4, 5, 6, 7},
    )
    assert result == [2, 3, 4, 5, 6, 7]
    assert len(result) == 6


def test_empty_candidates_returns_empty_list():
    assert hex_neighbors.filter_and_sort_intra_pack_neighbors(1, [], {1}) == []


def test_hex_ring_neighbors_is_not_imported_at_module_load_time():
    """`import hex_neighbors` 自体はh3パッケージを要求しないこと
    （本ファイルが `requirements-dev.txt`〔pytestのみ〕環境で収集・実行できることの保証。
    h3が未インストールでもここまで到達していること自体がこのテストの主張）。"""
    assert hasattr(hex_neighbors, "h3_ring_neighbors")
