# Cloud Monitoring configuration for Phase0 v2.1
# Firestore usage tracking and performance monitoring

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

# Notification channel for alerts (email/SMS)
resource "google_monitoring_notification_channel" "email_alerts" {
  display_name = "Phase0 Email Alerts"
  type         = "email"
  
  labels = {
    email_address = "admin@taikichu-app.com"  # Replace with actual admin email
  }
  
  enabled = true
}

# Firestore read operations monitoring
resource "google_monitoring_alert_policy" "firestore_reads_daily" {
  display_name = "Firestore Daily Reads Limit"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Firestore reads > 32M per day (80% of limit)"
    
    condition_threshold {
      filter          = "resource.type=\"firestore_instance\" AND metric.type=\"firestore.googleapis.com/api/request_count\" AND metric.label.method_name=\"BatchGet\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 32000000  # 32M reads (80% of 40M daily limit)
      
      aggregations {
        alignment_period     = "86400s"  # 24 hours
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  conditions {
    display_name = "Firestore reads > 35M per day (87.5% of limit)"
    
    condition_threshold {
      filter          = "resource.type=\"firestore_instance\" AND metric.type=\"firestore.googleapis.com/api/request_count\""
      duration        = "600s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 35000000  # 35M reads (87.5% of 40M limit)
      
      aggregations {
        alignment_period     = "86400s"  # 24 hours
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alerts.name]
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  documentation {
    content = <<-EOT
      Firestore read operations are approaching Phase0 v2.1 limits.
      
      Daily limit: 40M reads
      Current alert: 80% (32M) and 87.5% (35M)
      
      Actions to take:
      1. Review application caching strategies
      2. Optimize Firestore queries
      3. Consider Phase1 migration with Redis caching
      4. Check for unexpected traffic spikes
      
      Emergency contact: admin@taikichu-app.com
    EOT
    mime_type = "text/markdown"
  }
}

# Firestore write operations monitoring
resource "google_monitoring_alert_policy" "firestore_writes_daily" {
  display_name = "Firestore Daily Writes Monitoring"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Firestore writes > 800K per day"
    
    condition_threshold {
      filter          = "resource.type=\"firestore_instance\" AND metric.type=\"firestore.googleapis.com/api/request_count\" AND metric.label.method_name=~\"(Write|Commit|BatchWrite)\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 800000  # 800K writes (80% of 1M expected)
      
      aggregations {
        alignment_period     = "86400s"  # 24 hours
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alerts.name]
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
}

# Cloud Run performance monitoring
resource "google_monitoring_alert_policy" "cloud_run_latency" {
  display_name = "Cloud Run P95 Latency Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Request latency P95 > 600ms"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 600  # 600ms (Phase0 v2.1 target)
      
      aggregations {
        alignment_period     = "300s"  # 5 minutes
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_PERCENTILE_95"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alerts.name]
  
  alert_strategy {
    auto_close = "3600s"  # 1 hour
  }
  
  documentation {
    content = <<-EOT
      Cloud Run request latency P95 exceeded Phase0 targets.
      
      Target: P95 < 600ms, P90 < 400ms
      
      Potential causes:
      1. High Firestore read latency
      2. Cold starts (check min_instances setting)
      3. Resource constraints (CPU/Memory)
      4. Database query optimization needed
      
      Consider Phase1 migration if latency issues persist for 1 week.
    EOT
    mime_type = "text/markdown"
  }
}

# Cloud Run error rate monitoring
resource "google_monitoring_alert_policy" "cloud_run_errors" {
  display_name = "Cloud Run Error Rate Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Error rate > 5%"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.05  # 5% error rate
      
      aggregations {
        alignment_period     = "300s"  # 5 minutes
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.response_code_class"]
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alerts.name]
  
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }
}

# Cloud Storage usage monitoring
resource "google_monitoring_alert_policy" "storage_usage" {
  display_name = "Cloud Storage Usage Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Storage usage > 25GB"
    
    condition_threshold {
      filter          = "resource.type=\"gcs_bucket\" AND metric.type=\"storage.googleapis.com/storage/total_bytes\""
      duration        = "600s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 26843545600  # 25GB in bytes
      
      aggregations {
        alignment_period     = "3600s"  # 1 hour
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alerts.name]
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
}

# Daily Active Users (DAU) monitoring
resource "google_monitoring_alert_policy" "dau_threshold" {
  display_name = "DAU Threshold Monitoring"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "DAU > 8000 (Phase1 migration trigger)"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 8000  # 8000 DAU triggers Phase1 migration
      
      aggregations {
        alignment_period     = "86400s"  # 24 hours
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alerts.name]
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  documentation {
    content = <<-EOT
      DAU exceeded Phase1 migration threshold.
      
      Current: >8000 DAU
      Phase1 triggers: MAU > 8000, Firestore reads > 35M/day for 3 days, P95 latency > 780ms for 1 week
      
      Actions:
      1. Verify DAU calculation accuracy
      2. Prepare for Phase1 migration
      3. Review infrastructure scaling requirements
      4. Execute migration script: ./scripts/migrate-to-phase1.sh
    EOT
    mime_type = "text/markdown"
  }
}

# Custom dashboard for Phase0 monitoring
resource "google_monitoring_dashboard" "phase0_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Phase0 v2.1 Monitoring Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Firestore Daily Reads"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"firestore_instance\" AND metric.type=\"firestore.googleapis.com/api/request_count\""
                    aggregation = {
                      alignmentPeriod = "86400s"
                      perSeriesAligner = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Reads per day"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Cloud Run Request Latency P95"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\""
                    aggregation = {
                      alignmentPeriod = "300s"
                      perSeriesAligner = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_PERCENTILE_95"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 4
          widget = {
            title = "Daily Cost Estimation"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/billable_instance_time\""
                  aggregation = {
                    alignmentPeriod = "86400s"
                    perSeriesAligner = "ALIGN_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          yPos = 4
          widget = {
            title = "Error Rate"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.response_code_class!=\"2xx\""
                    aggregation = {
                      alignmentPeriod = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "STACKED_AREA"
              }]
            }
          }
        }
      ]
    }
  })
}

# Outputs
output "monitoring_dashboard_url" {
  description = "URL to the Phase0 monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.phase0_dashboard.id}?project=${var.project_id}"
}

output "notification_channel_id" {
  description = "Email notification channel ID"
  value       = google_monitoring_notification_channel.email_alerts.name
}

output "alert_policies" {
  description = "Created alert policies"
  value = {
    firestore_reads = google_monitoring_alert_policy.firestore_reads_daily.name
    firestore_writes = google_monitoring_alert_policy.firestore_writes_daily.name
    cloud_run_latency = google_monitoring_alert_policy.cloud_run_latency.name
    cloud_run_errors = google_monitoring_alert_policy.cloud_run_errors.name
    storage_usage = google_monitoring_alert_policy.storage_usage.name
    dau_threshold = google_monitoring_alert_policy.dau_threshold.name
  }
}