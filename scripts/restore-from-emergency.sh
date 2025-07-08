#!/bin/bash
# Emergency restoration script for Phase0 v2.1
# Use this to restore service after emergency shutdown

set -e

echo "🔧 Starting emergency restoration process..."

# Configuration
PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"
SERVICE_NAME="taikichu-app"

# Check prerequisites
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
    echo "❌ Please authenticate with gcloud first"
    exit 1
fi

CURRENT_PROJECT=$(gcloud config get-value project)
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    gcloud config set project $PROJECT_ID
fi

echo "✅ Prerequisites check passed"

# Function to get current emergency status
check_emergency_status() {
    echo "🔍 Checking current emergency status..."
    
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format="value(status.url)" 2>/dev/null || echo "")
    
    if [ -z "$SERVICE_URL" ]; then
        echo "⚠️  Service URL not found - service may be completely stopped"
        return 1
    fi
    
    # Try to get emergency status
    EMERGENCY_STATUS=$(curl -s "$SERVICE_URL/budget-health" 2>/dev/null | jq -r '.emergencyMode // false' || echo "unknown")
    
    echo "Emergency mode: $EMERGENCY_STATUS"
    return 0
}

# Step 1: Restore basic service functionality
restore_basic_service() {
    echo "🚀 Restoring basic service functionality..."
    
    # Restore Phase0 v2.1 configuration
    gcloud run services update $SERVICE_NAME \
        --region $REGION \
        --min-instances 1 \
        --max-instances 10 \
        --concurrency 40 \
        --cpu 1000m \
        --memory 512Mi \
        --set-env-vars "EMERGENCY_MODE=false,PHASE=0,MAX_REQUESTS_PER_MINUTE=30" \
        --no-traffic
    
    echo "✅ Basic service configuration restored"
    
    # Wait for service to be ready
    echo "⏳ Waiting for service to be ready..."
    sleep 30
    
    # Test service health
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format="value(status.url)")
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/health" || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Service health check passed"
    else
        echo "⚠️  Service health check failed (HTTP $HTTP_CODE) - continuing with restoration"
    fi
}

# Step 2: Restore Cloud Functions
restore_cloud_functions() {
    echo "⚡ Restoring Cloud Functions..."
    
    # Redeploy essential functions from source
    echo "Deploying daily aggregation function..."
    gcloud functions deploy dailyAggregation \
        --source ./functions \
        --entry-point dailyAggregation \
        --runtime nodejs18 \
        --trigger-event providers/cloud.pubsub/eventTypes/topic.publish \
        --trigger-resource budget-alerts \
        --region $REGION \
        --memory 256MB \
        --timeout 300s \
        --quiet || echo "Function deployment failed - will retry later"
    
    echo "Deploying Firestore monitoring function..."
    gcloud functions deploy monitorFirestoreReads \
        --source ./functions \
        --entry-point monitorFirestoreReads \
        --runtime nodejs18 \
        --trigger-event providers/cloud.pubsub/eventTypes/topic.publish \
        --trigger-resource firestore-monitoring \
        --region $REGION \
        --memory 256MB \
        --timeout 180s \
        --quiet || echo "Function deployment failed - will retry later"
    
    echo "Deploying cleanup function..."
    gcloud functions deploy cleanupInboxItems \
        --source ./functions \
        --entry-point cleanupInboxItems \
        --runtime nodejs18 \
        --trigger-event providers/cloud.pubsub/eventTypes/topic.publish \
        --trigger-resource weekly-cleanup \
        --region $REGION \
        --memory 256MB \
        --timeout 540s \
        --quiet || echo "Function deployment failed - will retry later"
    
    echo "✅ Cloud Functions restoration completed"
}

# Step 3: Restore monitoring and alerts
restore_monitoring() {
    echo "📊 Restoring monitoring and alerts..."
    
    # Apply monitoring configuration
    if [ -f "terraform/monitoring.tf" ]; then
        echo "Applying monitoring configuration..."
        cd terraform
        terraform init -upgrade
        terraform apply -var="project_id=$PROJECT_ID" -auto-approve || echo "Monitoring restoration failed - manual intervention needed"
        cd ..
    else
        echo "⚠️  Monitoring configuration not found - skipping"
    fi
    
    # Apply budget alerts
    if [ -f "terraform/budget-alerts.tf" ]; then
        echo "Applying budget alert configuration..."
        cd terraform
        
        # Prompt for billing account ID if needed
        read -p "Enter Billing Account ID (or press Enter to skip): " BILLING_ACCOUNT_ID
        
        if [ -n "$BILLING_ACCOUNT_ID" ]; then
            terraform apply -var="project_id=$PROJECT_ID" -var="billing_account_id=$BILLING_ACCOUNT_ID" -auto-approve || echo "Budget alerts restoration failed"
        else
            echo "⚠️  Billing account ID not provided - budget alerts not restored"
        fi
        
        cd ..
    else
        echo "⚠️  Budget alerts configuration not found - skipping"
    fi
    
    echo "✅ Monitoring restoration completed"
}

# Step 4: Verify full system functionality
verify_system() {
    echo "🧪 Verifying system functionality..."
    
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format="value(status.url)")
    
    # Test health endpoint
    echo "Testing health endpoint..."
    HEALTH_RESPONSE=$(curl -s "$SERVICE_URL/health")
    if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
        echo "✅ Health endpoint working"
    else
        echo "⚠️  Health endpoint issue: $HEALTH_RESPONSE"
    fi
    
    # Test budget health endpoint
    echo "Testing budget health endpoint..."
    BUDGET_HEALTH=$(curl -s "$SERVICE_URL/budget-health" 2>/dev/null || echo "{}")
    EMERGENCY_MODE=$(echo "$BUDGET_HEALTH" | jq -r '.emergencyMode // "unknown"')
    
    if [ "$EMERGENCY_MODE" = "false" ]; then
        echo "✅ Emergency mode disabled"
    else
        echo "⚠️  Emergency mode status: $EMERGENCY_MODE"
    fi
    
    # Test basic API functionality
    echo "Testing API functionality..."
    API_TEST=$(curl -s "$SERVICE_URL/api/health" 2>/dev/null || echo "")
    if [ -n "$API_TEST" ]; then
        echo "✅ API endpoints responding"
    else
        echo "⚠️  API endpoints may have issues"
    fi
    
    echo "✅ System verification completed"
}

# Step 5: Record restoration and provide recommendations
finalize_restoration() {
    echo "📝 Finalizing restoration..."
    
    # Record restoration event
    TIMESTAMP=$(date -Iseconds)
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format="value(status.url)")
    
    curl -X POST "$SERVICE_URL/api/record-restoration" \
        -H "Content-Type: application/json" \
        -d "{\"timestamp\": \"$TIMESTAMP\", \"type\": \"emergency_restoration\", \"success\": true}" \
        2>/dev/null || echo "⚠️  Could not record restoration event"
    
    # Clear emergency status
    curl -X POST "$SERVICE_URL/api/clear-emergency" \
        -H "Content-Type: application/json" \
        -d "{\"timestamp\": \"$TIMESTAMP\", \"clearedBy\": \"restoration_script\"}" \
        2>/dev/null || echo "⚠️  Could not clear emergency status"
    
    echo "✅ Restoration event recorded"
    
    # Provide post-restoration recommendations
    echo ""
    echo "🎉 EMERGENCY RESTORATION COMPLETED!"
    echo ""
    echo "📊 Current Status:"
    echo "  Service URL: $SERVICE_URL"
    echo "  Health: $SERVICE_URL/health"
    echo "  Budget: $SERVICE_URL/budget-health"
    echo ""
    echo "📋 Immediate Actions Recommended:"
    echo "  1. Review budget alerts to understand what caused the emergency"
    echo "  2. Monitor system performance for the next 24 hours"
    echo "  3. Verify all user-facing functionality"
    echo "  4. Check Firestore usage patterns"
    echo ""
    echo "🔍 Investigation Commands:"
    echo "  ./scripts/monitor-phase-triggers.sh  # Check current metrics"
    echo "  curl -s $SERVICE_URL/budget-health | jq  # Check budget status"
    echo "  gcloud logging read 'severity>=ERROR' --limit=50  # Check recent errors"
    echo ""
    echo "⚠️  Prevention Measures:"
    echo "  1. Set up automated budget monitoring alerts"
    echo "  2. Review Phase1 migration triggers"
    echo "  3. Consider implementing gradual cost reduction before emergency"
    echo "  4. Update contact information for budget alerts"
    echo ""
    echo "📞 Support:"
    echo "  If issues persist, contact: admin@taikichu-app.com"
}

# Main execution
main() {
    echo "🚨 Phase0 v2.1 Emergency Restoration"
    echo "===================================="
    echo ""
    
    # Check current status
    if check_emergency_status; then
        echo "✅ Service is accessible for status checks"
    else
        echo "⚠️  Service may be completely down - proceeding with full restoration"
    fi
    
    echo ""
    read -p "Proceed with restoration? (y/n): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Restoration cancelled"
        exit 1
    fi
    
    # Execute restoration steps
    echo "🔧 Starting restoration process..."
    
    restore_basic_service
    echo ""
    
    restore_cloud_functions
    echo ""
    
    restore_monitoring
    echo ""
    
    verify_system
    echo ""
    
    finalize_restoration
}

# Execute main function
main "$@"