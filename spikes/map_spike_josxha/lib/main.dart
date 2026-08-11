// map_spike_josxha — Issue #24 検証ハーネス（josxha/flutter-maplibre 用・最小プローブ）。
//
// 【これは使い捨ての検証コードです】terra-town本体（app/ packages/core/ packages/location/）
// とは一切関係がなく、DESIGN.md のデザイントークンにも準拠していません。
//
// research.md §3.2 の調査で feature-state のAndroid実装根拠が見つからなかったため、
// このアプリには性能計測UIを作っていない（map_spike_gl側にのみfog of war計測がある）。
// 以下の3項目のみ:
//   1. プラグイン版数の表示
//   2. 基本地図表示
//   3. MBTiles参照の試行（構文が特定できなかったため、ボタンは無効化してある。詳細README参照）
//
// 詳細は README.md を参照。

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import 'plugin_info.dart';

void main() {
  runApp(const MapSpikeJosxhaApp());
}

class MapSpikeJosxhaApp extends StatelessWidget {
  const MapSpikeJosxhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'map_spike_josxha (使い捨て検証ハーネス)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const _SpikeHome(),
    );
  }
}

class _SpikeHome extends StatefulWidget {
  const _SpikeHome();

  @override
  State<_SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<_SpikeHome> {
  final TextEditingController _mbtilesPathCtrl = TextEditingController();
  final List<String> _log = [];

  void _appendLog(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    debugPrint(line);
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  @override
  void dispose() {
    _mbtilesPathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('map_spike_josxha [使い捨て検証ハーネス]')),
      body: Column(
        children: [
          // 1. プラグイン版数の常時表示。
          Container(
            width: double.infinity,
            color: Colors.teal.shade900,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kPluginVersionLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  kPluginVersionNote,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          // 2. 基本地図表示。
          SizedBox(
            height: 360,
            child: MapLibreMap(
              options: MapOptions(
                initStyle: 'https://demotiles.maplibre.org/style.json',
                initCenter: const Geographic(lon: 139.767125, lat: 35.681236),
                initZoom: 14,
              ),
              onMapCreated: (c) => _appendLog('onMapCreated 発火'),
              onStyleLoaded: (style) => _appendLog('onStyleLoaded 発火（スタイル読込完了）'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('③ MBTiles参照の試行 [research.md §6.2]',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Card(
                  color: Colors.orange.shade50,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '結論（机上調査時点）: MBTiles参照の具体的な構文（URLスキームの書式）を、'
                      'パッケージソース（maplibre / maplibre_android / maplibre_platform_interface '
                      '各パッケージ）から特定できなかった。研究doc research.md §2.2 も同じ結論。\n\n'
                      '機能マトリクス上はMBTiles対応がAndroid/iOSで明記されているため、'
                      '実装自体は存在する可能性が高いが、Dart側から呼び出す一次情報が見つからない。\n\n'
                      'そのため、下のボタンは意図的に無効化してある。代表が実機で試す場合は、'
                      'まず maplibre_gl 側で確認できている mbtiles://<絶対パス> という構文を'
                      '類推で試すのも一つの手だが、これは完全な当て推量であり根拠がないことに注意。',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mbtilesPathCtrl,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'MBTilesファイルの絶対パス（構文未特定のため入力欄も無効化）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const ElevatedButton(
                  onPressed: null, // 意図的に無効化。理由は上のカード参照。
                  child: Text('MBTiles読込を試す（構文未特定のため無効）'),
                ),
                const Divider(height: 32),
                Text('ログ（debugPrintにも出力）',
                    style: Theme.of(context).textTheme.titleMedium),
                Container(
                  height: 200,
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
      ),
    );
  }
}
