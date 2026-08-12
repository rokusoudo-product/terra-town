// Tab 1: 基本表示 / ローカルMBTiles / PMTiles / addSource・addLayer / feature-state の疎通確認。
// research.md §6.1〜6.3 のチェック項目に対応する。使い捨て検証ハーネス（製品コードではない）。

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';

import 'hex_grid.dart';

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

  // --- 3. ローカルMBTiles読込 ------------------------------------------
  // research.md §2.1 の手順:
  //   1. アセット/外部ストレージのファイルを、書き込み可能ディレクトリ（アプリのcacheディレクトリ）へコピー
  //   2. addSource に RasterSourceProperties(tiles: ['mbtiles://<コピー後の絶対パス>']) を渡す
  // 非公式・未文書化の挙動（Issue #318）であることに注意。
  //
  // 【既知の制約】当初 file_picker でネイティブのファイル選択ダイアログを提供する予定だったが、
  // file_picker 11.0.3 が独自に適用するKotlin Gradle Pluginとmaplibre_glのそれが衝突し、
  // `cannot find symbol FilePickerPlugin` でビルドが通らなかった（README参照）。
  // そのため、パスはテキスト入力のみで指定する（adb push等で端末に転送したファイルのパスを入力）。
  Future<void> _loadMbtiles() async {
    final controller = _controller;
    if (controller == null) {
      _appendLog('MBTiles: マップ未初期化のため中止');
      return;
    }
    final srcPath = _mbtilesPathCtrl.text.trim();
    if (srcPath.isEmpty) {
      _appendLog('MBTiles: パスが空です。ファイル選択するか直接入力してください');
      return;
    }
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final fileName = srcPath.split(Platform.pathSeparator).last;
      final destPath = '${cacheDir.path}/mbtiles_copy_$fileName';
      final srcFile = File(srcPath);
      if (!await srcFile.exists()) {
        _appendLog('MBTiles: 指定パスにファイルが存在しません: $srcPath');
        return;
      }
      await srcFile.copy(destPath);
      _appendLog('MBTiles: 書き込み可能ディレクトリへコピー完了 -> $destPath');

      await controller.addSource(
        'mbtiles_probe_source',
        RasterSourceProperties(tiles: ['mbtiles://$destPath']),
      );
      await controller.addLayer(
        'mbtiles_probe_source',
        'mbtiles_probe_layer',
        const RasterLayerProperties(),
      );
      _appendLog('MBTiles: addSource/addLayer 成功（例外なし）。'
          '実際にタイルが描画されているかは目視で確認すること');
    } catch (e, st) {
      _appendLog('MBTiles: 失敗 ${e.runtimeType}: $e');
      developer.log('MBTiles load failed', error: e, stackTrace: st);
    }
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
              _sectionTitle('③ ローカルMBTiles読込 [research.md §6.2]'),
              TextField(
                controller: _mbtilesPathCtrl,
                decoration: const InputDecoration(
                  labelText: 'MBTilesファイルの絶対パス（端末上）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadMbtiles,
                child: const Text('MBTiles読込を試す'),
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
