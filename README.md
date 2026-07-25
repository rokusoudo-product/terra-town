# terra-town

歩いた場所が開拓され、自分の街が育っていく GPS 位置情報ゲーム（Android 先行）。

## コンセプト

- GPS を用いてマップを歩く。**歩いた場所の霧が晴れて開拓される**
- 開拓エリアから資材を獲得し、実在地図の上に**自分の街を建設・育成**する
- **歩く楽しさ + 健康促進 + マップの開拓**を組み合わせる
- 行ったことがない場所も**ポイントで開拓**できる
- → 最終的に「**地球が自分の街になる**」楽しさを目指す

## ドキュメント

仕様書は本リポジトリ内で管理する（GitHub Spec Kit / 仕様書ファースト）。

| ドキュメント | 内容 |
|--------------|------|
| [docs/concept.md](docs/concept.md) | 初期コンセプトメモ（2026-07-08 起草、2026-07-20 コンセプト確定） |
| [specs/001-mvp/spec.md](specs/001-mvp/spec.md) | MVP 仕様（GDD 相当・何を/なぜ）。ゲート① 承認済み |
| [specs/001-mvp/plan.md](specs/001-mvp/plan.md) | MVP 実装計画（技術スタック・アーキ）。ゲート② 承認済み |
| [DESIGN.md](DESIGN.md) | UIデザイン仕様（Material 3 ＋ 独自トークン） |
| [docs/architecture.md](docs/architecture.md) | 環境構成図（Mermaid・詳細版） |
| [docs/opening_points.md](docs/opening_points.md) | 開放ポイント（未踏破エリアの開放手段）定義（Issue #4） |
| [docs/terrain.md](docs/terrain.md) | エリア（ヘクス）の形状・地形タイプ定義（2026-07-23、Issue #3） |
| [docs/landmark_objects.md](docs/landmark_objects.md) | 名所・固有オブジェクト（大量配置POI）システム定義（2026-07-26、Issue #6） |

## アーキテクチャ / 構成図

MVP は **端末内完結（ステートフルなバックエンドなし）**。外部通信は「地域パックの初回ダウンロード（静的ファイル・任意）」のみで、**歩行位置はサーバに送信しない**。詳細・依存方向図は [docs/architecture.md](docs/architecture.md)。

```mermaid
flowchart TB
    user([プレイヤー / 歩く人])

    subgraph device["📱 ユーザー端末（Android 先行 / 将来 iOS）"]
        subgraph flutter["Flutter アプリ (Dart)"]
            ui["UI 層（MapLibre GL / Material 3）"]
            core["packages/core【純粋】<br/>開示判定・資材・建設・経済・区画"]
            loc["packages/location<br/>GPS変換・地図SDK連携"]
        end
        native["Kotlin ネイティブ (Pigeon channel)<br/>foreground位置記録・モック/速度検出・歩数・Health Connect"]
        gamedb[("ゲーム状態 SQLite")]
        pack[("地域パック（読取専用）<br/>MBTiles＋地形属性＋区画＋POI")]
    end

    cdn["🌐 静的ホスティング<br/>地域パック配布（初回DLのみ）"]
    ci["🛠 CI: Planetiler（ビルド時）<br/>OSM/国土数値情報→パック生成"]

    user -->|GPS移動| native
    native --> gamedb
    ui <--> core
    loc <--> core
    core <--> gamedb
    core -->|地形/区画/POI 参照| pack
    loc -->|表示専用タイル| pack
    cdn -.初回のみ.-> pack
    ci ==>|同梱/配布| pack

    classDef pure fill:#e8f5e9,stroke:#2e7d32;
    class core pure
```

> 依存方向: `core/`（純粋ロジック）は `location/`（GPS・地図SDK）を import しない一方向依存（[GPS_ARCHITECTURE 準拠](docs/architecture.md)）。
