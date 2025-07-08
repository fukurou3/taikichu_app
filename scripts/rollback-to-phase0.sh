#!/bin/bash
# Rollback script from Phase1 to Phase0
# Use this if Phase1 migration encounters issues

set -e

echo "🔄 Starting Phase1 to Phase0 rollback..."

# Configuration
PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
    echo "❌ Please authenticate with gcloud first"
    exit 1
fi

CURRENT_PROJECT=$(gcloud config get-value project)
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    gcloud config set project $PROJECT_ID
fi

echo "✅ Prerequisites check passed"

# Step 1: Redeploy Phase0 application
echo "📦 Redeploying Phase0 application..."

gcloud run deploy taikichu-app \
    --image gcr.io/$PROJECT_ID/taikichu-app:latest \
    --region $REGION \
    --set-env-vars "PHASE=0,NODE_ENV=production,LOG_LEVEL=ERROR" \
    --min-instances 1 \
    --max-instances 10 \
    --concurrency 40 \
    --cpu 1 \
    --memory 512Mi \
    --timeout 300

echo "✅ Phase0 application redeployed"

# Step 2: Verify Phase0 deployment
echo "🔍 Verifying Phase0 deployment..."

sleep 30

SERVICE_URL=$(gcloud run services describe taikichu-app --region $REGION --format="value(status.url)")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/health")

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Phase0 health check passed"
else
    echo "❌ Phase0 health check failed (HTTP $HTTP_CODE)"
    exit 1
fi

# Step 3: Clean up Redis resources (optional)
echo "🧹 Redis cleanup options:"
echo "  1. Keep Redis for quick re-migration"
echo "  2. Delete Redis to save costs"

read -p "Delete Redis resources? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Destroying Redis infrastructure..."
    cd scripts
    terraform destroy -var="project_id=$PROJECT_ID" -var="region=$REGION" -auto-approve
    echo "✅ Redis resources deleted"
else
    echo "💾 Redis resources preserved for future use"
fi

# Step 4: Clean up Phase1 artifacts
echo "🧽 Cleaning up Phase1 artifacts..."

if [ -f ".env.phase1" ]; then
    rm .env.phase1
    echo "✅ Phase1 environment file removed"
fi

if [ -f "phase1-monitoring.json" ]; then
    rm phase1-monitoring.json
    echo "✅ Phase1 monitoring config removed"
fi

# Step 5: Verify Phase0 functionality
echo "🧪 Testing Phase0 functionality..."

# Test key endpoints
echo "  Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s "$SERVICE_URL/health")
if echo "$HEALTH_RESPONSE" | grep -q "phase0"; then
    echo "  ✅ Health endpoint working"
else
    echo "  ⚠️  Health endpoint response: $HEALTH_RESPONSE"
fi

echo "🎉 Rollback to Phase0 completed successfully!"
echo ""
echo "📊 Current status:"
echo "  Phase: 0 (Firestore-only)"
echo "  Service URL: $SERVICE_URL"
echo "  Health: $SERVICE_URL/health"
echo ""
echo "💰 Cost savings restored:"
echo "  Estimated monthly cost: ¥6,250"
echo "  Daily budget: ¥450"
echo ""
echo "📈 If you need to migrate again:"
echo "  ./migrate-to-phase1.sh"