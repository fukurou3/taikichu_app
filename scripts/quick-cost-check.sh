#!/bin/bash
# Quick cost-generating services check
# Lists all potentially expensive services that should be reviewed

echo "💰 Quick Cost-Generating Services Check"
echo "======================================"

PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"

# Set project
gcloud config set project $PROJECT_ID

echo "📊 Project: $PROJECT_ID"
echo "🌏 Region: $REGION"
echo ""

# Function to check and display service status
check_service() {
    local service_name="$1"
    local check_command="$2"
    local cost_estimate="$3"
    
    echo -n "🔍 $service_name: "
    
    if eval "$check_command" &>/dev/null; then
        local count=$(eval "$check_command" | wc -l)
        if [ $count -gt 0 ]; then
            echo -e "\033[0;31m$count active ($cost_estimate)\033[0m"
            eval "$check_command"
        else
            echo -e "\033[0;32mNone found\033[0m"
        fi
    else
        echo -e "\033[0;33mAPI not enabled or error\033[0m"
    fi
    echo ""
}

# Check high-cost services
echo "🚨 HIGH-COST SERVICES:"
echo "====================="

check_service "Cloud Memorystore (Redis)" \
    "gcloud redis instances list --region=$REGION --format='value(name)'" \
    "¥3,000-5,000/month per instance"

check_service "AlloyDB Clusters" \
    "gcloud alloydb clusters list --region=$REGION --format='value(name)'" \
    "¥15,000-30,000/month per cluster"

check_service "Cloud SQL Instances" \
    "gcloud sql instances list --format='value(name)'" \
    "¥5,000-15,000/month per instance"

check_service "GKE Clusters" \
    "gcloud container clusters list --region=$REGION --format='value(name)'" \
    "¥10,000-25,000/month per cluster"

echo "💡 MEDIUM-COST SERVICES:"
echo "========================"

check_service "Compute Engine VMs" \
    "gcloud compute instances list --format='value(name,zone)'" \
    "¥2,000-10,000/month per instance"

check_service "Persistent Disks" \
    "gcloud compute disks list --format='value(name,sizeGb,zone)'" \
    "¥100-500/month per 100GB"

check_service "Load Balancers" \
    "gcloud compute forwarding-rules list --format='value(name)'" \
    "¥2,000-5,000/month per LB"

check_service "App Engine Services" \
    "gcloud app services list --format='value(id)'" \
    "¥1,000-5,000/month"

echo "✅ PHASE0 ESSENTIAL SERVICES:"
echo "============================="

check_service "Cloud Run Services" \
    "gcloud run services list --region=$REGION --format='value(metadata.name)'" \
    "¥2,100/month (Phase0 budget)"

check_service "Cloud Functions" \
    "gcloud functions list --region=$REGION --format='value(name)'" \
    "¥50-200/month (Phase0 budget)"

echo "📋 STORAGE SERVICES:"
echo "==================="

check_service "Cloud Storage Buckets" \
    "gsutil ls" \
    "¥100-500/month per 100GB"

check_service "BigQuery Datasets" \
    "bq ls --format=csv | tail -n +2 | cut -d, -f1" \
    "¥100-1000/month per TB"

# Quick cost estimation
echo "💰 ESTIMATED MONTHLY COSTS:"
echo "==========================="

# Get actual Cloud Run info
CLOUD_RUN_COUNT=$(gcloud run services list --region=$REGION --format='value(metadata.name)' | wc -l)
CLOUD_FUNCTIONS_COUNT=$(gcloud functions list --region=$REGION --format='value(name)' | wc -l)

echo "Phase0 Essential Services:"
echo "  - Cloud Run ($CLOUD_RUN_COUNT services): ¥2,100"
echo "  - Cloud Functions ($CLOUD_FUNCTIONS_COUNT functions): ¥50"
echo "  - Firestore: ¥2,534 (40M reads + 1M writes)"
echo "  - Firebase Hosting: ¥620"
echo "  - Cloud Storage: ¥107"
echo "  - Cloud Logging: ¥775"
echo "  ─────────────────────────"
echo "  Total Phase0: ¥6,186"
echo ""

# Generate cleanup command
echo "🧹 CLEANUP COMMAND:"
echo "=================="
echo "To remove all non-Phase0 services:"
echo "  ./scripts/cleanup-unused-services.sh"
echo ""

echo "⚠️  IMMEDIATE ACTION REQUIRED FOR:"
echo "================================="

# Check for expensive services that should be deleted immediately
REDIS_COUNT=$(gcloud redis instances list --region=$REGION --format='value(name)' 2>/dev/null | wc -l)
ALLOYDB_COUNT=$(gcloud alloydb clusters list --region=$REGION --format='value(name)' 2>/dev/null | wc -l)
SQL_COUNT=$(gcloud sql instances list --format='value(name)' 2>/dev/null | wc -l)
GKE_COUNT=$(gcloud container clusters list --region=$REGION --format='value(name)' 2>/dev/null | wc -l)

TOTAL_HIGH_COST=$((REDIS_COUNT + ALLOYDB_COUNT + SQL_COUNT + GKE_COUNT))

if [ $TOTAL_HIGH_COST -gt 0 ]; then
    echo -e "\033[0;31m❌ Found $TOTAL_HIGH_COST high-cost services still running!\033[0m"
    echo "Estimated EXCESS cost: ¥$(($REDIS_COUNT * 4000 + $ALLOYDB_COUNT * 20000 + $SQL_COUNT * 8000 + $GKE_COUNT * 15000))/month"
    echo ""
    echo "Run cleanup immediately:"
    echo "  ./scripts/cleanup-unused-services.sh"
else
    echo -e "\033[0;32m✅ No high-cost services found - Phase0 budget on track!\033[0m"
fi

echo ""
echo "📊 For detailed cleanup:"
echo "  ./scripts/cleanup-unused-services.sh"
echo ""
echo "📈 For current billing:"
echo "  gcloud billing accounts list"
echo "  gcloud billing budgets list --billing-account=YOUR_BILLING_ACCOUNT"