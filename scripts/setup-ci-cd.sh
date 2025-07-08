#!/bin/bash

# CI/CD セットアップ確認スクリプト
# GitHub Actions パイプラインの設定確認

echo "🔧 CI/CD セットアップ確認中..."

# 1. Firebase CLI の確認
echo "📋 Firebase CLI チェック..."
if command -v firebase &> /dev/null; then
    echo "✅ Firebase CLI がインストール済み"
    firebase --version
else
    echo "❌ Firebase CLI がインストールされていません"
    echo "   npm install -g firebase-tools でインストールしてください"
fi

# 2. Google Cloud CLI の確認
echo "📋 Google Cloud CLI チェック..."
if command -v gcloud &> /dev/null; then
    echo "✅ Google Cloud CLI がインストール済み"
    gcloud version
else
    echo "❌ Google Cloud CLI がインストールされていません"
    echo "   https://cloud.google.com/sdk/docs/install からインストールしてください"
fi

# 3. GitHub Actions ワークフローファイルの確認
echo "📋 GitHub Actions ワークフロー確認..."
if [[ -f ".github/workflows/main.yml" ]]; then
    echo "✅ GitHub Actions ワークフローファイルが存在します"
    echo "   📄 .github/workflows/main.yml"
else
    echo "❌ GitHub Actions ワークフローファイルが見つかりません"
fi

# 4. 必要なファイルの存在確認
echo "📋 プロジェクトファイル確認..."
files=("pubspec.yaml" "functions/package.json" "analytics-service/requirements.txt")
for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✅ $file"
    else
        echo "❌ $file が見つかりません"
    fi
done

echo ""
echo "🚀 次のステップ:"
echo "1. firebase login:ci でトークンを生成"
echo "2. gcloud auth login でGoogle Cloudにログイン"
echo "3. Service Account を作成し、キーを生成"
echo "4. GitHubリポジトリのSecretsに FIREBASE_TOKEN と GCP_SA_KEY を設定"
echo "5. mainブランチにコミット・プッシュしてパイプラインをテスト"
echo ""
echo "📖 詳細: https://github.com/anthropics/claude-code/blob/main/docs/github-actions.md"