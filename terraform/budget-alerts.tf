# Budget alerts and monitoring for Phase0 v2.1
# Sets up Cloud Billing budgets with ¥450/day and ¥7,000/month thresholds

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "taikichu-app-c8dcd"
}

variable "billing_account_id" {
  description = "Google Cloud Billing Account ID"
  type        = string
  # This needs to be set during deployment
}

# Pub/Sub topic for budget alerts
resource "google_pubsub_topic" "budget_alerts" {
  name = "budget-alerts"
  
  labels = {
    environment = "phase0"
    purpose     = "budget_monitoring"
  }
}

# IAM binding for Cloud Billing to publish to Pub/Sub
resource "google_pubsub_topic_iam_binding" "budget_alerts_publisher" {
  topic = google_pubsub_topic.budget_alerts.name
  role  = "roles/pubsub.publisher"
  
  members = [
    "serviceAccount:billing@taikichu-app-c8dcd.iam.gserviceaccount.com",
    "serviceAccount:cloud-billing@system.gserviceaccount.com"
  ]
}

# Monthly budget (¥7,000/month)
resource "google_billing_budget" "monthly_budget" {
  billing_account = var.billing_account_id
  display_name    = "Phase0 Monthly Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    # Filter to only include specific services for accuracy
    services = [
      "services/6F81-5844-456A",  # Compute Engine (Cloud Run)
      "services/95FF-2EF5-5EA1",  # Firebase
      "services/A1E8-BE35-7EBC",  # Cloud Storage
      "services/5490-E99B-7A80",  # Cloud Functions
      "services/4E70-C956-73AD"   # Cloud Logging
    ]
  }
  
  amount {
    specified_amount {
      currency_code = "JPY"
      units         = "7000"  # ¥7,000/month
    }
  }
  
  # Alert thresholds
  threshold_rules {
    threshold_percent = 0.5  # 50% (¥3,500)
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 0.8  # 80% (¥5,600)
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 0.9  # 90% (¥6,300)
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0  # 100% (¥7,000) - Emergency alert
    spend_basis      = "CURRENT_SPEND"
  }
  
  # Forecasted spend alerts
  threshold_rules {
    threshold_percent = 1.1  # 110% forecasted (¥7,700)
    spend_basis      = "FORECASTED_SPEND"
  }
  
  # Notification channels
  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.budget_alerts.id
    schema_version                   = "1.0"
    monitoring_notification_channels = []
    
    # Disable email notifications to avoid spam
    disable_default_iam_recipients = true
  }
}

# Daily budget monitoring (approximate ¥450/day = ¥13,500/month)
resource "google_billing_budget" "daily_budget_monitor" {
  billing_account = var.billing_account_id
  display_name    = "Phase0 Daily Budget Monitor"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    # Calendar period for daily monitoring
    calendar_period = "MONTH"
  }
  
  amount {
    specified_amount {
      currency_code = "JPY"
      units         = "13500"  # ¥450/day × 30 days
    }
  }
  
  # Daily threshold monitoring (more frequent alerts)
  threshold_rules {
    threshold_percent = 0.1   # ¥1,350 (3 days spending)
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 0.2   # ¥2,700 (6 days spending)
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 0.33  # ¥4,455 (10 days spending)
    spend_basis      = "CURRENT_SPEND"
  }
  
  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.budget_alerts.id
    schema_version                   = "1.0"
    disable_default_iam_recipients   = true
  }
}

# Emergency shutdown budget (¥8,000/month)
resource "google_billing_budget" "emergency_budget" {
  billing_account = var.billing_account_id
  display_name    = "Phase0 Emergency Shutdown Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }
  
  amount {
    specified_amount {
      currency_code = "JPY"
      units         = "8000"  # ¥8,000/month emergency threshold
    }
  }
  
  # Single threshold for emergency action
  threshold_rules {
    threshold_percent = 1.0  # 100% (¥8,000) - Trigger emergency shutdown
    spend_basis      = "CURRENT_SPEND"
  }
  
  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.budget_alerts.id
    schema_version                   = "1.0"
    disable_default_iam_recipients   = true
  }
}

# Cloud Function trigger for budget alerts
resource "google_cloudfunctions_function" "budget_alert_handler" {
  name        = "budget-alert-handler"
  description = "Handles budget alerts and triggers cost reduction measures"
  runtime     = "nodejs18"
  
  available_memory_mb   = 256
  source_archive_bucket = "taikichu-app-functions"
  source_archive_object = "functions.zip"
  entry_point          = "monitorDailyBudget"
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.budget_alerts.name
  }
  
  environment_variables = {
    PHASE = "0"
    DAILY_BUDGET_THRESHOLD = "450"
    MONTHLY_BUDGET_THRESHOLD = "7000"
    EMERGENCY_THRESHOLD = "8000"
  }
}

# Cloud Monitoring alert policy for Firestore reads
resource "google_monitoring_alert_policy" "firestore_reads_alert" {
  display_name = "Phase0 Firestore Reads Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Firestore reads approaching limit"
    
    condition_threshold {
      filter          = "resource.type=\"firestore_instance\" AND metric.type=\"firestore.googleapis.com/api/request_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 30000000  # 30M reads (75% of 40M limit)
      
      aggregations {
        alignment_period   = "3600s"  # 1 hour
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "604800s"  # 7 days
  }
}

# Service account for budget management
resource "google_service_account" "budget_manager" {
  account_id   = "budget-manager"
  display_name = "Phase0 Budget Manager"
  description  = "Service account for budget monitoring and cost control"
}

# IAM roles for budget manager
resource "google_project_iam_member" "budget_manager_roles" {
  for_each = toset([
    "roles/billing.viewer",
    "roles/monitoring.viewer",
    "roles/pubsub.publisher",
    "roles/cloudfunctions.invoker",
    "roles/run.admin"  # For emergency scaling actions
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.budget_manager.email}"
}

# Output budget information
output "budget_alert_topic" {
  description = "Pub/Sub topic for budget alerts"
  value       = google_pubsub_topic.budget_alerts.name
}

output "monthly_budget_id" {
  description = "Monthly budget ID"
  value       = google_billing_budget.monthly_budget.name
}

output "daily_budget_monitor_id" {
  description = "Daily budget monitor ID"
  value       = google_billing_budget.daily_budget_monitor.name
}

output "emergency_budget_id" {
  description = "Emergency budget ID"
  value       = google_billing_budget.emergency_budget.name
}

# Cost breakdown export to BigQuery (for detailed analysis)
resource "google_bigquery_dataset" "billing_export" {
  dataset_id                  = "billing_export"
  friendly_name               = "Phase0 Billing Export"
  description                 = "Detailed billing data for cost analysis"
  location                    = "asia-northeast1"
  default_table_expiration_ms = 7776000000  # 90 days

  labels = {
    environment = "phase0"
    purpose     = "cost_analysis"
  }
}

# Instructions for manual setup
output "setup_instructions" {
  description = "Manual setup instructions"
  value = <<-EOT
    
    MANUAL SETUP REQUIRED:
    
    1. Set billing account ID:
       terraform apply -var="billing_account_id=YOUR_BILLING_ACCOUNT_ID"
    
    2. Enable Billing Export to BigQuery:
       - Go to Cloud Console > Billing > Billing Export
       - Set dataset: ${google_bigquery_dataset.billing_export.dataset_id}
       - Enable detailed usage cost data
    
    3. Upload Cloud Functions code:
       - Create functions.zip with billing-monitor.ts
       - Upload to Cloud Storage bucket: taikichu-app-functions
    
    4. Verify Pub/Sub topic permissions:
       - Topic: ${google_pubsub_topic.budget_alerts.name}
       - Ensure Cloud Billing can publish to this topic
    
    Budget Thresholds Set:
    - Daily monitoring: ¥450/day (¥13,500/month equivalent)
    - Monthly budget: ¥7,000/month with 50%, 80%, 90%, 100% alerts
    - Emergency shutdown: ¥8,000/month
    - Firestore reads: 30M reads alert (75% of 40M limit)
    
  EOT
}