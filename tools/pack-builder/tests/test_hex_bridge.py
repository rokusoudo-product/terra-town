"""hex_bridge.py の単体テスト（Issue #118・可能であれば追加、の対象）。

`docs/terrain.md` §4.4 の「H3 index → Feature id の下位52bitマスク」方式が
実際に可逆で、JSON安全整数の範囲に収まることを検証する。

H3 の実セル値（`h3` パッケージ）は使わず、64bit整数のビット演算のみで完結する
純粋関数として合成入力（任意のヘッダビット・任意のfeature_id）でテストする
（h3パッケージへの依存を増やさないため）。
"""

from __future__ import annotations

import pytest

import hex_bridge


def test_feature_id_bits_and_mask_constants():
    assert hex_bridge.FEATURE_ID_BITS == 52
    assert hex_bridge.FEATURE_ID_MASK == (1 << 52) - 1
    assert hex_bridge.FEATURE_ID_MASK == 4_503_599_627_370_495


def test_feature_id_mask_is_within_json_safe_integer_range():
    """docs/terrain.md §4.4: 52bitの最大値は2^53-1（JSON safe integer上限）未満。"""
    json_safe_integer_max = 2**53 - 1
    assert hex_bridge.FEATURE_ID_MASK < json_safe_integer_max


@pytest.mark.parametrize(
    "header_bits, feature_id",
    [
        (0, 0),
        (0, (1 << 52) - 1),  # 全52bit立った最大値
        (0xABC, 0x1),
        (0xABC, 0xFEDCBA9876543),
        (0xFFF, (1 << 52) - 1),  # ヘッダ12bit最大 + featureビット最大
        (0x1, 0),
    ],
)
def test_h3_to_feature_id_and_back_roundtrip(header_bits: int, feature_id: int):
    """h3_to_feature_id / feature_id_to_h3 が可逆であること（docs/terrain.md §4.4）。"""
    h3_index = (header_bits << hex_bridge.FEATURE_ID_BITS) | feature_id

    assert hex_bridge.h3_to_feature_id(h3_index) == feature_id
    assert hex_bridge.header_bits_of(h3_index) == header_bits
    assert hex_bridge.feature_id_to_h3(feature_id, header_bits) == h3_index


def test_h3_to_feature_id_masks_off_header_bits():
    """上位ビット（ヘッダ）は捨てられ、下位52bitだけが feature_id になること。"""
    header_bits = 0b1010_1010_1010  # 12bit
    feature_id = 0x0F0F0F0F0F0F0
    h3_index = (header_bits << 52) | feature_id

    assert hex_bridge.h3_to_feature_id(h3_index) == feature_id
    # ヘッダを別の値に変えても feature_id 部分は変わらないこと（マスクの独立性）。
    other_header_h3_index = (0b1111_0000_1111 << 52) | feature_id
    assert hex_bridge.h3_to_feature_id(other_header_h3_index) == feature_id


def test_feature_id_never_exceeds_json_safe_integer_for_any_64bit_h3_index():
    """任意の64bit整数を入力しても、出力される feature_id は必ずJSON安全整数に収まること。"""
    json_safe_integer_max = 2**53 - 1
    sample_h3_indexes = [
        0,
        1,
        2**63 - 1,  # 63bit最大（H3 indexは常に2^63未満。docs/terrain.md §4.4参照）
        0x89283082BFFFFFF,  # 実際のH3 index（res9セル）に類似した16進値の例
        (1 << 64) - 1,  # 64bit全ビット立った極端値
    ]
    for h3_index in sample_h3_indexes:
        feature_id = hex_bridge.h3_to_feature_id(h3_index)
        assert 0 <= feature_id <= json_safe_integer_max
        assert feature_id <= hex_bridge.FEATURE_ID_MASK
