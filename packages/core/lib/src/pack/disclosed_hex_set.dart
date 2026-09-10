import 'dart:typed_data';

import '../geo/hex_id.dart';

/// 開示ヘクス集合の圧縮表現（T035・Issue #84）。
///
/// 出典: `specs/001-mvp/plan.md` §6「開示ヘクス集合: Roaring Bitmap / ビットセットで
/// 地域ごとに圧縮（GeoJSON 保持は肥大化するため不採用）」、
/// §3.5「1ソース（＝1エリア）あたりの暫定上限 30,000 ヘクス」。
///
/// **本クラスは GeoJSON・地図SDKの型を一切保持しない**（受け入れ基準）。保持するのは
/// [HexId]（H3由来・非負整数、`hex_id.dart` 参照）の集合のみである。
///
/// ## 圧縮方式（Roaring Bitmap の考え方を64bit値向けに適用）
/// [HexId.value] は H3 セルインデックス由来で疎（大きな値域に少数が散らばる）ため、
/// 素朴な固定長ビット配列は使えない。Roaring Bitmap と同様に、値を
/// 「上位ビット（コンテナキー）＋下位16bit（コンテナ内位置）」に分割し、
/// コンテナ単位で疎なら**ソート配列**（[_ArrayContainer]）、
/// 密なら**ビットマップ**（[_BitmapContainer]、65,536bit=8KB 固定）に
/// 適応的に切り替える。1コンテナあたりの要素数が閾値
/// [_arrayToBitmapThreshold]（Roaring Bitmap の一般的な閾値 4096 = 65536/16 を踏襲）を
/// 超えたら配列からビットマップへ昇格する。
///
/// 【閾値の厳密さについて】本実装の [_ArrayContainer] は `List<int>`（Dart の Smi は
/// 64bit環境で8byteスロット）で保持しており、本家 Roaring Bitmap の `uint16[]`
/// （2byte/要素）ではない。本家の閾値4096は「配列(2byte×4096=8KB) とビットマップ
/// (8KB固定) が釣り合う点」から導かれているため、8byteスロットの本実装では
/// 厳密な損益分岐点は約1024要素になる（4096はRoaring Bitmapの慣例値をそのまま
/// 踏襲したものであり、本実装のメモリ特性に対して最適化された値ではない）。
/// 1エリア暫定上限30,000ヘクス規模では正しさ・性能とも問題にならないため
/// 本 Issue ではこのままとするが、メモリ最適化が必要になった場合は
/// [_ArrayContainer] を `Uint16List` ベースに置き換えるか、閾値を約1024へ
/// 見直すことを検討すること。
///
/// pub.dev の外部 Roaring Bitmap 実装には依存しない（GPS_ARCHITECTURE・
/// `packages/core` は純粋 Dart のみという方針、`tools/check_import_direction.sh` が
/// 依存追加を機械的に検査するわけではないが、外部パッケージ追加はネットワーク取得を
/// 要し `dart pub get` の再現性リスクがあるため本 Issue では避けた）。
///
/// ## 開示状態の正について（重要）
/// 2026-09-09 の実機検証（Issue #24）で、地図の `setStyle`（スタイル再読み込み）を
/// 呼ぶと地図側の `feature-state` が全て失われることが確認された（plan.md §8・
/// research.md §6.4）。**地図の feature-state は描画のための派生状態に過ぎず、
/// 開示状態の正ではない。** 開示状態の唯一の正は永続ストレージ
/// （`packages/location` の `disclosed_hex` テーブル・PR #90）である。
/// 本クラスは、その永続ストレージから読み出したヘクス集合を**メモリ上で圧縮して
/// 保持するための作業表現**であり、それ自体が正ではない
/// （例: 起動時に `disclosed_hex` テーブルを集約して本クラスを構築し、地図の
/// feature-state 復元やアプリ内の高速な開示判定に使う、といった用途を想定）。
class DisclosedHexSet {
  /// コンテナキー（上位ビット）と、コンテナ内位置（下位16bit）の境界。
  static const int _lowBits = 16;
  static const int _lowMask = (1 << _lowBits) - 1;

  /// 1コンテナ（65,536通りの下位ビット空間）内の要素数がこれを超えたら
  /// 配列コンテナからビットマップコンテナへ昇格する。
  static const int _arrayToBitmapThreshold = 4096;

  final Map<int, _Container> _containers = {};
  int _length = 0;

  DisclosedHexSet();

  /// 空でない集合を直接構築するための便利コンストラクタ。
  factory DisclosedHexSet.from(Iterable<HexId> hexIds) {
    final set = DisclosedHexSet();
    set.addAll(hexIds);
    return set;
  }

  /// 集合に含まれるヘクス数。
  int get length => _length;

  bool get isEmpty => _length == 0;
  bool get isNotEmpty => _length > 0;

  bool contains(HexId hexId) {
    final container = _containers[_containerKey(hexId.value)];
    if (container == null) return false;
    return container.contains(_low(hexId.value));
  }

  /// [hexId] を集合に追加する。既に含まれている場合は何もしない（冪等）。
  ///
  /// 戻り値は「新規に追加されたか」（既存なら `false`）。
  bool add(HexId hexId) {
    final key = _containerKey(hexId.value);
    final low = _low(hexId.value);
    final existing = _containers[key];
    if (existing == null) {
      final container = _ArrayContainer();
      container.add(low);
      _containers[key] = container;
      _length++;
      return true;
    }
    final added = existing.add(low);
    if (!added) return false;
    _length++;
    if (existing is _ArrayContainer && existing.length > _arrayToBitmapThreshold) {
      _containers[key] = existing.toBitmapContainer();
    }
    return true;
  }

  void addAll(Iterable<HexId> hexIds) {
    for (final hexId in hexIds) {
      add(hexId);
    }
  }

  /// 集合内のヘクスをコンテナキー昇順・コンテナ内昇順で列挙する。
  Iterable<HexId> toIterable() sync* {
    final sortedKeys = _containers.keys.toList()..sort();
    for (final key in sortedKeys) {
      final base = key << _lowBits;
      for (final low in _containers[key]!.values()) {
        yield HexId(base + low);
      }
    }
  }

  static int _containerKey(int value) => value >> _lowBits;
  static int _low(int value) => value & _lowMask;
}

/// コンテナ（Roaring Bitmap の「チャンク」に相当）の共通インターフェース。
abstract class _Container {
  bool contains(int low);

  /// 追加した場合 true。既に含まれていた場合は false。
  bool add(int low);

  int get length;

  Iterable<int> values();
}

/// 疎なコンテナ用のソート済み配列表現。
class _ArrayContainer implements _Container {
  final List<int> _sorted = <int>[];

  @override
  int get length => _sorted.length;

  @override
  bool contains(int low) => _indexOf(low) >= 0;

  @override
  bool add(int low) {
    final index = _indexOf(low);
    if (index >= 0) return false;
    _sorted.insert(-(index + 1), low);
    return true;
  }

  @override
  Iterable<int> values() => _sorted;

  /// 二分探索。見つかればその位置、無ければ `-(挿入位置 + 1)`（`List.binarySearch` 相当）。
  int _indexOf(int low) {
    var lo = 0;
    var hi = _sorted.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final value = _sorted[mid];
      if (value == low) return mid;
      if (value < low) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -(lo + 1);
  }

  /// 密なコンテナ（要素数が閾値超過）へ変換する。
  _BitmapContainer toBitmapContainer() {
    final bitmap = _BitmapContainer();
    for (final low in _sorted) {
      bitmap.add(low);
    }
    return bitmap;
  }
}

/// 密なコンテナ用の固定長ビットマップ表現（65,536bit = 8KB 固定・[Uint32List]）。
class _BitmapContainer implements _Container {
  static const int _bitsPerWord = 32;
  static const int _wordCount = 65536 ~/ _bitsPerWord; // 2048 words = 8KB

  final Uint32List _words = Uint32List(_wordCount);
  int _length = 0;

  @override
  int get length => _length;

  @override
  bool contains(int low) {
    final word = _words[low >> 5];
    return (word & (1 << (low & 31))) != 0;
  }

  @override
  bool add(int low) {
    final wordIndex = low >> 5;
    final bit = 1 << (low & 31);
    if ((_words[wordIndex] & bit) != 0) return false;
    _words[wordIndex] |= bit;
    _length++;
    return true;
  }

  @override
  Iterable<int> values() sync* {
    for (var w = 0; w < _words.length; w++) {
      final word = _words[w];
      if (word == 0) continue;
      for (var b = 0; b < _bitsPerWord; b++) {
        if ((word & (1 << b)) != 0) {
          yield (w << 5) + b;
        }
      }
    }
  }
}
