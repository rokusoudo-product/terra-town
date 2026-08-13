// map_spike_gl — Issue #24 検証ハーネス（maplibre_gl 用）。
//
// 【これは使い捨ての検証コードです】terra-town本体（app/ packages/core/ packages/location/）
// とは一切関係がなく、DESIGN.md のデザイントークンにも準拠していません。
// 目的は「代表が実機Androidにインストールしてボタンを押すだけで、Issue #24の
// 受け入れ基準に必要な数値・可否が画面から読み取れる」状態を作ることのみです。
// 詳細は README.md を参照。

import 'package:flutter/material.dart';

import 'fog_benchmark_page.dart';
import 'fog_feature_state_benchmark_page.dart';
import 'map_probe_page.dart';
import 'plugin_info.dart';

void main() {
  runApp(const MapSpikeApp());
}

class MapSpikeApp extends StatelessWidget {
  const MapSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'map_spike_gl (使い捨て検証ハーネス)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const _SpikeHome(),
    );
  }
}

class _SpikeHome extends StatefulWidget {
  const _SpikeHome();

  @override
  State<_SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<_SpikeHome> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('map_spike_gl [使い捨て検証ハーネス]'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '① 地図/MBTiles/feature-state'),
            Tab(text: '② fog of war 性能(第一案:再エンコード)'),
            Tab(text: '③ fog of war 性能(第二案:feature-state)'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. プラグイン版数の常時表示（README「バージョン切り替え」参照）。
          Container(
            width: double.infinity,
            color: Colors.indigo.shade900,
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                MapProbePage(),
                FogBenchmarkPage(),
                FogFeatureStateBenchmarkPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
