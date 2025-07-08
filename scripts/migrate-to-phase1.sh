#!/bin/bash
# Phase1 migration script - Redis integration for performance optimization
# Run this when Phase0 triggers indicate need for Phase1 migration
# Triggers: MAU > 8000, Firestore reads > 35M/day for 3 days, p95 latency > 780ms for 1 week

set -e

echo "🚀 Starting Phase0 to Phase1 migration..."

# Configuration
PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"
REDIS_INSTANCE_ID="taikichu-cache"

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check if gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
    echo "❌ Please authenticate with gcloud first"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is required but not installed"
    exit 1
fi

# Check current project
CURRENT_PROJECT=$(gcloud config get-value project)
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    echo "⚠️  Setting project to $PROJECT_ID"
    gcloud config set project $PROJECT_ID
fi

echo "✅ Prerequisites check passed"

# Step 1: Deploy Redis infrastructure
echo "🔧 Deploying Redis infrastructure..."
cd scripts
terraform init
terraform plan -var="project_id=$PROJECT_ID" -var="region=$REGION"

read -p "Deploy Redis infrastructure? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    terraform apply -var="project_id=$PROJECT_ID" -var="region=$REGION" -auto-approve
    echo "✅ Redis infrastructure deployed"
else
    echo "❌ Redis deployment cancelled"
    exit 1
fi

# Step 2: Get Redis connection details
echo "🔍 Retrieving Redis connection details..."
REDIS_HOST=$(terraform output -raw redis_host)
REDIS_PORT=$(terraform output -raw redis_port)
REDIS_AUTH=$(terraform output -raw redis_auth_string)

echo "📝 Redis Details:"
echo "  Host: $REDIS_HOST"
echo "  Port: $REDIS_PORT"
echo "  Auth: [SECURED]"

# Step 3: Update Cloud Run configuration for Phase1
echo "🔄 Updating Cloud Run configuration for Phase1..."
cd ..

# Create Phase1 environment variables file
cat > .env.phase1 << EOF
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_AUTH=$REDIS_AUTH
PHASE=1
CACHE_TTL=300
FANOUT_CACHE_ENABLED=true
TIMELINE_CACHE_ENABLED=true
EOF

echo "✅ Phase1 environment variables created"

# Step 4: Deploy updated application
echo "🚢 Deploying Phase1 application..."

# Build and deploy new container with Redis support
gcloud builds submit --tag gcr.io/$PROJECT_ID/taikichu-app:phase1 .

# Update Cloud Run service with Phase1 configuration
gcloud run deploy taikichu-app \
    --image gcr.io/$PROJECT_ID/taikichu-app:phase1 \
    --region $REGION \
    --set-env-vars "REDIS_HOST=$REDIS_HOST,REDIS_PORT=$REDIS_PORT,REDIS_AUTH=$REDIS_AUTH,PHASE=1" \
    --min-instances 1 \
    --max-instances 20 \
    --concurrency 80 \
    --cpu 2 \
    --memory 1Gi \
    --timeout 300

echo "✅ Phase1 application deployed"

# Step 5: Verify deployment
echo "🔍 Verifying Phase1 deployment..."

# Wait for deployment to be ready
sleep 30

# Get service URL
SERVICE_URL=$(gcloud run services describe taikichu-app --region $REGION --format="value(status.url)")

# Test health endpoint
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/health")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed (HTTP $HTTP_CODE)"
    exit 1
fi

# Test Redis connectivity (if health endpoint includes Redis check)
echo "🔗 Testing Redis connectivity..."
HEALTH_RESPONSE=$(curl -s "$SERVICE_URL/health")
if echo "$HEALTH_RESPONSE" | grep -q "redis.*connected"; then
    echo "✅ Redis connectivity verified"
else
    echo "⚠️  Redis connectivity could not be verified"
fi

# Step 6: Update monitoring and alerts
echo "📊 Updating monitoring for Phase1..."

# Create Phase1 monitoring dashboard config
cat > phase1-monitoring.json << EOF
{
  "phase": "1",
  "redis_monitoring": true,
  "alerts": {
    "redis_memory_usage": "80%",
    "redis_connection_errors": 10,
    "cache_hit_ratio": "below_70%",
    "timeline_p95_latency": "400ms"
  },
  "cost_limits": {
    "daily": 500,
    "monthly": 15000
  }
}
EOF

echo "✅ Phase1 monitoring configuration created"

# Step 7: Performance validation
echo "🏃 Running performance validation..."

# Wait for cache warm-up
echo "⏳ Waiting for cache warm-up (60 seconds)..."
sleep 60

# Run basic performance test
echo "🧪 Running timeline performance test..."
for i in {1..5}; do
    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" "$SERVICE_URL/api/timeline/test")
    echo "  Test $i: ${RESPONSE_TIME}s"
done

echo "🎉 Phase1 migration completed successfully!"
echo ""
echo "📈 Next steps:"
echo "  1. Monitor performance metrics for 24 hours"
echo "  2. Verify cache hit ratios > 70%"
echo "  3. Confirm p95 latency < 400ms"
echo "  4. Monitor costs stay under ¥500/day"
echo ""
echo "🔄 Rollback command (if needed):"
echo "  ./rollback-to-phase0.sh"
echo ""
echo "📊 Monitoring:"
echo "  Service URL: $SERVICE_URL"
echo "  Health: $SERVICE_URL/health"
echo "  Metrics: $SERVICE_URL/metrics"