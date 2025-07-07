#!/bin/bash

# Phase 3 手動設定確認スクリプト
echo "🔍 Phase 3 設定確認スクリプト"
echo "================================"

# プロジェクト設定確認
echo "📋 プロジェクト設定確認..."
if [ -f "pubspec.yaml" ]; then
    echo "✅ pubspec.yaml が見つかりました"
    if grep -q "firebase_crashlytics" pubspec.yaml; then
        echo "✅ Firebase Crashlytics 依存関係が追加されています"
    else
        echo "❌ Firebase Crashlytics 依存関係が見つかりません"
    fi
else
    echo "❌ pubspec.yaml が見つかりません"
fi

# Firebase設定ファイル確認
echo ""
echo "🔥 Firebase設定ファイル確認..."
if [ -f "lib/firebase_options.dart" ]; then
    echo "✅ firebase_options.dart が見つかりました"
else
    echo "❌ firebase_options.dart が見つかりません"
    echo "   firebase_core の flutterfire configure を実行してください"
fi

if [ -f "android/app/google-services.json" ]; then
    echo "✅ Android google-services.json が見つかりました"
else
    echo "❌ Android google-services.json が見つかりません"
fi

if [ -f "ios/Runner/GoogleService-Info.plist" ]; then
    echo "✅ iOS GoogleService-Info.plist が見つかりました"
else
    echo "❌ iOS GoogleService-Info.plist が見つかりません"
fi

# テストファイル確認
echo ""
echo "🧪 テストファイル確認..."
if [ -d "test/services" ]; then
    echo "✅ サービステストディレクトリが見つかりました"
    if [ -f "test/services/mvp_analytics_client_test.dart" ]; then
        echo "✅ MVPAnalyticsClient テストが見つかりました"
    else
        echo "❌ MVPAnalyticsClient テストが見つかりません"
    fi
else
    echo "❌ サービステストディレクトリが見つかりません"
fi

if [ -d "integration_test" ]; then
    echo "✅ 統合テストディレクトリが見つかりました"
else
    echo "❌ 統合テストディレクトリが見つかりません"
fi

# Cloud Run サービス確認
echo ""
echo "☁️  Cloud Run サービス確認..."
if [ -f "analytics-service/main.py" ]; then
    echo "✅ analytics-service が見つかりました"
    if grep -q "error_reporting" analytics-service/main.py; then
        echo "✅ Error Reporting 統合が確認されました"
    else
        echo "❌ Error Reporting 統合が見つかりません"
    fi
    if grep -q "report_critical_error" analytics-service/main.py; then
        echo "✅ 重大エラー報告機能が確認されました"
    else
        echo "❌ 重大エラー報告機能が見つかりません"
    fi
else
    echo "❌ analytics-service が見つかりません"
fi

# 手動設定チェックリスト表示
echo ""
echo "📝 手動設定チェックリスト"
echo "=========================="
echo "以下の設定を手動で確認・実行してください："
echo ""
echo "🔥 Firebase Console (https://console.firebase.google.com/)"
echo "   □ Crashlytics を有効化"
echo "   □ Authentication > 匿名認証 が有効"
echo "   □ Firestore Database が作成済み"
echo ""
echo "☁️  Google Cloud Console (https://console.cloud.google.com/)"
echo "   □ Cloud Error Reporting API が有効"
echo "   □ Cloud Logging API が有効"
echo "   □ Cloud Monitoring でアラートポリシー作成"
echo "   □ Redis インスタンス (Cloud Memorystore) 作成"
echo ""
echo "🚀 Cloud Run デプロイ"
echo "   □ analytics-service デプロイ完了"
echo "   □ 環境変数 (REDIS_HOST, REDIS_PASSWORD) 設定"
echo "   □ サービスアカウント権限設定"
echo ""
echo "📱 アプリビルド設定"
echo "   □ Android: firebase-crashlytics gradle plugin 追加"
echo "   □ iOS: Firebase Crashlytics Run Script 追加"
echo "   □ リリースビルドでのシンボルアップロード設定"
echo ""

# 環境変数確認
echo "🔧 環境変数確認..."
if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo "✅ GOOGLE_APPLICATION_CREDENTIALS が設定されています"
else
    echo "⚠️  GOOGLE_APPLICATION_CREDENTIALS が設定されていません（ローカル開発時のみ必要）"
fi

echo ""
echo "✨ 設定確認完了！"
echo "上記チェックリストの項目を全て完了すると、完全な監視体制が整います。"