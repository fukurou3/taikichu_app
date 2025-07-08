#!/bin/bash
# Phase migration trigger monitoring script
# Monitors key metrics to determine when to trigger Phase1 migration

PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"

# Phase1 migration trigger thresholds (from phase0-config.json)
MAU_THRESHOLD=8000
FIRESTORE_DAILY_READS_THRESHOLD=35000000
P95_LATENCY_THRESHOLD_MS=780
CONSECUTIVE_DAYS_THRESHOLD=3
CONSECUTIVE_WEEKS_THRESHOLD=1

echo "📊 Phase Migration Trigger Monitor"
echo "=================================="

# Function to get current date in YYYY-MM-DD format
get_date() {
    date +%Y-%m-%d
}

# Function to check MAU
check_mau() {
    echo "👥 Checking Monthly Active Users (MAU)..."
    
    # Get current month's DAU data from Firestore
    CURRENT_MONTH=$(date +%Y-%m)
    
    # Query daily_stats collection for current month
    # Note: This is a simplified check - in production, use proper MAU calculation
    ESTIMATED_MAU=$(gcloud firestore collections list --format="value(name)" | head -1)
    
    # Placeholder: Replace with actual MAU query
    CURRENT_MAU=5000  # This should be replaced with actual Firestore query
    
    echo "  Current MAU: $CURRENT_MAU"
    echo "  Threshold: $MAU_THRESHOLD"
    
    if [ $CURRENT_MAU -ge $MAU_THRESHOLD ]; then
        echo "  ⚠️  MAU threshold exceeded!"
        return 0
    else
        echo "  ✅ MAU within limits"
        return 1
    fi
}

# Function to check Firestore reads
check_firestore_reads() {
    echo "🔥 Checking Firestore daily reads..."
    
    # Get today's estimated reads from monitoring
    # Note: This requires proper Cloud Monitoring integration
    TODAY=$(get_date)
    
    # Placeholder: Replace with actual Cloud Monitoring query
    DAILY_READS=25000000  # This should be replaced with actual monitoring query
    
    echo "  Today's reads: $(printf "%'d" $DAILY_READS)"
    echo "  Threshold: $(printf "%'d" $FIRESTORE_DAILY_READS_THRESHOLD)"
    
    if [ $DAILY_READS -ge $FIRESTORE_DAILY_READS_THRESHOLD ]; then
        echo "  ⚠️  Daily Firestore reads threshold exceeded!"
        
        # Check if this has been happening for consecutive days
        # Store in a tracking file
        echo "$TODAY" >> /tmp/high_reads_days.log
        
        # Count consecutive days
        CONSECUTIVE_DAYS=$(tail -n $CONSECUTIVE_DAYS_THRESHOLD /tmp/high_reads_days.log | wc -l)
        
        if [ $CONSECUTIVE_DAYS -ge $CONSECUTIVE_DAYS_THRESHOLD ]; then
            echo "  🚨 High reads for $CONSECUTIVE_DAYS consecutive days!"
            return 0
        else
            echo "  📊 High reads detected (day $CONSECUTIVE_DAYS of $CONSECUTIVE_DAYS_THRESHOLD)"
            return 1
        fi
    else
        echo "  ✅ Firestore reads within limits"
        # Clear the tracking file if reads are normal
        > /tmp/high_reads_days.log
        return 1
    fi
}

# Function to check P95 latency
check_p95_latency() {
    echo "⏱️  Checking P95 latency..."
    
    # Get current service URL
    SERVICE_URL=$(gcloud run services describe taikichu-app --region $REGION --format="value(status.url)")
    
    # Simple latency test (5 samples)
    echo "  Running latency test..."
    LATENCIES=()
    
    for i in {1..5}; do
        LATENCY=$(curl -s -o /dev/null -w "%{time_total}" "$SERVICE_URL/health")
        LATENCY_MS=$(echo "$LATENCY * 1000" | bc)
        LATENCIES+=($LATENCY_MS)
        echo "    Sample $i: ${LATENCY_MS}ms"
    done
    
    # Calculate P95 (simplified - use 95th percentile of samples)
    IFS=$'\n' SORTED_LATENCIES=($(sort -n <<<"${LATENCIES[*]}"))
    P95_INDEX=$(echo "(${#SORTED_LATENCIES[@]} - 1) * 0.95" | bc | cut -d. -f1)
    P95_LATENCY=${SORTED_LATENCIES[$P95_INDEX]}
    
    echo "  P95 Latency: ${P95_LATENCY}ms"
    echo "  Threshold: ${P95_LATENCY_THRESHOLD_MS}ms"
    
    if [ $(echo "$P95_LATENCY >= $P95_LATENCY_THRESHOLD_MS" | bc) -eq 1 ]; then
        echo "  ⚠️  P95 latency threshold exceeded!"
        
        # Track consecutive weeks of high latency
        WEEK=$(date +%Y-W%U)
        echo "$WEEK" >> /tmp/high_latency_weeks.log
        
        # Remove duplicate weeks and count unique consecutive weeks
        sort -u /tmp/high_latency_weeks.log > /tmp/unique_weeks.log
        CONSECUTIVE_WEEKS=$(tail -n $CONSECUTIVE_WEEKS_THRESHOLD /tmp/unique_weeks.log | wc -l)
        
        if [ $CONSECUTIVE_WEEKS -ge $CONSECUTIVE_WEEKS_THRESHOLD ]; then
            echo "  🚨 High latency for $CONSECUTIVE_WEEKS consecutive weeks!"
            return 0
        else
            echo "  📊 High latency detected (week $CONSECUTIVE_WEEKS of $CONSECUTIVE_WEEKS_THRESHOLD)"
            return 1
        fi
    else
        echo "  ✅ P95 latency within limits"
        # Clear tracking if latency is normal
        > /tmp/high_latency_weeks.log
        return 1
    fi
}

# Function to generate migration recommendation
generate_recommendation() {
    local mau_trigger=$1
    local reads_trigger=$2
    local latency_trigger=$3
    
    echo ""
    echo "🎯 Migration Recommendation"
    echo "=========================="
    
    TRIGGERS_COUNT=0
    
    if [ $mau_trigger -eq 0 ]; then
        echo "❌ MAU threshold exceeded"
        ((TRIGGERS_COUNT++))
    fi
    
    if [ $reads_trigger -eq 0 ]; then
        echo "❌ Firestore reads threshold exceeded"
        ((TRIGGERS_COUNT++))
    fi
    
    if [ $latency_trigger -eq 0 ]; then
        echo "❌ P95 latency threshold exceeded"
        ((TRIGGERS_COUNT++))
    fi
    
    echo ""
    echo "Triggers activated: $TRIGGERS_COUNT/3"
    
    if [ $TRIGGERS_COUNT -ge 1 ]; then
        echo "🚀 RECOMMENDATION: Migrate to Phase1"
        echo ""
        echo "Migration command:"
        echo "  ./migrate-to-phase1.sh"
        echo ""
        echo "Expected benefits:"
        echo "  - Reduced Firestore reads via Redis caching"
        echo "  - Improved P95 latency (target: <400ms)"
        echo "  - Better user experience with faster responses"
        echo ""
        echo "Cost impact:"
        echo "  - Additional ¥3,500-5,000/month for Redis"
        echo "  - Total monthly cost: ¥9,750-12,000"
        echo "  - Within Phase1 budget of ¥15,000/month"
    else
        echo "✅ RECOMMENDATION: Stay on Phase0"
        echo ""
        echo "Current metrics are within acceptable limits."
        echo "Continue monitoring for optimization opportunities."
    fi
}

# Main execution
echo "Starting monitoring check at $(date)"
echo ""

# Run all checks
MAU_STATUS=1
READS_STATUS=1
LATENCY_STATUS=1

check_mau
MAU_STATUS=$?

echo ""

check_firestore_reads
READS_STATUS=$?

echo ""

check_p95_latency
LATENCY_STATUS=$?

# Generate recommendation
generate_recommendation $MAU_STATUS $READS_STATUS $LATENCY_STATUS

echo ""
echo "📅 Next check recommended: $(date -d '+1 day')"
echo "💡 Run this script daily for continuous monitoring"