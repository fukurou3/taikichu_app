# 『待機中。』アプリ - スケーラブルアーキテクチャ

## 概要
企業レベルのSNSアプリを想定した、スケーラブルで効率的なアーキテクチャを実装。

## 🏗 アーキテクチャ概要

### データ構造の最適化
- **非正規化設計**: `counts`コレクションに集約フィールド保存
- **リアルタイム集約**: Cloud Functionsによる自動カウント更新
- **分散カウンター**: 高負荷対応の分散カウンターパターン

### パフォーマンス最適化
- **ページネーション**: 無限スクロール対応
- **StreamBuilder最適化**: キャッシュとデバウンス機能
- **バッチ処理**: 定期的なランキング更新

## 📊 Firestoreコレクション設計

### counts (カウントダウン)
```
{
  eventName: string,
  eventDate: timestamp,
  category: string,
  creatorId: string,
  participantsCount: number,    // リアルタイム更新
  likesCount: number,          // リアルタイム更新
  commentsCount: number,       // リアルタイム更新
  sharesCount: number          // 今後実装
}
```

### comments (コメント)
```
{
  countdownId: string,
  content: string,
  authorId: string,
  authorName: string,
  createdAt: timestamp,
  likesCount: number,
  repliesCount: number
}
```

### countdownLikes (いいね管理)
```
{
  countdownId: string,
  userId: string,
  createdAt: timestamp
}
```

### trendRankings (事前計算ランキング)
```
{
  countdownId: string,
  eventName: string,
  category: string,
  eventDate: timestamp,
  participantsCount: number,
  commentsCount: number,
  likesCount: number,
  sharesCount: number,
  trendScore: number,
  rank: number,
  updatedAt: timestamp
}
```

### countdownShards (分散カウンター)
```
{
  count: number
}
```

## ⚡ Cloud Functions

### トリガー関数
- `onCommentCreate`: コメント投稿時のカウント更新
- `onCommentDelete`: コメント削除時のカウント更新
- `onLikeCreate`: いいね時のカウント更新
- `onLikeDelete`: いいね解除時のカウント更新

### 定期実行関数
- `updateTrendRankings`: 5分ごとのランキング更新

### HTTP関数
- `manualUpdateTrendRankings`: 手動ランキング更新
- `incrementDistributedCounter`: 分散カウンター操作
- `getDistributedCounterTotal`: 分散カウンター合計取得

## 🎯 スケーラビリティ対策

### 1. クエリ最適化
- **複合インデックス**: 効率的なクエリ実行
- **ページネーション**: 大量データ対応
- **キャッシュ機能**: 重複読み込み防止

### 2. 書き込み最適化
- **分散カウンター**: ホットスポット回避
- **バッチ処理**: 効率的な一括更新
- **原子的操作**: データ整合性保証

### 3. ネットワーク最適化
- **StreamBuilder最適化**: 不要な更新削減
- **デバウンス処理**: API呼び出し制限
- **エラーハンドリング**: 堅牢性向上

## 🚀 デプロイメント

### 前提条件
1. Firebase CLI インストール
2. Node.js 18+ インストール
3. Firebase プロジェクト設定

### デプロイ手順

#### 1. Cloud Functions
```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

#### 2. Firestore Rules & Indexes
```bash
firebase deploy --only firestore
```

#### 3. Flutter アプリ
```bash
flutter build apk --release
# または
flutter build ios --release
```

## 📈 パフォーマンス指標

### 目標値
- **初期読み込み**: < 2秒
- **ページ遷移**: < 1秒
- **リアルタイム更新**: < 3秒
- **同時接続数**: 1000+

### 監視項目
- Firestore読み書き回数
- Cloud Functions実行時間
- アプリ起動時間
- メモリ使用量

## 🔧 運用・メンテナンス

### 定期メンテナンス
1. **インデックス最適化**: 月1回レビュー
2. **キャッシュクリア**: 週1回実行
3. **パフォーマンス監視**: 日次チェック

### トラブルシューティング
1. **高負荷時**: 分散カウンター増設
2. **レスポンス低下**: キャッシュ戦略見直し
3. **データ不整合**: Functions再実行

## 🎨 UI/UX最適化

### レスポンシブ対応
- 無限スクロール
- プルリフレッシュ
- ローディング状態表示

### アクセシビリティ
- スクリーンリーダー対応
- 適切なコントラスト
- タッチターゲットサイズ

## 🔒 セキュリティ

### Firestore Rules
- 認証ユーザーのみ書き込み
- 作成者のみ削除可能
- Cloud Functions専用書き込み

### データ保護
- 匿名認証使用
- 個人情報最小化
- GDPR準拠設計

## 📝 今後の拡張計画

### Phase 1 (短期)
- [ ] プッシュ通知
- [ ] 画像アップロード
- [ ] シェア機能

### Phase 2 (中期)
- [ ] ユーザープロフィール
- [ ] フォロー機能
- [ ] 検索機能強化

### Phase 3 (長期)
- [ ] AI による推奨
- [ ] 多言語対応
- [ ] Web版対応

---

このアーキテクチャにより、企業レベルの要求に対応できるスケーラブルなSNSアプリケーションを実現できます。