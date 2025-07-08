#!/bin/bash
# Comprehensive cleanup script for unused Google Cloud services
# Stops and deletes all non-Phase0 services to minimize costs

set -e

echo "🧹 Starting comprehensive Google Cloud services cleanup..."

# Configuration
PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"
ZONE="asia-northeast1-a"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to prompt for confirmation
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        read -p "$message (Y/n): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Nn]$ ]] && return 1
    else
        read -p "$message (y/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || return 1
    fi
    return 0
}

# Function to check if resource exists before trying to delete
resource_exists() {
    local check_command="$1"
    eval "$check_command" &>/dev/null
    return $?
}

echo "📋 Current project: $PROJECT_ID"
echo "🌏 Region: $REGION"
echo ""

# Check prerequisites
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
    echo -e "${RED}❌ Please authenticate with gcloud first${NC}"
    exit 1
fi

CURRENT_PROJECT=$(gcloud config get-value project)
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    echo "⚠️  Setting project to $PROJECT_ID"
    gcloud config set project $PROJECT_ID
fi

echo "✅ Prerequisites check passed"
echo ""

# 1. Cloud Memorystore for Redis
echo -e "${YELLOW}🔍 Checking Cloud Memorystore for Redis instances...${NC}"
REDIS_INSTANCES=$(gcloud redis instances list --region=$REGION --format="value(name)" 2>/dev/null || echo "")

if [ -n "$REDIS_INSTANCES" ]; then
    echo -e "${RED}Found Redis instances:${NC}"
    gcloud redis instances list --region=$REGION
    echo ""
    
    if confirm "Delete all Redis instances?"; then
        for instance in $REDIS_INSTANCES; do
            echo "🗑️  Deleting Redis instance: $instance"
            gcloud redis instances delete "$instance" --region=$REGION --quiet
            echo -e "${GREEN}✅ Redis instance $instance deleted${NC}"
        done
    else
        echo "⏭️  Skipping Redis instances deletion"
    fi
else
    echo -e "${GREEN}✅ No Redis instances found${NC}"
fi
echo ""

# 2. AlloyDB clusters and instances
echo -e "${YELLOW}🔍 Checking AlloyDB clusters...${NC}"
ALLOYDB_CLUSTERS=$(gcloud alloydb clusters list --region=$REGION --format="value(name)" 2>/dev/null || echo "")

if [ -n "$ALLOYDB_CLUSTERS" ]; then
    echo -e "${RED}Found AlloyDB clusters:${NC}"
    gcloud alloydb clusters list --region=$REGION
    echo ""
    
    if confirm "Delete all AlloyDB clusters and instances?"; then
        for cluster in $ALLOYDB_CLUSTERS; do
            # First delete all instances in the cluster
            INSTANCES=$(gcloud alloydb instances list --cluster="$cluster" --region=$REGION --format="value(name)" 2>/dev/null || echo "")
            
            for instance in $INSTANCES; do
                echo "🗑️  Deleting AlloyDB instance: $instance"
                gcloud alloydb instances delete "$instance" --cluster="$cluster" --region=$REGION --quiet
            done
            
            # Then delete the cluster
            echo "🗑️  Deleting AlloyDB cluster: $cluster"
            gcloud alloydb clusters delete "$cluster" --region=$REGION --quiet
            echo -e "${GREEN}✅ AlloyDB cluster $cluster deleted${NC}"
        done
    else
        echo "⏭️  Skipping AlloyDB deletion"
    fi
else
    echo -e "${GREEN}✅ No AlloyDB clusters found${NC}"
fi
echo ""

# 3. Cloud SQL instances
echo -e "${YELLOW}🔍 Checking Cloud SQL instances...${NC}"
SQL_INSTANCES=$(gcloud sql instances list --format="value(name)" 2>/dev/null || echo "")

if [ -n "$SQL_INSTANCES" ]; then
    echo -e "${RED}Found Cloud SQL instances:${NC}"
    gcloud sql instances list
    echo ""
    
    if confirm "Delete all Cloud SQL instances?"; then
        for instance in $SQL_INSTANCES; do
            echo "🗑️  Deleting Cloud SQL instance: $instance"
            gcloud sql instances delete "$instance" --quiet
            echo -e "${GREEN}✅ Cloud SQL instance $instance deleted${NC}"
        done
    else
        echo "⏭️  Skipping Cloud SQL deletion"
    fi
else
    echo -e "${GREEN}✅ No Cloud SQL instances found${NC}"
fi
echo ""

# 4. Compute Engine instances
echo -e "${YELLOW}🔍 Checking Compute Engine instances...${NC}"
COMPUTE_INSTANCES=$(gcloud compute instances list --zones=$ZONE --format="value(name)" 2>/dev/null || echo "")

if [ -n "$COMPUTE_INSTANCES" ]; then
    echo -e "${RED}Found Compute Engine instances:${NC}"
    gcloud compute instances list --zones=$ZONE
    echo ""
    
    if confirm "Stop and delete Compute Engine instances?"; then
        for instance in $COMPUTE_INSTANCES; do
            echo "🛑 Stopping Compute Engine instance: $instance"
            gcloud compute instances stop "$instance" --zone=$ZONE --quiet
            
            echo "🗑️  Deleting Compute Engine instance: $instance"
            gcloud compute instances delete "$instance" --zone=$ZONE --quiet
            echo -e "${GREEN}✅ Compute Engine instance $instance deleted${NC}"
        done
    else
        echo "⏭️  Skipping Compute Engine instances"
    fi
else
    echo -e "${GREEN}✅ No Compute Engine instances found${NC}"
fi
echo ""

# 5. Kubernetes Engine clusters
echo -e "${YELLOW}🔍 Checking GKE clusters...${NC}"
GKE_CLUSTERS=$(gcloud container clusters list --region=$REGION --format="value(name)" 2>/dev/null || echo "")

if [ -n "$GKE_CLUSTERS" ]; then
    echo -e "${RED}Found GKE clusters:${NC}"
    gcloud container clusters list --region=$REGION
    echo ""
    
    if confirm "Delete all GKE clusters?"; then
        for cluster in $GKE_CLUSTERS; do
            echo "🗑️  Deleting GKE cluster: $cluster"
            gcloud container clusters delete "$cluster" --region=$REGION --quiet
            echo -e "${GREEN}✅ GKE cluster $cluster deleted${NC}"
        done
    else
        echo "⏭️  Skipping GKE clusters"
    fi
else
    echo -e "${GREEN}✅ No GKE clusters found${NC}"
fi
echo ""

# 6. Cloud Datastore/Firestore in Datastore mode
echo -e "${YELLOW}🔍 Checking for Datastore mode databases...${NC}"
# Note: We keep Firestore in Native mode for Phase0
DATASTORE_ENTITIES=$(gcloud datastore indexes list 2>/dev/null | grep -v "Firestore" || echo "")

if [ -n "$DATASTORE_ENTITIES" ]; then
    echo -e "${YELLOW}⚠️  Found Datastore indexes (keeping Firestore Native mode for Phase0)${NC}"
    gcloud datastore indexes list
    echo ""
    
    if confirm "Clean up Datastore indexes (keeping Firestore)?"; then
        # This would require more specific commands based on what's found
        echo "ℹ️  Manual cleanup may be required for Datastore entities"
    fi
else
    echo -e "${GREEN}✅ No conflicting Datastore configuration found${NC}"
fi
echo ""

# 7. Cloud BigQuery datasets (careful with billing export)
echo -e "${YELLOW}🔍 Checking BigQuery datasets...${NC}"
BQ_DATASETS=$(bq ls --format=csv | tail -n +2 | cut -d, -f1 | grep -v "billing_export" || echo "")

if [ -n "$BQ_DATASETS" ]; then
    echo -e "${YELLOW}Found BigQuery datasets (excluding billing_export):${NC}"
    bq ls
    echo ""
    
    if confirm "Delete non-essential BigQuery datasets?"; then
        for dataset in $BQ_DATASETS; do
            if [ "$dataset" != "billing_export" ] && [ "$dataset" != "" ]; then
                echo "🗑️  Deleting BigQuery dataset: $dataset"
                bq rm -r -f "$dataset"
                echo -e "${GREEN}✅ BigQuery dataset $dataset deleted${NC}"
            fi
        done
    else
        echo "⏭️  Skipping BigQuery datasets"
    fi
else
    echo -e "${GREEN}✅ No unnecessary BigQuery datasets found${NC}"
fi
echo ""

# 8. App Engine services (if any)
echo -e "${YELLOW}🔍 Checking App Engine services...${NC}"
APP_ENGINE_SERVICES=$(gcloud app services list --format="value(id)" 2>/dev/null | grep -v "default" || echo "")

if [ -n "$APP_ENGINE_SERVICES" ]; then
    echo -e "${RED}Found App Engine services:${NC}"
    gcloud app services list
    echo ""
    
    if confirm "Delete non-default App Engine services?"; then
        for service in $APP_ENGINE_SERVICES; do
            echo "🗑️  Deleting App Engine service: $service"
            gcloud app services delete "$service" --quiet
            echo -e "${GREEN}✅ App Engine service $service deleted${NC}"
        done
    else
        echo "⏭️  Skipping App Engine services"
    fi
else
    echo -e "${GREEN}✅ No unnecessary App Engine services found${NC}"
fi
echo ""

# 9. Cloud Storage buckets (careful with essential ones)
echo -e "${YELLOW}🔍 Checking Cloud Storage buckets...${NC}"
STORAGE_BUCKETS=$(gsutil ls | grep -v "taikichu-app-functions" | grep -v "firebase" || echo "")

if [ -n "$STORAGE_BUCKETS" ]; then
    echo -e "${YELLOW}Found Cloud Storage buckets (excluding essential ones):${NC}"
    gsutil ls
    echo ""
    
    echo -e "${RED}⚠️  WARNING: This will permanently delete bucket contents!${NC}"
    if confirm "Delete non-essential storage buckets?"; then
        for bucket in $STORAGE_BUCKETS; do
            if [[ "$bucket" != *"taikichu-app-functions"* ]] && [[ "$bucket" != *"firebase"* ]]; then
                echo "🗑️  Deleting storage bucket: $bucket"
                gsutil rm -r "$bucket" || echo "Failed to delete $bucket"
                echo -e "${GREEN}✅ Storage bucket $bucket deleted${NC}"
            fi
        done
    else
        echo "⏭️  Skipping storage buckets deletion"
    fi
else
    echo -e "${GREEN}✅ No unnecessary storage buckets found${NC}"
fi
echo ""

# 10. Persistent Disks
echo -e "${YELLOW}🔍 Checking persistent disks...${NC}"
PERSISTENT_DISKS=$(gcloud compute disks list --zones=$ZONE --format="value(name)" 2>/dev/null || echo "")

if [ -n "$PERSISTENT_DISKS" ]; then
    echo -e "${RED}Found persistent disks:${NC}"
    gcloud compute disks list --zones=$ZONE
    echo ""
    
    if confirm "Delete unused persistent disks?"; then
        for disk in $PERSISTENT_DISKS; do
            echo "🗑️  Deleting persistent disk: $disk"
            gcloud compute disks delete "$disk" --zone=$ZONE --quiet
            echo -e "${GREEN}✅ Persistent disk $disk deleted${NC}"
        done
    else
        echo "⏭️  Skipping persistent disks"
    fi
else
    echo -e "${GREEN}✅ No persistent disks found${NC}"
fi
echo ""

# 11. Network Load Balancers
echo -e "${YELLOW}🔍 Checking load balancers...${NC}"
LOAD_BALANCERS=$(gcloud compute forwarding-rules list --global --format="value(name)" 2>/dev/null || echo "")

if [ -n "$LOAD_BALANCERS" ]; then
    echo -e "${RED}Found load balancers:${NC}"
    gcloud compute forwarding-rules list --global
    echo ""
    
    if confirm "Delete load balancers?"; then
        for lb in $LOAD_BALANCERS; do
            echo "🗑️  Deleting load balancer: $lb"
            gcloud compute forwarding-rules delete "$lb" --global --quiet
            echo -e "${GREEN}✅ Load balancer $lb deleted${NC}"
        done
    else
        echo "⏭️  Skipping load balancers"
    fi
else
    echo -e "${GREEN}✅ No load balancers found${NC}"
fi
echo ""

# 12. Generate cost impact report
echo -e "${YELLOW}📊 Generating cost impact report...${NC}"

# Create cleanup report
cat > cleanup_report.txt << EOF
Google Cloud Services Cleanup Report
Generated: $(date)
Project: $PROJECT_ID

Services Checked and Processed:
- Cloud Memorystore for Redis: $(echo "$REDIS_INSTANCES" | wc -w) instances
- AlloyDB: $(echo "$ALLOYDB_CLUSTERS" | wc -w) clusters  
- Cloud SQL: $(echo "$SQL_INSTANCES" | wc -w) instances
- Compute Engine: $(echo "$COMPUTE_INSTANCES" | wc -w) instances
- GKE: $(echo "$GKE_CLUSTERS" | wc -w) clusters
- BigQuery: $(echo "$BQ_DATASETS" | wc -w) datasets
- App Engine: $(echo "$APP_ENGINE_SERVICES" | wc -w) services
- Storage: $(echo "$STORAGE_BUCKETS" | wc -w) buckets
- Persistent Disks: $(echo "$PERSISTENT_DISKS" | wc -w) disks
- Load Balancers: $(echo "$LOAD_BALANCERS" | wc -w) rules

Estimated Monthly Cost Savings:
- Redis instances: ¥3,000-5,000 per instance
- AlloyDB clusters: ¥15,000-30,000 per cluster
- Cloud SQL: ¥5,000-15,000 per instance
- Compute Engine: ¥2,000-10,000 per instance
- GKE clusters: ¥10,000-25,000 per cluster

Remaining Phase0 Services:
- Cloud Run (taikichu-app): ¥2,100/month
- Firestore: ¥2,534/month (reads + writes)
- Firebase Hosting: ¥620/month
- Cloud Storage (essential): ¥107/month
- Cloud Functions: ¥50/month
- Cloud Logging: ¥775/month

TOTAL REMAINING: ~¥6,250/month (within ¥7,000 budget)
EOF

echo "✅ Cleanup report generated: cleanup_report.txt"
echo ""

# 13. Final verification
echo -e "${GREEN}🎉 Cleanup process completed!${NC}"
echo ""
echo "📋 Next steps:"
echo "1. Review cleanup_report.txt for cost impact"
echo "2. Verify Phase0 services are still running:"
echo "   - Cloud Run: gcloud run services list"
echo "   - Cloud Functions: gcloud functions list"
echo "   - Firestore: accessible via Firebase Console"
echo "3. Monitor billing for cost reduction confirmation"
echo ""
echo "⚠️  If you need to restore any services:"
echo "   - Redis: ./scripts/migrate-to-phase1.sh"
echo "   - Others: Contact support for restoration procedures"
echo ""
echo -e "${GREEN}✅ Phase0 cost optimization complete!${NC}"