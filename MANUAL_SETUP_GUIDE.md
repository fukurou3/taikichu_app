# Phase 3 手動設定ガイド

このガイドでは、Phase 3 で構築した監視・テスト体制を完全に有効化するための手動設定手順を説明します。

## 🔥 Firebase Console 設定

### 1. Crashlytics 有効化

1. [Firebase Console](https://console.firebase.google.com/) にアクセス
2. プロジェクトを選択
3. 左メニューから「Crashlytics」をクリック
4. 「Crashlytics を開始する」をクリック
5. iOS/Android アプリでそれぞれ「アプリを設定」を完了

### 2. Authentication 設定

1. 左メニューから「Authentication」をクリック
2. 「Sign-in method」タブを選択
3. 「匿名」認証が「有効」になっていることを確認
4. 無効の場合は有効化する

## ☁️ Google Cloud Console 設定

### 1. 必要なAPI有効化

```bash
# Cloud Shell または gcloud CLI で実行
gcloud services enable clouderrorreporting.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable redis.googleapis.com
```

### 2. Redis インスタンス作成

```bash
# Cloud Memorystore Redis インスタンス作成
gcloud redis instances create taikichu-redis \
  --size=1 \
  --region=asia-northeast1 \
  --redis-version=redis_6_x \
  --network=default
```

### 3. サービスアカウント権限設定

```bash
# プロジェクトIDを変数に設定
export PROJECT_ID="your-project-id"

# Cloud Run のデフォルトサービスアカウントに権限付与
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$PROJECT_ID-compute@developer.gserviceaccount.com" \
  --role="roles/errorreporting.writer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$PROJECT_ID-compute@developer.gserviceaccount.com" \
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$PROJECT_ID-compute@developer.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"
```

## 🚀 Cloud Run デプロイ

### 1. analytics-service デプロイ

```bash
# analytics-service ディレクトリで実行
cd analytics-service

# Redis インスタンスの内部IPを取得
export REDIS_IP=$(gcloud redis instances describe taikichu-redis --region=asia-northeast1 --format="value(host)")

# Cloud Run にデプロイ
gcloud run deploy analytics-service \
  --source . \
  --platform managed \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --set-env-vars="REDIS_HOST=$REDIS_IP,ENVIRONMENT=production" \
  --memory=1Gi \
  --cpu=1000m \
  --max-instances=10
```

### 2. Cloud Run URLの更新

デプロイ完了後、表示されるURLを以下のファイルで更新：

```dart
// lib/services/mvp_analytics_client.dart
static const String _baseUrl = 'https://analytics-service-xxxxx-an.a.run.app';
```

## 📊 Cloud Monitoring アラート設定

### 1. エラー率アラート

1. [Cloud Monitoring](https://console.cloud.google.com/monitoring) にアクセス
2. 「Alerting」> 「Create Policy」をクリック
3. 以下の条件を設定：
   - **Resource**: Cloud Run サービス (analytics-service)
   - **Metric**: Request count (エラーレスポンス 4xx, 5xx)
   - **Condition**: Rate > 5% for 5 minutes
4. 通知チャンネルを設定（Email推奨）

### 2. レスポンス時間アラート

1. 新しいアラートポリシーを作成
2. 以下の条件を設定：
   - **Resource**: Cloud Run サービス (analytics-service)
   - **Metric**: Request latencies
   - **Condition**: 95th percentile > 5000ms for 5 minutes
3. 同じ通知チャンネルを設定

### 3. Crashlytics アラート

1. Firebase Console の「Crashlytics」で設定
2. 「設定」タブから「アラート」を選択
3. 「新しいクラッシュが発生したときに通知」を有効化
4. 通知先メールアドレスを設定

## 📱 アプリビルド設定

### Android 設定

`android/app/build.gradle` に以下を追加（未追加の場合）：

```gradle
plugins {
    id 'com.android.application'
    id 'kotlin-android'
    id 'dev.flutter.flutter-gradle-plugin'
    id 'com.google.gms.google-services'
    id 'com.google.firebase.crashlytics'  // 追加
}

dependencies {
    implementation 'com.google.firebase:firebase-crashlytics:18.6.1'
    implementation 'com.google.firebase:firebase-analytics:21.5.0'
}

android {
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
            
            // Crashlytics設定
            firebaseCrashlytics {
                mappingFileUploadEnabled true
            }
        }
    }
}
```

### iOS 設定

1. Xcode で `ios/Runner.xcworkspace` を開く
2. Runner target を選択
3. 「Build Phases」タブを選択
4. 「+」ボタンから「New Run Script Phase」を追加
5. スクリプト内容を入力：
```bash
"${PODS_ROOT}/FirebaseCrashlytics/run"
```
6. 「Input Files」に追加：
```
$(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)
```

## 🧪 テスト実行

すべての設定完了後、テストを実行：

```bash
# 設定確認
./scripts/verify_setup.sh

# テスト実行
./scripts/run_tests.sh
```

## ✅ 設定完了確認

以下が正常に動作することを確認：

1. **単体テスト**: `flutter test` が成功
2. **統合テスト**: `flutter test integration_test/` が成功
3. **Crashlytics**: リリースビルドでクラッシュレポートが送信される
4. **Error Reporting**: Cloud Run でエラーが記録される
5. **アラート**: 設定した条件でアラートが発火する

## 🔧 トラブルシューティング

### よくある問題

1. **Crashlytics でレポートが表示されない**
   - リリースビルドでテストしているか確認
   - プロジェクトの Crashlytics 有効化を確認
   - dSYM/ProGuardマッピングファイルアップロードを確認

2. **Cloud Run エラーが Error Reporting に表示されない**
   - サービスアカウント権限を確認
   - Error Reporting API が有効か確認
   - ログレベルが CRITICAL 以上に設定されているか確認

3. **Redis 接続エラー**
   - VPC ネットワーク設定を確認
   - Cloud Run から Redis への接続許可を確認

この設定を完了すると、Phase 3 の監視・エラー報告体制が完全に機能します。