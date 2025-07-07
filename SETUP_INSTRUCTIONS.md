# 信頼性・安全性基盤 セットアップ手順書

## ✅ 完了済み項目

### 1. Firebase設定の更新
- [x] `admin_interface/lib/firebase_options.dart` - 実際のプロジェクト設定に更新済み
- [x] `lib/firebase_options.dart` - 既に正しい設定済み

## 🔧 手動設定が必要な項目

### 2. Firebase Console での設定

#### 2.1 メール/パスワード認証の有効化
1. **Firebase Console** にアクセス: https://console.firebase.google.com/
2. プロジェクト「taikichu-app-c8dcd」を選択
3. 左側メニューから **「Authentication」** を選択
4. **「Sign-in method」** タブをクリック
5. **「Email/Password」** を選択
6. **「Enable」** をオンにする
7. **「Save」** をクリック

### 3. Cloud Run Analytics Service のデプロイ

#### 3.1 サービスのビルドとデプロイ
```bash
cd analytics-service

# Dockerイメージをビルド
gcloud builds submit --tag gcr.io/taikichu-app-c8dcd/analytics-service

# Cloud Runにデプロイ
gcloud run deploy analytics-service \
  --image gcr.io/taikichu-app-c8dcd/analytics-service \
  --platform managed \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --set-env-vars="REDIS_HOST=YOUR_REDIS_HOST,REDIS_PORT=6379,ENVIRONMENT=production"
```

#### 3.2 デプロイ後のURL更新
デプロイ完了後に表示されるURLを以下のファイルに設定：

**admin_interface/lib/services/admin_api_service.dart**
```dart
// 変更前
static const String baseUrl = 'https://analytics-service-your-project.a.run.app';

// 変更後（実際のURL）
static const String baseUrl = 'https://analytics-service-xxxxx-aa.a.run.app';
```

### 4. 管理者権限の設定

#### 4.1 サービスアカウントキーの取得
1. Google Cloud Console → IAM & Admin → Service Accounts
2. Firebase Admin SDK service account を選択
3. 「Keys」タブ → 「Add Key」→ 「Create new key」(JSON)
4. ダウンロードしたキーファイルを `admin_scripts/service-account-key.json` に保存

#### 4.2 管理者アカウントの作成と権限付与
```bash
# 必要なパッケージをインストール
cd admin_scripts
pip install -r requirements.txt

# 環境変数設定
export GOOGLE_APPLICATION_CREDENTIALS="service-account-key.json"

# 最初の管理者アカウントを作成（Firebase Consoleで手動作成後）
# スーパーアドミン権限を付与
python setup_admin_roles.py set-role <USER_UID> superadmin

# 管理者一覧確認
python setup_admin_roles.py list-admins
```

### 5. Firestore セキュリティルールのデプロイ

```bash
# プロジェクトルートディレクトリで実行
firebase deploy --only firestore:rules
```

### 6. 管理画面のビルドとデプロイ

#### 6.1 ローカルでのテスト
```bash
cd admin_interface
flutter pub get
flutter run -d web-server --web-port 8080
```

#### 6.2 Firebase Hosting へのデプロイ
```bash
cd admin_interface

# Firebase プロジェクトの初期化（初回のみ）
firebase init hosting
# プロジェクト選択: taikichu-app-c8dcd
# Public directory: build/web
# Single-page app: Yes
# Set up automatic builds: No

# ビルドとデプロイ
flutter build web --release
firebase deploy --only hosting
```

### 7. Redis インスタンスの設定（必要に応じて）

#### 7.1 Google Cloud Memorystore の作成
```bash
gcloud redis instances create taikichu-redis \
    --size=1 \
    --region=asia-northeast1 \
    --redis-version=redis_6_x
```

#### 7.2 Redis接続情報の取得
```bash
gcloud redis instances describe taikichu-redis --region=asia-northeast1
```

### 8. 動作確認チェックリスト

#### 8.1 基本機能テスト
- [ ] 管理画面にログイン可能
- [ ] ダッシュボードが正常に表示される
- [ ] 通報キューが表示される（空でも可）
- [ ] ユーザー検索が動作する
- [ ] コンテンツモデレーション機能が動作する

#### 8.2 API接続テスト
- [ ] Cloud Run analytics-service にアクセス可能
- [ ] `/health` エンドポイントが正常応答
- [ ] 管理者API（要認証）が正常動作

#### 8.3 セキュリティテスト
- [ ] 権限のないユーザーは管理画面にアクセス不可
- [ ] Firestore rules により直接アクセスが拒否される
- [ ] 管理者操作が監査ログに記録される

### 9. 本運用時の設定

#### 9.1 アラート設定
```bash
# Cloud Loggingアラートの設定
gcloud alpha logging sinks create moderation-alerts \
  pubsub.googleapis.com/projects/taikichu-app-c8dcd/topics/admin-alerts \
  --log-filter='resource.type="cloud_run_revision" AND severity>=ERROR'
```

#### 9.2 定期バックアップ
- Firestore の自動バックアップを有効化
- 管理者権限の定期監査

### 10. トラブルシューティング

#### 10.1 よくある問題
**管理画面でログインできない**
- Firebase Authentication でメール/パスワードが有効化されているか確認
- ユーザーに適切な権限（custom claims）が設定されているか確認

**API接続エラー**
- Cloud Run サービスがデプロイされているか確認
- admin_api_service.dart の baseUrl が正しいか確認
- Firebase Admin SDK の認証情報が正しく設定されているか確認

**権限エラー**
- IAM 権限でCloud Run Invoker が設定されているか確認
- サービスアカウントキーが正しくアップロードされているか確認

## 緊急時連絡先

- **技術責任者**: [設定してください]
- **プロジェクト管理者**: [設定してください]
- **システム管理者**: [設定してください]

---

## 📋 設定進捗チェック

- [ ] Firebase Authentication 有効化
- [ ] Cloud Run analytics-service デプロイ
- [ ] 管理者権限設定
- [ ] Firestore rules デプロイ
- [ ] 管理画面デプロイ
- [ ] 動作確認完了
- [ ] 運用体制構築完了

設定完了後、実際に通報→モデレーション→監査ログ確認の一連の流れをテストしてください。