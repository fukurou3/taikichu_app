# Firestore to Redis データ移行

## 概要

旧システムの完全撤廃のため、既存のFirestoreデータをRedisに移行する1回限りの移行スクリプトです。

## 移行対象データ

1. **countsコレクション** - カウントダウンメインデータ
2. **distributed_countersコレクション** - 分散カウンターデータ
3. **trendRankingsコレクション** - トレンドランキングデータ

## 前提条件

1. **環境設定**
   - Python 3.8以上
   - Google Cloud認証設定済み
   - Redis環境（ローカル/リモート）

2. **権限**
   - Firestore読み取り権限
   - Redis書き込み権限

## セットアップ

```bash
# 依存関係のインストール
pip install -r requirements.txt

# Google Cloud認証設定
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"
```

## 使用方法

### 1. テスト実行（DRY RUN）

```bash
python firestore_to_redis_migration.py --dry-run
```

- 実際の移行は行わず、データの調査と整合性検証のみ実行
- 移行対象データの確認
- データ不整合の検出

### 2. 本番移行

```bash
python firestore_to_redis_migration.py --migrate
```

- 実際のデータ移行を実行
- Redis環境にデータを書き込み
- 移行レポートの生成

### 3. オプション

```bash
# カスタムRedis設定
python firestore_to_redis_migration.py --migrate --redis-host redis.example.com --redis-port 6380
```

## 移行データ構造

### Redis Key構造

```
countdown:{countdown_id}          # カウントダウンメインデータ
counter:{countdown_id}            # カウンター値 (likes, comments, participants, views)
recent_counter:{countdown_id}     # 最近のカウンター値
ranking:{countdown_id}            # ランキングデータ
trend_scores                      # トレンドスコア (sorted set)
category:{category_name}          # カテゴリ別インデックス
ranking:{category_name}           # カテゴリ別ランキング
```

### データ例

```json
{
  "countdown:abc123": {
    "event_name": "東京オリンピック開会式",
    "description": "歴史的な瞬間まで #Tokyo2024",
    "event_date": "2024-07-26T20:00:00Z",
    "category": "スポーツ",
    "participants_count": 1500,
    "likes_count": 890,
    "comments_count": 234,
    "views_count": 5600,
    "trend_score": 87.5
  }
}
```

## 安全性とバックアップ

### 移行前の準備

1. **データバックアップ**
   ```bash
   # Firestoreエクスポート
   gcloud firestore export gs://your-backup-bucket/firestore-backup
   
   # Redis現在のデータ確認
   redis-cli --scan
   ```

2. **移行計画の確認**
   - 移行対象データの特定
   - ダウンタイムの計画
   - フォールバック手順の準備

### 移行中の監視

- スクリプトが自動生成するログファイル
- 移行レポート（JSON形式）
- データ整合性検証結果

### 移行後の確認

1. **データ整合性**
   ```bash
   # 移行後のデータ確認
   redis-cli hgetall countdown:abc123
   ```

2. **アプリケーション動作確認**
   - カウンター値の正確性
   - トレンドランキングの表示
   - 検索機能の動作

## トラブルシューティング

### よくある問題

1. **接続エラー**
   - Firebase認証の確認
   - Redis接続設定の確認

2. **データ不整合**
   - 分散カウンターの合計値不一致
   - 警告表示後の手動確認

3. **メモリ不足**
   - バッチサイズの調整
   - 分割実行の検討

### ログの確認

```bash
# 移行ログの確認
tail -f migration_20240707_120000.log

# 移行レポートの確認
cat migration_report_20240707_120000.json
```

## 移行後の作業

1. **旧システムの無効化**
   - レガシーサービスの削除
   - 古いCloud Functionsの削除

2. **新システムの有効化**
   - MVPAnalyticsClient経由のデータ取得
   - 統一パイプラインの完全移行

3. **監視とメンテナンス**
   - Redis監視の設定
   - 定期的なデータ整合性チェック