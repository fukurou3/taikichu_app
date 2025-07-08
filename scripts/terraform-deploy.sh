#!/bin/bash

# Taikichu App Phase0 - Complete Terraform Deployment Script
# Single command deployment with comprehensive error handling

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Default values
PROJECT_ID="taikichu-app-c8dcd"
REGION="asia-northeast1"
BILLING_ACCOUNT_ID=""
ADMIN_EMAIL=""
SKIP_CONFIRMATION=false
PLAN_ONLY=false
DESTROY_MODE=false

# Help function
show_help() {
    cat << EOF
Taikichu App Phase0 - Terraform Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
    -p, --project-id ID         GCP Project ID (default: taikichu-app-c8dcd)
    -r, --region REGION         GCP Region (default: asia-northeast1)
    -b, --billing-account ID    Billing Account ID (required)
    -e, --email EMAIL           Admin email for notifications (required)
    -y, --yes                   Skip confirmation prompts
    --plan-only                 Run terraform plan only (no apply)
    --destroy                   Destroy infrastructure (use with caution)
    -h, --help                  Show this help message

EXAMPLES:
    # Standard deployment
    $0 -b 123456-789012-345678 -e admin@example.com

    # Plan only (no changes)
    $0 -b 123456-789012-345678 -e admin@example.com --plan-only

    # Auto-approve deployment
    $0 -b 123456-789012-345678 -e admin@example.com -y

    # Destroy infrastructure
    $0 --destroy -y

REQUIREMENTS:
    - gcloud CLI installed and authenticated
    - terraform >= 1.5 installed
    - Billing account with valid permissions
    - Project owner or editor permissions

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -b|--billing-account)
            BILLING_ACCOUNT_ID="$2"
            shift 2
            ;;
        -e|--email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --plan-only)
            PLAN_ONLY=true
            shift
            ;;
        --destroy)
            DESTROY_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation functions
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install terraform >= 1.5"
        exit 1
    fi
    
    # Check terraform version
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    log "Terraform version: $TERRAFORM_VERSION"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some features may be limited"
    fi
    
    success "Prerequisites check passed"
}

validate_inputs() {
    log "Validating inputs..."
    
    if [ "$DESTROY_MODE" = false ]; then
        # Validate required inputs for deployment
        if [ -z "$BILLING_ACCOUNT_ID" ]; then
            error "Billing account ID is required for deployment"
            echo "Find your billing account ID at: https://console.cloud.google.com/billing"
            exit 1
        fi
        
        if [ -z "$ADMIN_EMAIL" ]; then
            error "Admin email is required for notifications"
            exit 1
        fi
        
        # Validate email format
        if [[ ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            error "Invalid email format: $ADMIN_EMAIL"
            exit 1
        fi
        
        # Validate billing account format
        if [[ ! "$BILLING_ACCOUNT_ID" =~ ^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$ ]]; then
            error "Invalid billing account ID format. Expected: XXXXXX-XXXXXX-XXXXXX"
            exit 1
        fi
    fi
    
    # Validate project ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        error "Invalid project ID format: $PROJECT_ID"
        exit 1
    fi
    
    success "Input validation passed"
}

show_deployment_summary() {
    if [ "$DESTROY_MODE" = true ]; then
        echo -e "${RED}============================================${NC}"
        echo -e "${RED}         DESTRUCTION SUMMARY${NC}"
        echo -e "${RED}============================================${NC}"
        echo -e "Project ID: ${YELLOW}$PROJECT_ID${NC}"
        echo -e "Region: ${YELLOW}$REGION${NC}"
        echo -e "${RED}WARNING: This will DESTROY all infrastructure!${NC}"
    else
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}         DEPLOYMENT SUMMARY${NC}"
        echo -e "${GREEN}============================================${NC}"
        echo -e "Project ID: ${YELLOW}$PROJECT_ID${NC}"
        echo -e "Region: ${YELLOW}$REGION${NC}"
        echo -e "Billing Account: ${YELLOW}$BILLING_ACCOUNT_ID${NC}"
        echo -e "Admin Email: ${YELLOW}$ADMIN_EMAIL${NC}"
        echo -e "Plan Only: ${YELLOW}$PLAN_ONLY${NC}"
        echo ""
        echo -e "${BLUE}Resources to be created:${NC}"
        echo "  ✓ Firebase project with Firestore"
        echo "  ✓ Cloud Run service (Phase0 configuration)"
        echo "  ✓ Cloud Storage buckets"
        echo "  ✓ IAM service accounts and roles"
        echo "  ✓ Budget alerts and monitoring"
        echo "  ✓ Firebase Authentication"
        echo "  ✓ Secret Manager for secure key storage"
        echo ""
        echo -e "${BLUE}Budget Configuration:${NC}"
        echo "  ✓ Daily budget: ¥450/day alerts"
        echo "  ✓ Monthly budget: ¥7,000/month with thresholds"
        echo "  ✓ Emergency shutdown: ¥8,000/month"
    fi
    echo -e "${GREEN}============================================${NC}"
}

confirm_deployment() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    echo ""
    if [ "$DESTROY_MODE" = true ]; then
        read -p "Are you ABSOLUTELY SURE you want to DESTROY all infrastructure? Type 'destroy' to confirm: " confirm
        if [ "$confirm" != "destroy" ]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    else
        read -p "Do you want to proceed with this deployment? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
}

setup_terraform() {
    log "Setting up Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    log "Initializing Terraform..."
    terraform init
    
    # Validate Terraform configuration
    log "Validating Terraform configuration..."
    terraform validate
    
    success "Terraform setup completed"
}

run_terraform_plan() {
    log "Running Terraform plan..."
    
    cd "$TERRAFORM_DIR"
    
    if [ "$DESTROY_MODE" = true ]; then
        terraform plan -destroy \
            -var="project_id=$PROJECT_ID" \
            -var="region=$REGION" \
            -var="billing_account_id=${BILLING_ACCOUNT_ID:-dummy}" \
            -var="admin_email=${ADMIN_EMAIL:-dummy@example.com}" \
            -out=destroy.tfplan
    else
        terraform plan \
            -var="project_id=$PROJECT_ID" \
            -var="region=$REGION" \
            -var="billing_account_id=$BILLING_ACCOUNT_ID" \
            -var="admin_email=$ADMIN_EMAIL" \
            -out=phase0.tfplan
    fi
    
    success "Terraform plan completed"
}

run_terraform_apply() {
    if [ "$PLAN_ONLY" = true ]; then
        success "Plan-only mode completed. Review the plan above."
        return 0
    fi
    
    log "Applying Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    if [ "$DESTROY_MODE" = true ]; then
        terraform apply destroy.tfplan
    else
        terraform apply phase0.tfplan
    fi
    
    success "Terraform apply completed"
}

show_next_steps() {
    if [ "$DESTROY_MODE" = true ]; then
        success "Infrastructure destruction completed"
        return 0
    fi
    
    echo ""
    echo -e "${GREEN}🎉 TERRAFORM DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}"
    echo ""
    echo -e "${BLUE}📋 NEXT MANUAL STEPS:${NC}"
    echo ""
    echo "1. Build and deploy the application:"
    echo "   cd $PROJECT_ROOT"
    echo "   gcloud builds submit --tag gcr.io/$PROJECT_ID/taikichu-app:latest"
    echo ""
    echo "2. Deploy Firestore security rules:"
    echo "   firebase deploy --only firestore:rules"
    echo ""
    echo "3. Deploy Firebase Functions:"
    echo "   cd functions && npm install && firebase deploy --only functions"
    echo ""
    echo "4. Deploy admin interface:"
    echo "   cd admin_interface && flutter build web --release"
    echo "   firebase deploy --only hosting"
    echo ""
    echo -e "${BLUE}📊 MONITORING:${NC}"
    echo "   Dashboard: https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
    echo "   Alerts: Configured for email notifications to $ADMIN_EMAIL"
    echo ""
    echo -e "${BLUE}💰 BUDGET:${NC}"
    echo "   Daily alerts: ¥450/day"
    echo "   Monthly budget: ¥7,000/month"
    echo "   Emergency shutdown: ¥8,000/month"
    echo ""
    echo -e "${GREEN}✅ Phase0 infrastructure is ready for use!${NC}"
}

# Main execution
main() {
    log "Starting Taikichu App Phase0 Terraform Deployment"
    
    check_prerequisites
    validate_inputs
    show_deployment_summary
    confirm_deployment
    setup_terraform
    run_terraform_plan
    run_terraform_apply
    show_next_steps
    
    success "Deployment script completed successfully"
}

# Error handling
trap 'error "Deployment failed at line $LINENO"' ERR

# Run main function
main "$@"