# terra-town 環境構成図（MVP / ゲート②）

> spec-kit plan 工程の環境構成図。MVP は **端末内完結（ステートフルなバックエンドなし）**。
> 外部との通信は「地域パックの初回ダウンロード（静的ファイル・任意）」のみで、**歩行位置はサーバに送信しない**。
> 変更を伴う実装をしたら、コードと同じコミットで本図と README を更新する。

## MVP 構成（端末内完結）

```mermaid
flowchart TB
    user([プレイヤー / 歩く人])

    subgraph device["📱 ユーザー端末（Android 先行 / 将来 iOS）"]
        direction TB
        subgraph flutter["Flutter アプリ (Dart)"]
            ui["UI 層<br/>地図・建設・図鑑・HUD<br/>(MapLibre GL / Material 3)"]
            core["packages/core【純粋】<br/>開示判定・資材・建設・経済・区画集計<br/>抽象: PositionProvider / TileId / TerrainType"]
            loc["packages/location<br/>GPS変換・地図SDK連携<br/>(core の抽象を実装)"]
        end
        subgraph native["Kotlin ネイティブ (platform channel / Pigeon)"]
            fg["foreground service<br/>fused location・距離ベース記録<br/>elapsedRealtime"]
            anti["モック検出 / 速度・テレポート判定 / 歩数センサー"]
            health["Health Connect（オプトイン）"]
        end
        subgraph store["端末内ストレージ"]
            gamedb[("ゲーム状態 SQLite<br/>開示メッシュ(bitmap)・資材・建物・区画・図鑑")]
            pack[("地域パック（読取専用）<br/>MBTiles ＋ mesh_terrain ＋ 行政区域 ＋ POI")]
        end
        exp["エクスポート/インポート<br/>（機種変更対策・端末内/共有シート）"]
    end

    subgraph static["🌐 静的ホスティング（BEではない・初回DLのみ）"]
        cdn["地域パック配布<br/>GitHub Releases / Cloudflare R2 等<br/>※地域選択のみ漏れる・歩行位置は送らない"]
    end

    subgraph ci["🛠 CI / ビルド時のみ（実行時サーバではない）"]
        planetiler["Planetiler / osmium<br/>OSM日本抽出→ベクタタイル＋メッシュ地形属性 事前計算"]
        osm["OpenStreetMap (ODbL)<br/>国土数値情報 N03（行政区域）"]
    end

    user -->|GPS移動| fg
    fg --> gamedb
    anti --> core
    health -.オプトイン.-> core
    loc <--> core
    ui <--> core
    loc -->|表示専用タイル| pack
    core -->|地形属性/区画/POI 参照| pack
    core <--> gamedb
    gamedb <--> exp
    cdn -.初回のみDL.-> pack
    osm --> planetiler
    planetiler ==>|ビルド成果物| cdn
    planetiler ==>|同梱| pack

    classDef pure fill:#e8f5e9,stroke:#2e7d32;
    classDef nobe fill:#fff3e0,stroke:#ef6c00;
    class core pure
    class static,cdn nobe
```

## 依存方向（GPS_ARCHITECTURE 準拠）

```mermaid
flowchart LR
    app["app / composition root"] --> loc["location/"]
    app --> core["core/【純粋】"]
    loc --> core
    core -. import 禁止 .-x loc

    classDef pure fill:#e8f5e9,stroke:#2e7d32;
    class core pure
```

- `core/` は `location/`（GPS・地図SDK）を **import しない**。依存は `location/ → core/` の一方向。
- pubspec 依存で物理強制し、CI で import 方向を静的チェックする。

## 将来（#16 ソーシャル導入時に初めて BE）

- ランキング・フレンド街見学のため、ここで初めて**ステートフルなバックエンド**を導入する。
- 同時に GPS 偽装対策 ④（Play Integrity / サーバ照合）を有効化（対人不正の被害がここで発生するため）。
- 本図はその段階で更新する。
