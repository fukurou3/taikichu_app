# Terraform Variables for Taikichu App Phase0

variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
  default     = "taikichu-app-c8dcd"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for resources"
  type        = string
  default     = "asia-northeast1"
  
  validation {
    condition = contains([
      "asia-northeast1",
      "asia-northeast2", 
      "asia-southeast1",
      "us-central1",
      "us-east1",
      "europe-west1"
    ], var.region)
    error_message = "Region must be one of the supported regions for cost optimization."
  }
}

variable "billing_account_id" {
  description = "Google Cloud Billing Account ID (format: XXXXXX-XXXXXX-XXXXXX)"
  type        = string
  
  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account_id))
    error_message = "Billing account ID must be in format XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "admin_email" {
  description = "Administrator email for notifications and alerts"
  type        = string
  default     = "admin@taikichu-app.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

variable "environment" {
  description = "Environment name (phase0, phase1, production)"
  type        = string
  default     = "phase0"
  
  validation {
    condition     = contains(["phase0", "phase1", "development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: phase0, phase1, development, staging, production."
  }
}

# Phase0 specific configurations
variable "phase0_config" {
  description = "Phase0 specific configuration settings"
  type = object({
    daily_budget_jpy         = number
    monthly_budget_jpy       = number
    emergency_budget_jpy     = number
    cloud_run_min_instances  = number
    cloud_run_max_instances  = number
    cloud_run_cpu_limit      = string
    cloud_run_memory_limit   = string
    firestore_daily_read_limit = number
  })
  
  default = {
    daily_budget_jpy         = 450   # ¥450/day
    monthly_budget_jpy       = 7000  # ¥7,000/month
    emergency_budget_jpy     = 8000  # ¥8,000/month emergency shutdown
    cloud_run_min_instances  = 1     # No cold starts
    cloud_run_max_instances  = 10    # Scale limit
    cloud_run_cpu_limit      = "1000m" # 1 vCPU
    cloud_run_memory_limit   = "512Mi" # 512 MiB
    firestore_daily_read_limit = 40000000 # 40M reads/day
  }
}

# Optional features configuration
variable "optional_features" {
  description = "Optional features to enable/disable"
  type = object({
    enable_cdn                = bool
    enable_load_balancer     = bool
    enable_custom_domain     = bool
    enable_ssl_certificate   = bool
    enable_audit_logging     = bool
    enable_backup_retention  = bool
  })
  
  default = {
    enable_cdn                = false  # Phase0: Keep it simple
    enable_load_balancer     = false  # Phase0: Direct Cloud Run
    enable_custom_domain     = false  # Phase0: Use .run.app domain
    enable_ssl_certificate   = false  # Phase0: Cloud Run provides SSL
    enable_audit_logging     = true   # Always enabled for security
    enable_backup_retention  = true   # Always enabled for safety
  }
}

# Monitoring configuration
variable "monitoring_config" {
  description = "Monitoring and alerting configuration"
  type = object({
    email_notifications      = bool
    slack_webhook_url       = string
    alert_threshold_cpu     = number
    alert_threshold_memory  = number
    alert_threshold_latency = number
    alert_threshold_errors  = number
  })
  
  default = {
    email_notifications      = true
    slack_webhook_url       = ""      # Optional: Add Slack webhook for alerts
    alert_threshold_cpu     = 80      # 80% CPU usage alert
    alert_threshold_memory  = 85      # 85% memory usage alert
    alert_threshold_latency = 600     # 600ms P95 latency alert
    alert_threshold_errors  = 5       # 5% error rate alert
  }
}

# Security configuration
variable "security_config" {
  description = "Security configuration settings"
  type = object({
    require_https               = bool
    enable_security_headers     = bool
    cors_allowed_origins       = list(string)
    max_request_size_mb        = number
    rate_limit_requests_per_min = number
  })
  
  default = {
    require_https               = true
    enable_security_headers     = true
    cors_allowed_origins       = ["*"]  # Phase0: Allow all origins, restrict in Phase1
    max_request_size_mb        = 10     # 10MB max request size
    rate_limit_requests_per_min = 30    # 30 requests/min per IP
  }
}

# Local variables for computed values
locals {
  # Common labels for all resources
  common_labels = {
    environment   = var.environment
    phase        = "0"
    project      = "taikichu-app"
    managed_by   = "terraform"
    cost_center  = "phase0-budget"
  }
  
  # Resource naming convention
  resource_prefix = "${var.project_id}-${var.environment}"
  
  # Phase0 specific settings
  phase0_daily_budget_monthly = var.phase0_config.daily_budget_jpy * 30
  
  # Computed configuration
  cloud_run_config = {
    service_name = "taikichu-app"
    image_name   = "gcr.io/${var.project_id}/taikichu-app:latest"
    port         = 8080
  }
  
  # Storage bucket names (must be globally unique)
  storage_buckets = {
    functions_source = "${var.project_id}-functions-source"
    user_uploads    = "${var.project_id}-user-uploads"
    static_assets   = "${var.project_id}-static-assets"
    backups         = "${var.project_id}-backups"
  }
  
  # Firebase configuration
  firebase_config = {
    hosting_site_id = "${var.project_id}-admin"
    database_id     = "(default)"
  }
}

# Outputs for variables (useful for debugging)
output "configuration_summary" {
  description = "Summary of the configuration being deployed"
  value = {
    project_id     = var.project_id
    region         = var.region
    environment    = var.environment
    admin_email    = var.admin_email
    phase0_config  = var.phase0_config
    features       = var.optional_features
    monitoring     = var.monitoring_config
    security       = var.security_config
  }
}

output "computed_values" {
  description = "Computed values from variables"
  value = {
    resource_prefix              = local.resource_prefix
    phase0_daily_budget_monthly  = local.phase0_daily_budget_monthly
    storage_buckets             = local.storage_buckets
    firebase_config             = local.firebase_config
    cloud_run_config            = local.cloud_run_config
  }
}