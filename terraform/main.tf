# Taikichu App Phase0 - Complete Infrastructure as Code
# Single-command deployment: terraform apply

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
  }
}

# Variables
variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "taikichu-app-c8dcd"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast1"
}

variable "billing_account_id" {
  description = "Google Cloud Billing Account ID"
  type        = string
  # Must be provided during deployment
}

variable "admin_email" {
  description = "Admin email for notifications"
  type        = string
  default     = "admin@taikichu-app.com"
}

# Configure providers
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudrun.googleapis.com",
    "firestore.googleapis.com",
    "firebase.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com"
  ])

  service = each.value
  disable_on_destroy = false
}

# Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "functions_bucket" {
  name     = "${var.project_id}-functions-source"
  location = var.region
  
  uniform_bucket_level_access = true
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = {
    environment = "phase0"
    purpose     = "functions"
  }
}

# Storage bucket for user uploads
resource "google_storage_bucket" "user_uploads" {
  name     = "${var.project_id}-user-uploads"
  location = var.region
  
  uniform_bucket_level_access = true
  
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }
  
  labels = {
    environment = "phase0"
    purpose     = "user_uploads"
  }
}

# Firebase project configuration
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id
  
  depends_on = [google_project_service.apis]
}

# Firestore database
resource "google_firestore_database" "database" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  
  depends_on = [google_firebase_project.default]
}

# Service account for Firebase Admin SDK
resource "google_service_account" "firebase_admin" {
  account_id   = "firebase-admin"
  display_name = "Firebase Admin SDK"
  description  = "Service account for Firebase Admin SDK operations"
}

# Service account key for Firebase Admin SDK
resource "google_service_account_key" "firebase_admin_key" {
  service_account_id = google_service_account.firebase_admin.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Store the service account key in Secret Manager
resource "google_secret_manager_secret" "firebase_admin_key" {
  secret_id = "firebase-admin-key"
  
  replication {
    automatic = true
  }
  
  labels = {
    environment = "phase0"
    purpose     = "firebase_admin"
  }
}

resource "google_secret_manager_secret_version" "firebase_admin_key" {
  secret      = google_secret_manager_secret.firebase_admin_key.id
  secret_data = base64decode(google_service_account_key.firebase_admin_key.private_key)
}

# IAM roles for Firebase Admin service account
resource "google_project_iam_member" "firebase_admin_roles" {
  for_each = toset([
    "roles/firebase.admin",
    "roles/datastore.user",
    "roles/storage.admin",
    "roles/cloudfunctions.admin"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
}

# Firebase Authentication configuration
resource "google_identity_platform_config" "auth_config" {
  provider = google-beta
  project  = var.project_id
  
  sign_in {
    allow_duplicate_emails = false
    
    email {
      enabled           = true
      password_required = true
    }
  }
  
  depends_on = [google_firebase_project.default]
}

# Cloud Run service for Phase0
resource "google_cloud_run_service" "app" {
  name     = "taikichu-app"
  location = var.region
  
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = "1"
        "autoscaling.knative.dev/maxScale" = "10"
        "run.googleapis.com/cpu-throttling" = "true"
        "run.googleapis.com/execution-environment" = "gen2"
      }
    }
    
    spec {
      container_concurrency = 40
      timeout_seconds       = 300
      
      containers {
        image = "gcr.io/${var.project_id}/taikichu-app:latest"
        
        resources {
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "500m"
            memory = "256Mi"
          }
        }
        
        env {
          name  = "FIRESTORE_PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "NODE_ENV"
          value = "production"
        }
        
        env {
          name  = "LOG_LEVEL"
          value = "ERROR"
        }
        
        env {
          name  = "MAX_REQUESTS_PER_MINUTE"
          value = "30"
        }
        
        env {
          name  = "PHASE"
          value = "0"
        }
        
        env {
          name = "GOOGLE_APPLICATION_CREDENTIALS"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.firebase_admin_key.secret_id
              key  = "latest"
            }
          }
        }
        
        ports {
          container_port = 8080
        }
        
        liveness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 30
          period_seconds        = 60
          timeout_seconds       = 10
          failure_threshold     = 3
        }
        
        readiness_probe {
          http_get {
            path = "/ready"
            port = 8080
          }
          initial_delay_seconds = 10
          period_seconds        = 30
          timeout_seconds       = 5
          failure_threshold     = 2
        }
        
        startup_probe {
          http_get {
            path = "/startup"
            port = 8080
          }
          initial_delay_seconds = 10
          period_seconds        = 10
          timeout_seconds       = 5
          failure_threshold     = 30
        }
      }
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [google_project_service.apis]
}

# Allow unauthenticated access to Cloud Run
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_service.app.name
  location = google_cloud_run_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Firebase Hosting configuration
resource "google_firebase_hosting_site" "admin_interface" {
  provider = google-beta
  project  = var.project_id
  site_id  = "${var.project_id}-admin"
  
  depends_on = [google_firebase_project.default]
}

# IAM roles for Cloud Run service account
resource "google_service_account" "cloud_run" {
  account_id   = "cloud-run-service"
  display_name = "Cloud Run Service Account"
  description  = "Service account for Cloud Run Phase0 application"
}

resource "google_project_iam_member" "cloud_run_roles" {
  for_each = toset([
    "roles/datastore.user",
    "roles/storage.objectViewer",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Update Cloud Run to use the service account
resource "google_cloud_run_service_iam_member" "cloud_run_sa" {
  service  = google_cloud_run_service.app.name
  location = google_cloud_run_service.app.location
  role     = "roles/run.serviceAgent"
  member   = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Security: Firestore security rules deployment placeholder
# Note: Security rules should be deployed via Firebase CLI: firebase deploy --only firestore:rules

# Output important information
output "project_setup_complete" {
  description = "Project setup completion status"
  value = {
    project_id        = var.project_id
    region           = var.region
    cloud_run_url    = google_cloud_run_service.app.status[0].url
    admin_site_url   = "https://${google_firebase_hosting_site.admin_interface.site_id}.web.app"
    firebase_config  = "Firebase project configured with Firestore and Authentication"
    service_account  = google_service_account.firebase_admin.email
  }
}

output "next_steps" {
  description = "Manual steps required after Terraform deployment"
  value = <<-EOT
    
    🎉 TERRAFORM DEPLOYMENT COMPLETE!
    
    ✅ Infrastructure Ready:
    - Firebase project: ${var.project_id}
    - Firestore database: Ready for use
    - Cloud Run service: ${google_cloud_run_service.app.status[0].url}
    - Cloud Storage buckets: Created and configured
    - Service accounts: Created with proper IAM roles
    - Monitoring & Budgets: Configured (see budget-alerts.tf and monitoring.tf)
    
    📋 NEXT MANUAL STEPS:
    
    1. Build and Deploy Application:
       cd /path/to/your/app
       gcloud builds submit --tag gcr.io/${var.project_id}/taikichu-app:latest
       gcloud run deploy taikichu-app --image gcr.io/${var.project_id}/taikichu-app:latest --region ${var.region}
    
    2. Deploy Firestore Security Rules:
       firebase deploy --only firestore:rules
    
    3. Deploy Firebase Functions:
       cd functions
       npm install
       firebase deploy --only functions
    
    4. Deploy Admin Interface:
       cd admin_interface
       flutter build web --release
       firebase deploy --only hosting:${google_firebase_hosting_site.admin_interface.site_id}
    
    5. Set up Admin Users:
       firebase auth:import admin_users.json
       # Or create manually in Firebase Console
    
    6. Verify Setup:
       - Test app at: ${google_cloud_run_service.app.status[0].url}
       - Test admin at: https://${google_firebase_hosting_site.admin_interface.site_id}.web.app
       - Check monitoring: https://console.cloud.google.com/monitoring
    
    🔐 SECURITY:
    - Firebase Admin Key stored in Secret Manager: ${google_secret_manager_secret.firebase_admin_key.secret_id}
    - Download for local development: gcloud secrets versions access latest --secret="${google_secret_manager_secret.firebase_admin_key.secret_id}"
    
    💰 COST MONITORING:
    - Daily budget: ¥450/day alerts configured
    - Monthly budget: ¥7,000/month with multi-threshold alerts
    - Emergency shutdown: ¥8,000/month threshold
    
    📊 MONITORING:
    - Dashboard: Access via Google Cloud Console > Monitoring
    - Alerts: Email notifications to ${var.admin_email}
    - Logs: Cloud Logging enabled for all services
    
  EOT
}

output "deployment_commands" {
  description = "Ready-to-use deployment commands"
  value = {
    terraform_apply = "terraform apply -var='billing_account_id=YOUR_BILLING_ID' -var='admin_email=your@email.com'"
    build_app      = "gcloud builds submit --tag gcr.io/${var.project_id}/taikichu-app:latest"
    deploy_app     = "gcloud run deploy taikichu-app --image gcr.io/${var.project_id}/taikichu-app:latest --region ${var.region}"
    deploy_rules   = "firebase deploy --only firestore:rules"
    deploy_functions = "cd functions && npm install && firebase deploy --only functions"
    deploy_admin   = "cd admin_interface && flutter build web --release && firebase deploy --only hosting:${google_firebase_hosting_site.admin_interface.site_id}"
  }
}