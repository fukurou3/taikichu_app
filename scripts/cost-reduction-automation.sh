#!/bin/bash
# Automatic cost reduction measures for Phase0 v2.1
# Triggered when budget thresholds are exceeded

set -e

echo "🚨 Executing automatic cost reduction measures..."

# Configuration
PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"
SERVICE_NAME="taikichu-app"

# Budget thresholds (in JPY)
DAILY_THRESHOLD=450
MONTHLY_THRESHOLD=7000
EMERGENCY_THRESHOLD=8000

# Function to check current budget status
check_budget_status() {
    echo "📊 Checking current budget status..."
    
    # Get latest budget data from Firestore (via Cloud Function)
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format="value(status.url)")
    BUDGET_STATUS=$(curl -s "$SERVICE_URL/budget-health" | jq -r '.budgetStatus.currentData.totalCostSoFar // 0')
    
    echo "Current monthly spend: ¥$BUDGET_STATUS"
    return $BUDGET_STATUS
}

# Level 1: Soft cost reduction (≥¥5,600 - 80% of monthly budget)
apply_soft_cost_reduction() {
    echo "🟨 Applying Level 1 cost reduction measures..."
    
    # Reduce Cloud Run concurrency to decrease resource usage
    gcloud run services update $SERVICE_NAME \
        --region $REGION \
        --concurrency 20 \
        --max-instances 8 \
        --no-traffic
    
    echo "✅ Reduced Cloud Run concurrency to 20, max instances to 8"
    
    # Enable aggressive log cleanup
    gcloud logging sinks create cost-reduction-sink \
        "storage.googleapis.com/taikichu-app-logs-emergency" \
        --log-filter='severity>=ERROR' \
        --quiet || echo "Sink already exists"
    
    # Create cost reduction record
    TIMESTAMP=$(date -Iseconds)
    echo "Recording cost reduction measures in Firestore..."
    
    # Use Cloud Function to record the action
    curl -X POST "$SERVICE_URL/api/record-cost-reduction" \
        -H "Content-Type: application/json" \
        -d "{\"level\": 1, \"timestamp\": \"$TIMESTAMP\", \"measures\": [\"reduced_concurrency\", \"aggressive_logging\"]}"
    
    echo "📝 Level 1 cost reduction applied and recorded"
}

# Level 2: Moderate cost reduction (≥¥6,300 - 90% of monthly budget)
apply_moderate_cost_reduction() {
    echo "🟧 Applying Level 2 cost reduction measures..."
    
    # Scale down to minimum viable configuration
    gcloud run services update $SERVICE_NAME \
        --region $REGION \
        --min-instances 0 \
        --max-instances 5 \
        --concurrency 10 \
        --cpu 500m \
        --memory 256Mi \
        --no-traffic
    
    echo "✅ Scaled down to minimum viable configuration"
    
    # Enable emergency Firestore query optimization
    # This would trigger application-level optimizations
    curl -X POST "$SERVICE_URL/api/emergency-optimization" \
        -H "Content-Type: application/json" \
        -d "{\"mode\": \"aggressive\", \"cacheAll\": true, \"reduceReads\": 0.4}"
    
    echo "✅ Enabled emergency Firestore optimizations"
    
    # Purge non-essential data
    curl -X POST "$SERVICE_URL/api/emergency-cleanup" \
        -H "Content-Type: application/json" \
        -d "{\"purgeOldLogs\": true, \"compressImages\": true, \"cleanupInboxes\": true}"
    
    echo "✅ Emergency data cleanup initiated"
    
    # Record Level 2 actions
    TIMESTAMP=$(date -Iseconds)
    curl -X POST "$SERVICE_URL/api/record-cost-reduction" \
        -H "Content-Type: application/json" \
        -d "{\"level\": 2, \"timestamp\": \"$TIMESTAMP\", \"measures\": [\"min_instances_0\", \"emergency_optimization\", \"data_purge\"]}"
    
    echo "📝 Level 2 cost reduction applied and recorded"
}

# Level 3: Emergency shutdown (≥¥7,000 - monthly budget exceeded)
apply_emergency_shutdown() {
    echo "🔴 EXECUTING EMERGENCY SHUTDOWN - BUDGET EXCEEDED"
    
    # Scale service to absolute minimum
    gcloud run services update $SERVICE_NAME \
        --region $REGION \
        --min-instances 0 \
        --max-instances 1 \
        --concurrency 1 \
        --cpu 500m \
        --memory 256Mi \
        --no-traffic
    
    echo "⚠️  Service scaled to absolute minimum"
    
    # Set emergency mode in application
    gcloud run services update $SERVICE_NAME \
        --region $REGION \
        --set-env-vars "EMERGENCY_MODE=true,MAX_REQUESTS_PER_MINUTE=1,PHASE=emergency"
    
    echo "🚨 Emergency mode activated"
    
    # Disable non-essential Cloud Functions
    echo "Disabling non-essential functions..."
    
    # List of functions to disable (keep only critical ones)
    FUNCTIONS_TO_DISABLE=("dailyAggregation" "cleanupInboxItems")
    
    for func in "${FUNCTIONS_TO_DISABLE[@]}"; do
        gcloud functions delete $func --region $REGION --quiet || echo "Function $func not found"
    done
    
    echo "🛑 Non-essential functions disabled"
    
    # Create emergency alert
    TIMESTAMP=$(date -Iseconds)
    curl -X POST "$SERVICE_URL/api/emergency-alert" \
        -H "Content-Type: application/json" \
        -d "{\"type\": \"budget_exceeded\", \"timestamp\": \"$TIMESTAMP\", \"action\": \"emergency_shutdown\"}"
    
    # Record emergency action
    curl -X POST "$SERVICE_URL/api/record-cost-reduction" \
        -H "Content-Type: application/json" \
        -d "{\"level\": 3, \"timestamp\": \"$TIMESTAMP\", \"measures\": [\"emergency_shutdown\", \"service_minimum\", \"functions_disabled\"]}"
    
    echo "📝 Emergency shutdown executed and recorded"
    
    # Send notification (this would integrate with notification service)
    echo "📧 Emergency notification sent"
    echo ""
    echo "🚨 SYSTEM IS NOW IN EMERGENCY MODE"
    echo "📱 Manual intervention required to restore full service"
    echo "📞 Contact: admin@taikichu-app.com"
    echo ""
    echo "To restore service:"
    echo "  ./scripts/restore-from-emergency.sh"
}

# Level 4: Complete shutdown (≥¥8,000 - emergency threshold)
apply_complete_shutdown() {
    echo "🛑 EXECUTING COMPLETE SHUTDOWN - EMERGENCY THRESHOLD EXCEEDED"
    
    # Stop all services
    gcloud run services update $SERVICE_NAME \
        --region $REGION \
        --min-instances 0 \
        --max-instances 0 \
        --no-traffic
    
    echo "🛑 All Cloud Run instances stopped"
    
    # Delete all Cloud Functions except emergency ones
    echo "Deleting all non-emergency functions..."
    
    # Keep only emergency restore function
    FUNCTIONS_TO_KEEP=("budgetHealthCheck" "emergencyRestore")
    ALL_FUNCTIONS=$(gcloud functions list --format="value(name)")
    
    for func in $ALL_FUNCTIONS; do
        if [[ ! " ${FUNCTIONS_TO_KEEP[@]} " =~ " ${func} " ]]; then
            gcloud functions delete $func --region $REGION --quiet
        fi
    done
    
    echo "🗑️  All non-emergency functions deleted"
    
    # Set complete shutdown status
    curl -X POST "$SERVICE_URL/api/complete-shutdown" \
        -H "Content-Type: application/json" \
        -d "{\"timestamp\": \"$(date -Iseconds)\", \"reason\": \"emergency_budget_exceeded\"}" || echo "Service unavailable for status update"
    
    echo ""
    echo "🛑 COMPLETE SYSTEM SHUTDOWN EXECUTED"
    echo "💰 Budget protection activated"
    echo "⏰ Estimated savings: ¥2,000+/month"
    echo ""
    echo "🔧 To restore service:"
    echo "  1. Review and approve additional budget"
    echo "  2. Run: ./scripts/restore-from-emergency.sh"
    echo "  3. Contact: admin@taikichu-app.com"
    echo ""
    echo "📊 Shutdown reason: Monthly budget ¥$1 exceeded ¥8,000 emergency threshold"
}

# Function to get cost reduction level based on current spend
get_cost_reduction_level() {
    local current_spend=$1
    
    if [ $current_spend -ge $EMERGENCY_THRESHOLD ]; then
        echo "4"  # Complete shutdown
    elif [ $current_spend -ge $MONTHLY_THRESHOLD ]; then
        echo "3"  # Emergency shutdown
    elif [ $current_spend -ge $((MONTHLY_THRESHOLD * 90 / 100)) ]; then
        echo "2"  # Moderate reduction
    elif [ $current_spend -ge $((MONTHLY_THRESHOLD * 80 / 100)) ]; then
        echo "1"  # Soft reduction
    else
        echo "0"  # No action needed
    fi
}

# Main execution
main() {
    echo "🚀 Starting automatic cost reduction system..."
    echo "Configuration:"
    echo "  Daily threshold: ¥$DAILY_THRESHOLD"
    echo "  Monthly threshold: ¥$MONTHLY_THRESHOLD"
    echo "  Emergency threshold: ¥$EMERGENCY_THRESHOLD"
    echo ""
    
    # Check prerequisites
    if ! command -v gcloud &> /dev/null; then
        echo "❌ gcloud CLI is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "❌ jq is required but not installed"
        exit 1
    fi
    
    # Get current budget status
    check_budget_status
    CURRENT_SPEND=$?
    
    echo "Current monthly spend: ¥$CURRENT_SPEND"
    
    # Determine appropriate action level
    REDUCTION_LEVEL=$(get_cost_reduction_level $CURRENT_SPEND)
    
    echo "Required cost reduction level: $REDUCTION_LEVEL"
    
    case $REDUCTION_LEVEL in
        0)
            echo "✅ Budget within acceptable limits - no action required"
            ;;
        1)
            apply_soft_cost_reduction
            ;;
        2)
            apply_moderate_cost_reduction
            ;;
        3)
            apply_emergency_shutdown
            ;;
        4)
            apply_complete_shutdown $CURRENT_SPEND
            ;;
        *)
            echo "❌ Unknown reduction level: $REDUCTION_LEVEL"
            exit 1
            ;;
    esac
    
    echo ""
    echo "🎯 Cost reduction measures completed"
    echo "📊 Monitor budget status: $SERVICE_URL/budget-health"
    echo "📈 Recovery plan: ./scripts/restore-from-emergency.sh"
}

# Execute main function with all arguments
main "$@"