# Taikichu App Phase0 - Infrastructure as Code

Complete Infrastructure as Code (IaC) setup for Taikichu App Phase0 using Terraform.

## 🎯 One-Command Deployment

Deploy the entire Phase0 infrastructure with a single command:

```bash
./scripts/terraform-deploy.sh -b YOUR_BILLING_ACCOUNT_ID -e your@email.com
```

## 📋 Prerequisites

### Required Tools
- **Terraform** >= 1.5 ([Install](https://learn.hashicorp.com/tutorials/terraform/install-cli))
- **Google Cloud SDK** ([Install](https://cloud.google.com/sdk/docs/install))
- **Firebase CLI** ([Install](https://firebase.google.com/docs/cli))
- **Flutter** >= 3.8.1 ([Install](https://docs.flutter.dev/get-started/install))

### Required Permissions
- Google Cloud Project Owner or Editor
- Billing Account User
- Firebase Admin

### Setup Authentication
```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set default project
gcloud config set project taikichu-app-c8dcd

# Authenticate with Firebase
firebase login
```

## 🏗️ Infrastructure Components

### Core Services
- **Firebase Project** with Firestore database
- **Cloud Run** service for main application
- **Firebase Authentication** with email/password
- **Cloud Storage** buckets for uploads and functions
- **Firebase Hosting** for admin interface

### Security & IAM
- Service accounts with minimal required permissions
- Secret Manager for secure credential storage
- Firestore security rules (deployed separately)
- HTTPS enforcement and security headers

### Monitoring & Cost Control
- **Budget Alerts**: ¥450/day, ¥7,000/month, ¥8,000/month emergency
- **Performance Monitoring**: Latency, error rate, resource usage
- **Firestore Usage Tracking**: Read/write limits and alerts
- **Custom Dashboard** for Phase0 metrics

## 🚀 Quick Start

### 1. Get Your Billing Account ID

Visit [Google Cloud Billing](https://console.cloud.google.com/billing) and copy your billing account ID (format: `XXXXXX-XXXXXX-XXXXXX`).

### 2. Deploy Infrastructure

```bash
# Clone the repository
git clone <repository-url>
cd taikichu_app

# Run the deployment script
./scripts/terraform-deploy.sh -b YOUR_BILLING_ACCOUNT_ID -e your@email.com
```

### 3. Post-Deployment Steps

After Terraform completes, run these commands:

```bash
# 1. Build and deploy the application
gcloud builds submit --tag gcr.io/taikichu-app-c8dcd/taikichu-app:latest
gcloud run deploy taikichu-app --image gcr.io/taikichu-app-c8dcd/taikichu-app:latest --region asia-northeast1

# 2. Deploy Firestore security rules
firebase deploy --only firestore:rules

# 3. Deploy Firebase Functions
cd functions
npm install
firebase deploy --only functions

# 4. Deploy admin interface
cd ../admin_interface
flutter build web --release
firebase deploy --only hosting
```

## 📖 Detailed Usage

### Deployment Script Options

```bash
./scripts/terraform-deploy.sh [OPTIONS]

OPTIONS:
    -p, --project-id ID         GCP Project ID (default: taikichu-app-c8dcd)
    -r, --region REGION         GCP Region (default: asia-northeast1)
    -b, --billing-account ID    Billing Account ID (required)
    -e, --email EMAIL           Admin email for notifications (required)
    -y, --yes                   Skip confirmation prompts
    --plan-only                 Run terraform plan only (no apply)
    --destroy                   Destroy infrastructure (use with caution)
    -h, --help                  Show help message
```

### Examples

```bash
# Standard deployment
./scripts/terraform-deploy.sh -b 123456-789012-345678 -e admin@example.com

# Plan only (preview changes)
./scripts/terraform-deploy.sh -b 123456-789012-345678 -e admin@example.com --plan-only

# Auto-approve deployment
./scripts/terraform-deploy.sh -b 123456-789012-345678 -e admin@example.com -y

# Destroy infrastructure
./scripts/terraform-deploy.sh --destroy -y
```

### Manual Terraform Commands

If you prefer to run Terraform commands manually:

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan deployment
terraform plan \
  -var="billing_account_id=YOUR_BILLING_ACCOUNT_ID" \
  -var="admin_email=your@email.com" \
  -out=phase0.tfplan

# Apply deployment
terraform apply phase0.tfplan

# Destroy infrastructure
terraform destroy \
  -var="billing_account_id=YOUR_BILLING_ACCOUNT_ID" \
  -var="admin_email=your@email.com"
```

## 📊 Monitoring & Alerts

### Budget Configuration
- **Daily Budget**: ¥450/day with early warning alerts
- **Monthly Budget**: ¥7,000/month with 50%, 80%, 90%, 100% thresholds
- **Emergency Shutdown**: ¥8,000/month automatic triggers

### Performance Alerts
- **Latency**: P95 > 600ms
- **Error Rate**: > 5%
- **Firestore Reads**: > 32M/day (80% of limit)
- **Storage Usage**: > 25GB

### Dashboard Access
- **Monitoring Dashboard**: [Google Cloud Console](https://console.cloud.google.com/monitoring)
- **Firebase Console**: [Firebase Project](https://console.firebase.google.com/project/taikichu-app-c8dcd)
- **Budget Alerts**: [Cloud Billing](https://console.cloud.google.com/billing)

## 🔧 Configuration

### Environment Variables

Key configuration options in `terraform/variables.tf`:

```hcl
# Phase0 Configuration
phase0_config = {
  daily_budget_jpy         = 450    # ¥450/day
  monthly_budget_jpy       = 7000   # ¥7,000/month
  emergency_budget_jpy     = 8000   # ¥8,000/month
  cloud_run_min_instances  = 1      # No cold starts
  cloud_run_max_instances  = 10     # Scale limit
  cloud_run_cpu_limit      = "1000m" # 1 vCPU
  cloud_run_memory_limit   = "512Mi" # 512 MiB
  firestore_daily_read_limit = 40000000 # 40M reads/day
}
```

### Optional Features

```hcl
optional_features = {
  enable_cdn               = false  # Phase0: Keep simple
  enable_load_balancer     = false  # Phase0: Direct Cloud Run
  enable_custom_domain     = false  # Phase0: Use .run.app
  enable_audit_logging     = true   # Always enabled
  enable_backup_retention  = true   # Always enabled
}
```

## 🛡️ Security

### Service Accounts
- **firebase-admin**: Firebase Admin SDK operations
- **cloud-run-service**: Cloud Run application runtime
- **budget-manager**: Budget monitoring and alerts

### Secret Management
- Firebase Admin SDK key stored in Secret Manager
- Automatic rotation and secure access patterns
- No hardcoded credentials in code or configuration

### Network Security
- HTTPS enforced for all communications
- Security headers enabled
- CORS configured for Phase0 requirements

## 🔍 Troubleshooting

### Common Issues

**1. Authentication Errors**
```bash
# Re-authenticate
gcloud auth login
gcloud auth application-default login
firebase login
```

**2. Permission Errors**
```bash
# Check permissions
gcloud projects get-iam-policy taikichu-app-c8dcd
gcloud billing accounts get-iam-policy YOUR_BILLING_ACCOUNT_ID
```

**3. Terraform State Issues**
```bash
# Reset Terraform state (use with caution)
cd terraform
rm -rf .terraform terraform.tfstate*
terraform init
```

**4. Billing Account Not Found**
```bash
# List available billing accounts
gcloud billing accounts list
```

### Getting Help

1. **Terraform Documentation**: [terraform.io](https://www.terraform.io/docs)
2. **Google Cloud Documentation**: [cloud.google.com/docs](https://cloud.google.com/docs)
3. **Firebase Documentation**: [firebase.google.com/docs](https://firebase.google.com/docs)

### Support Contacts

- **Technical Issues**: Check the repository issues
- **Infrastructure Questions**: Review this documentation
- **Emergency**: Use the emergency shutdown script in `/scripts/`

## 📈 Scaling to Phase1

When ready to scale beyond Phase0 limits:

1. **Triggers for Migration**:
   - DAU > 8,000 users
   - Firestore reads > 35M/day for 3 consecutive days
   - P95 latency > 780ms for 1 week
   - Monthly costs approaching ¥8,000

2. **Migration Path**:
   ```bash
   # Prepare for Phase1
   ./scripts/migrate-to-phase1.sh
   ```

3. **Phase1 Features**:
   - Redis caching layer
   - Load balancer with CDN
   - Auto-scaling microservices
   - Advanced monitoring

## 📝 License

This Infrastructure as Code configuration is part of the Taikichu App project.

---

**🎉 Ready to deploy? Run the deployment script and get your Phase0 infrastructure up in minutes!**