// Tab 1: 基本表示 / ローカルMBTiles(ベクタ) / PMTiles / addSource・addLayer /
// feature-state / feature_id(H3由来の大きい整数)疎通確認。
// research.md §6.1〜6.3・§8.4 のチェック項目に対応する。使い捨て検証ハーネス（製品コードではない）。

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';

import 'hex_grid.dart';

// 【2026-08-13 変更】path_provider への依存を外した。
// maplibre_gl 0.27.0 を AGP 9 で使うには android.builtInKotlin=true が
// 必要だが、path_provider_android が引き込む jni パッケージが org.jetbrains.kotlin.android
// を適用するため、AGP 9 の built-in Kotlin と衝突してビルドできない:
//   A problem occurred evaluating project ':jni'.
//   > The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin support
//     since AGP 9.0.
// builtInKotlin=false に戻すと今度は maplibre_gl 0.27.0 側が kotlin() 未定義で落ちるため、
// AGP 9 では両立しない。fog of war ベンチマーク（本ハーネスの最重要項目）は
// path_provider を必要としないので、書き込み先を Directory.systemTemp に置き換えて回避した。
// Android では systemTemp はアプリ専有のキャッシュ領域を指すため、用途上は同等。

// 【2026-09-09 実測】spikes/fixtures/fetch_fixtures.sh が取得する検証用フィクスチャ
// （maplibre.mbtiles、ベクタタイル、z0-6）の source-layer 名。推測せず実測して確定した:
//   $ cd spikes/fixtures && python3 -c \
//       "import sqlite3; c=sqlite3.connect('sample.mbtiles'); \
//        print(c.execute(\"select value from metadata where name='json'\").fetchone()[0])"
//   -> {"vector_layers":[
//        {"id":"geolines", ...},   // 線（経緯線）
//        {"id":"countries", ...},  // ポリゴン（国境）
//        {"id":"centroids", ...}]} // 点（国の代表点）
const String kFixtureFillSourceLayer = 'countries';
const String kFixtureLineSourceLayer = 'geolines';

// フィクスチャは z0-6 のみ（README・spikes/fixtures/README.md参照）。これより高いズームで
// ベクタソースを開くとタイルが要求されず「例外なし・描画なし」になり、research.md §6.2の
// 判定不能をハーネス側の別バグとして再現してしまう。addLayer成功後に明示的にズームを
// 寄せて、目視で「実際に描画されたか」を確認できるようにする。
const double kFixtureMinZoom = 0;
const double kFixtureMaxZoom = 6;
const double kFixtureViewZoom = 2;

// research.md §8.4 実測値（tools/pack-builder/verify_feature_id.py、狭山湖周辺・解像度11・
// 13,106ヘクスに対する検証結果）: H3 index の下位52bitマスク後の feature_id 最大値。
// 2^53-1（9,007,199,254,740,991）未満のJSON safe integerであることを確認済み。
// このコメントは §8.4 の一次情報から転記したもの（研究資料の節番号はドキュメントの
// 追記により変わりうるため、値そのものを鵜呑みにせず研究資料の原典で都度確認すること）。
const int kMaxObservedFeatureId = 833108588584959;

class MapProbePage extends StatefulWidget {
  const MapProbePage({super.key});

  @override
  State<MapProbePage> createState() => _MapProbePageState();
}

class _MapProbePageState extends State<MapProbePage> {
  MapLibreMapController? _controller;
  String _styleString = MapLibreStyles.demo;
  final TextEditingController _styleUrlCtrl =
      TextEditingController(text: MapLibreStyles.demo);
  final TextEditingController _mbtilesPathCtrl = TextEditingController();
  final TextEditingController _pmtilesPathCtrl = TextEditingController();

  bool _geojsonProbeAdded = false;
  bool _featureIdProbeAdded = false;
  final List<String> _log = [];

  void _appendLog(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    developer.log(line, name: 'map_spike_gl.probe');
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  // --- 2. 基本地図表示 -----------------------------------------------
  void _applyStyleUrl() {
    setState(() => _styleString = _styleUrlCtrl.text.trim());
    _appendLog('スタイル適用: ${_styleUrlCtrl.text.trim()}');
  }

  // --- 3-0. 同梱フィクスチャをアプリのキャッシュ領域へコピー -----------------
  // 【2026-09-09 追加】adb push方式を廃止した。Android 13+ ではアプリがSAFを通さずに
  // /sdcard/Download 等の任意パスを直接読めず、権限エラーになる。これは「MapLibreの失敗」と
  // 外形上区別できず検証結果を汚染する（Androidのスコープドストレージ一般の制約。
  // terra-town固有の一次情報での確認はしていない。要確認としてIssue #24に記録すること）。
  // かわりにアセット同梱（pubspec.yaml の assets: 参照）にした。アセットは署名パッケージ内に
  // 封じ込まれておりネイティブSQLiteが直接開けないため、rootBundle.load()で読み出し、
  // 書き込み可能なディレクトリ（Directory.systemTemp）へコピーしてから mbtiles:// で参照する
  // （research.md §2.1 の手順どおり）。
  Future<void> _copyBundledFixture() async {
    try {
      final data = await rootBundle.load('assets/sample.mbtiles');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final destPath = '${Directory.systemTemp.path}/bundled_sample.mbtiles';
      await File(destPath).writeAsBytes(bytes, flush: true);
      setState(() => _mbtilesPathCtrl.text = destPath);
      _appendLog(
          '同梱フィクスチャをコピー完了 -> $destPath (${bytes.length} bytes)。'
          '下の②③ボタンでこのパスを使って読込を試せます');
    } catch (e, st) {
      _appendLog('同梱フィクスチャのコピー失敗: ${e.runtimeType}: $e '
          '（fetch_fixtures.sh を実行済みか確認してください）');
      developer.log('bundled fixture copy failed', error: e, stackTrace: st);
    }
  }

  // --- 3-1/3-2. ローカルMBTiles読込（ベクタソース・url方式 / tiles配列方式） -----
  // plan.md L83・research.md §6.2: terra-townの地域パックはベクタタイルMBTilesであり、
  // 旧実装の RasterSourceProperties は誤りだった（research.md §2.1の訂正、別PR）。
  // VectorSourceProperties の url と tiles のどちらが正しいかは一次情報で確定できないため、
  // 両方試せるボタンを用意し、1回の実機セッションで切り分ける。
  Future<void> _loadMbtilesVectorUrl() =>
      _loadMbtilesVector(useTilesArray: false);

  Future<void> _loadMbtilesVectorTiles() =>
      _loadMbtilesVector(useTilesArray: true);

  Future<void> _loadMbtilesVector({required bool useTilesArray}) async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('MBTiles(vector): マップ未初期化のため中止');
      return;
    }
    final srcPath = _mbtilesPathCtrl.text.trim();
    if (srcPath.isEmpty) {
      _appendLog(
          'MBTiles(vector): パスが空です。まず①「同梱フィクスチャをコピー」を押すか、'
          'パスを直接入力してください');
      return;
    }
    final variant = useTilesArray ? 'tiles配列' : 'url';
    final sourceId =
        useTilesArray ? 'mbtiles_vec_tiles_source' : 'mbtiles_vec_url_source';
    final fillLayerId =
        useTilesArray ? 'mbtiles_vec_tiles_fill' : 'mbtiles_vec_url_fill';
    final lineLayerId =
        useTilesArray ? 'mbtiles_vec_tiles_line' : 'mbtiles_vec_url_line';
    try {
      // ①のボタンでコピー済みのパス（書き込み可能ディレクトリ配下）ならそのまま使う。
      // 手入力で任意の場所を指定した場合に備え、未コピーならここでも一応コピーする
      // （Android 13+の制約はREADME「既知の制約」参照。既定の①ボタンを使えばこの分岐は通らない）。
      String destPath = srcPath;
      if (!srcPath.startsWith(Directory.systemTemp.path)) {
        final srcFile = File(srcPath);
        if (!await srcFile.exists()) {
          _appendLog('MBTiles(vector/$variant): 指定パスにファイルが存在しません: $srcPath');
          return;
        }
        final fileName = srcPath.split(Platform.pathSeparator).last;
        destPath = '${Directory.systemTemp.path}/mbtiles_copy_$fileName';
        await srcFile.copy(destPath);
        _appendLog('MBTiles(vector/$variant): 書き込み可能ディレクトリへコピー完了 -> $destPath');
      }

      // 同じボタンを2回目以降に押した場合（例: 1回目は描画されず、代表がもう一度押した場合）に
      // 「source already exists」でクラッシュ/例外になると、それがMBTiles読込自体の失敗
      // であるかのように見えてしまう。毎回いったん削除してから追加し直すことで、
      // 「複数回試せる」ことを保証する（既存が無ければ例外は握りつぶす）。
      try {
        await controller.removeLayer(fillLayerId);
      } catch (_) {}
      try {
        await controller.removeLayer(lineLayerId);
      } catch (_) {}
      try {
        await controller.removeSource(sourceId);
      } catch (_) {}

      final uri = 'mbtiles://$destPath';
      await controller.addSource(
        sourceId,
        useTilesArray
            ? VectorSourceProperties(
                tiles: [uri],
                minzoom: kFixtureMinZoom,
                maxzoom: kFixtureMaxZoom,
              )
            : VectorSourceProperties(
                url: uri,
                minzoom: kFixtureMinZoom,
                maxzoom: kFixtureMaxZoom,
              ),
      );
      // ベクタソースはレイヤーを追加しないと何も描画されない。fillとlineの両方を追加し、
      // 「例外が出ないこと」だけでなく「実際に描画されたか」を目視確認できるようにする。
      // source-layer名はファイル冒頭で実測した値。
      await controller.addLayer(
        sourceId,
        fillLayerId,
        const FillLayerProperties(fillColor: '#3388ff', fillOpacity: 0.5),
        sourceLayer: kFixtureFillSourceLayer,
      );
      await controller.addLayer(
        sourceId,
        lineLayerId,
        const LineLayerProperties(lineColor: '#ff0000', lineWidth: 1.5),
        sourceLayer: kFixtureLineSourceLayer,
      );
      // フィクスチャはz0-6のみ。判別しやすいズームへ寄せる（現在の中心のままズームだけ変更）。
      await controller.animateCamera(CameraUpdate.zoomTo(kFixtureViewZoom));
      _appendLog(
          'MBTiles(vector/$variant): addSource/addLayer(fill+line)成功（例外なし）。'
          '青い塗り(countries)と赤い線(geolines)が実際に描画されているかを目視で確認すること。'
          '例外が出なくても描画されていなければ$variant方式は不成立と判定すること');
    } catch (e, st) {
      _appendLog('MBTiles(vector/$variant): 失敗 ${e.runtimeType}: $e');
      developer.log('MBTiles vector load failed ($variant)',
          error: e, stackTrace: st);
    }
  }

  // --- 3-3. url方式・tiles配列方式のソース/レイヤーをリセット -----------------
  // 【2026-09-09追加】2026-09-09の実機セッションで、url方式を追加した後にリセットせず
  // tiles配列方式を重ねて追加したため、描画がどちらの方式の寄与か厳密に分離できない
  // という精度の限界が生じた（research.md §6.2参照）。url/tiles方式を比較する際は、
  // 必ず片方を試す→本ボタンでリセット→もう片方を試す、の順で行うこと
  // （README「タブ①」節にも同じ注意を記載）。
  Future<void> _resetMbtilesVectorSources() async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('MBTiles(vector) リセット: マップ未初期化のため中止');
      return;
    }
    const ids = [
      ['mbtiles_vec_url_fill', 'mbtiles_vec_url_line', 'mbtiles_vec_url_source'],
      [
        'mbtiles_vec_tiles_fill',
        'mbtiles_vec_tiles_line',
        'mbtiles_vec_tiles_source'
      ],
    ];
    for (final group in ids) {
      final fillLayerId = group[0];
      final lineLayerId = group[1];
      final sourceId = group[2];
      try {
        await controller.removeLayer(fillLayerId);
      } catch (_) {}
      try {
        await controller.removeLayer(lineLayerId);
      } catch (_) {}
      try {
        await controller.removeSource(sourceId);
      } catch (_) {}
    }
    _appendLog(
        'MBTiles(vector) リセット完了: url方式・tiles配列方式のソース/レイヤーを両方削除しました。'
        'これでどちらか片方だけを試せば、描画がその方式単独の寄与だと確認できます');
  }

  // --- 4. PMTiles読込（フォールバック候補） ------------------------------
  // 公式サンプル（maplibre_gl_example/assets/pmtiles_style.json）はリモートURL
  // ("pmtiles://https://...") をスタイルJSON内のsource.urlとして与える方式。
  // ローカルファイルの場合の正式な参照構文は一次情報で確認できなかったため、
  // 同じ "pmtiles://<絶対パス>" 形式を類推で試す（README に「未検証の類推」と明記）。
  // file_pickerを使わない理由は③と同じ（README参照）。
  Future<void> _loadPmtilesViaStyle() async {
    final srcPath = _pmtilesPathCtrl.text.trim();
    if (srcPath.isEmpty) {
      _appendLog('PMTiles: パスが空です（ローカルファイル選択、またはリモートURLを直接入力可）');
      return;
    }
    final isRemote = srcPath.startsWith('http://') || srcPath.startsWith('https://');
    final String pmtilesUrl = isRemote ? 'pmtiles://$srcPath' : 'pmtiles://$srcPath';
    final style = {
      'version': 8,
      'sources': {
        'pmtiles_probe_source': {
          'type': 'vector',
          'url': pmtilesUrl,
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#dddddd'},
        },
      ],
    };
    try {
      setState(() => _styleString = jsonEncode(style));
      _appendLog('PMTiles: スタイルJSONを $pmtilesUrl で適用（addSource例ではなくstyleString差し替え方式）。'
          '例外が出なくても実描画は目視確認が必要');
    } catch (e) {
      _appendLog('PMTiles: 失敗 ${e.runtimeType}: $e');
    }
  }

  // --- 5. addSource / addLayer 疎通 -----------------------------------
  Future<void> _addGeojsonSourceAndLayer() async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('addSource/addLayer: マップ未初期化のため中止');
      return;
    }
    try {
      final centers = generateHexGrid(3);
      final geojson = {
        'type': 'FeatureCollection',
        'features': [
          for (final c in centers)
            {
              'type': 'Feature',
              'id': c.q * 1000 + c.r,
              'properties': {'hexId': c.q * 1000 + c.r},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [hexRing(c)],
              },
            },
        ],
      };
      await controller.addGeoJsonSource(
        'probe_geojson_source',
        geojson,
        promoteId: 'hexId',
      );
      await controller.addLayer(
        'probe_geojson_source',
        'probe_geojson_layer',
        const FillLayerProperties(fillColor: '#ff4d4d', fillOpacity: 0.6),
      );
      setState(() => _geojsonProbeAdded = true);
      _appendLog('addSource/addLayer: 成功（3ヘクス分のGeoJSONを動的追加）');
    } catch (e, st) {
      _appendLog('addSource/addLayer: 失敗 ${e.runtimeType}: $e');
      developer.log('addSource/addLayer failed', error: e, stackTrace: st);
    }
  }

  // --- 6. feature-state プローブ ---------------------------------------
  // research.md §3.2: 0.26.2 の Android では UnimplementedError が投げられる想定。
  // 例外そのものが有効な検証結果なので、握りつぶさず型とメッセージを画面に出す。
  Future<void> _probeFeatureState() async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('feature-state: マップ未初期化のため中止');
      return;
    }
    if (!_geojsonProbeAdded) {
      _appendLog('feature-state: 先に「addSource/addLayer疎通」を実行してください（promoteId付きソースが必要）');
      return;
    }
    try {
      await controller.setFeatureState(
        'probe_geojson_source',
        '0',
        {'probed': true},
      );
      _appendLog('feature-state: 例外なく成功しました（0.27.0以降 or 環境差の可能性）');
    } catch (e, st) {
      _appendLog('feature-state: 例外を捕捉 -> type=${e.runtimeType} message="$e"');
      developer.log('feature-state probe raised', error: e, stackTrace: st);
    }
  }

  // --- 7. feature_id（H3由来の大きい整数）疎通確認 --------------------------
  // terra-townはH3の64bitインデックスを下位52bitマスクでfeature_idに変換している
  // （docs/terrain.md §4.4・research.md §8.4）。この大きさの整数がDart -> MethodChannel
  // -> Java -> MapLibreを問題なく通るかは未検証だった。実測最大値(kMaxObservedFeatureId)を
  // idに持つFeatureを1つ追加し、setFeatureStateの成功/例外と、getFeatureStateで実際に
  // 読み戻せるか（＝idが途中で丸められ別のfeatureに紐付いていないか）を確認する。
  Future<void> _probeLargeFeatureId() async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('feature_id疎通: マップ未初期化のため中止');
      return;
    }
    const sourceId = 'feature_id_probe_source';
    const layerId = 'feature_id_probe_layer';
    try {
      if (!_featureIdProbeAdded) {
        final geojson = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'id': kMaxObservedFeatureId,
              'properties': {},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  [
                    [139.4, 35.8],
                    [139.41, 35.8],
                    [139.41, 35.81],
                    [139.4, 35.81],
                    [139.4, 35.8],
                  ],
                ],
              },
            },
          ],
        };
        await controller.addGeoJsonSource(sourceId, geojson);
        await controller.addLayer(
          sourceId,
          layerId,
          const FillLayerProperties(fillColor: '#00c853', fillOpacity: 0.7),
        );
        setState(() => _featureIdProbeAdded = true);
        // このFeatureは東京近辺の固定座標に置いている。②③のMBTiles確認でカメラが
        // ズーム2（世界全体表示）へ移動している場合、そのままでは緑の四角が
        // 画面外/視認不能になり「例外なし＝成功」の判定を目視で裏取りできなくなる。
        // 目視確認を主目的ではなく補助にするため（PASS判定の主はログのsetFeatureState/
        // getFeatureStateの結果）、ここで明示的にカメラを寄せておく。
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(const LatLng(35.805, 139.405), 13),
        );
        _appendLog('feature_id疎通: id=$kMaxObservedFeatureId のFeatureを追加（例外なし）。'
            '目視用に地図を東京近辺（zoom13）へ移動しました');
      }

      await controller.setFeatureState(
        sourceId,
        kMaxObservedFeatureId.toString(),
        {'probed': true},
      );
      _appendLog('feature_id疎通: setFeatureState 成功（例外なし）。id=$kMaxObservedFeatureId');

      final state = await controller.getFeatureState(sourceId, kMaxObservedFeatureId.toString());
      if (state != null && state['probed'] == true) {
        _appendLog('feature_id疎通: getFeatureStateで読み戻し成功 -> $state '
            '（idが途中で丸められていないことの傍証）');
      } else {
        _appendLog('feature_id疎通: getFeatureStateの結果が想定と異なる -> $state '
            '（idが別の値に変換された可能性あり。要確認）');
      }
    } catch (e, st) {
      _appendLog('feature_id疎通: 失敗 ${e.runtimeType}: $e (id=$kMaxObservedFeatureId)');
      developer.log('large feature_id probe failed', error: e, stackTrace: st);
    }
  }

  @override
  void dispose() {
    _styleUrlCtrl.dispose();
    _mbtilesPathCtrl.dispose();
    _pmtilesPathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 320,
          child: MapLibreMap(
            styleString: _styleString,
            initialCameraPosition: CameraPosition(
              target: LatLng(kOriginLat, kOriginLng),
              zoom: 14,
            ),
            onMapCreated: (c) => _controller = c,
            onStyleLoadedCallback: () => _appendLog('onStyleLoadedCallback 発火（スタイル読込完了）'),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _sectionTitle('② 基本地図表示 [research.md §6.1]'),
              TextField(
                controller: _styleUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'スタイルURL（またはraw JSON文字列）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _applyStyleUrl,
                child: const Text('スタイル適用'),
              ),
              const Divider(height: 32),
              _sectionTitle('③ ローカルMBTiles読込（ベクタソース）[research.md §6.2]'),
              const Text(
                'terra-townの地域パックはベクタタイルMBTiles（plan.md）。'
                'まず①でフィクスチャをコピーしてから、②url方式・③tiles配列方式を'
                '両方試すこと（どちらが正しいか一次情報で確定できないため）。\n'
                '⚠️ 重要: ②③は同じ色（青い塗り・赤い線）で描画するため、片方を試した後に'
                'リセットせずもう片方を重ねて試すと、描画がどちらの方式単独の寄与かが'
                '区別できなくなる。②→リセット→③、の順で1つずつ試すこと'
                '（2026-09-09の実機セッションでこれをせず重ねたため、この精度の限界が生じた）。',
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _copyBundledFixture,
                child: const Text('① 同梱フィクスチャをコピーして使う（推奨）'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _mbtilesPathCtrl,
                decoration: const InputDecoration(
                  labelText: 'MBTilesファイルの絶対パス（①実行後は自動入力・手入力も可）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _loadMbtilesVectorUrl,
                    child: const Text('② VectorSourceProperties(url:)で読込'),
                  ),
                  ElevatedButton(
                    onPressed: _loadMbtilesVectorTiles,
                    child: const Text('③ VectorSourceProperties(tiles:)で読込'),
                  ),
                  OutlinedButton(
                    onPressed: _resetMbtilesVectorSources,
                    child: const Text('リセット（②③を両方削除）'),
                  ),
                ],
              ),
              const Divider(height: 32),
              _sectionTitle('④ PMTiles読込（フォールバック候補）[research.md §6.2]'),
              TextField(
                controller: _pmtilesPathCtrl,
                decoration: const InputDecoration(
                  labelText: 'PMTilesファイルの絶対パス、またはhttps URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadPmtilesViaStyle,
                child: const Text('PMTiles読込を試す'),
              ),
              const Divider(height: 32),
              _sectionTitle('⑤ addSource/addLayer 疎通 [research.md §6.3]'),
              ElevatedButton(
                onPressed: _addGeojsonSourceAndLayer,
                child: const Text('GeoJSONソース+レイヤーを動的追加'),
              ),
              const Divider(height: 32),
              _sectionTitle('⑥ feature-state プローブ [research.md §6.3]'),
              ElevatedButton(
                onPressed: _probeFeatureState,
                child: const Text('setFeatureState を試す'),
              ),
              const Divider(height: 32),
              _sectionTitle('⑦ feature_id（H3由来の大きい整数）疎通確認 [research.md §8.4]'),
              Text(
                'id=$kMaxObservedFeatureId を持つFeatureを追加し、'
                'setFeatureState/getFeatureStateがDart→MethodChannel→Java→MapLibreを'
                '問題なく通るかを確認する。',
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _probeLargeFeatureId,
                child: const Text('大きいfeature_idでsetFeatureStateを試す'),
              ),
              const Divider(height: 32),
              _sectionTitle('ログ（debugPrintにも出力）'),
              Container(
                height: 240,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _log.isEmpty
                    ? const Text('（まだログはありません）',
                        style: TextStyle(color: Colors.white54))
                    : ListView.builder(
                        itemCount: _log.length,
                        itemBuilder: (context, i) => Text(
                          _log[i],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
