# Redis preparation script for Phase1 migration
# This script creates Redis infrastructure but does NOT deploy it
# Use when Phase0 triggers indicate need for Phase1 migration

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

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast1"
}

# Redis instance for Phase1 caching
resource "google_redis_instance" "main_cache" {
  name           = "taikichu-cache"
  tier           = "BASIC"
  memory_size_gb = 1  # Start small, can scale up
  region         = var.region
  
  # Cost optimization
  redis_version     = "REDIS_7_0"
  replica_count     = 0  # No replicas for Phase1
  
  # Network configuration
  authorized_network = google_compute_network.redis_network.id
  
  # Persistence disabled for cost savings
  persistence_config {
    persistence_mode    = "DISABLED"
  }
  
  # Maintenance window (low traffic period)
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
      }
    }
  }
  
  labels = {
    environment = "phase1"
    cost_center = "optimization"
    auto_delete = "true"
  }
}

# VPC network for Redis
resource "google_compute_network" "redis_network" {
  name                    = "redis-network"
  auto_create_subnetworks = false
}

# Subnet for Redis
resource "google_compute_subnetwork" "redis_subnet" {
  name          = "redis-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.redis_network.id
}

# Firewall rule for Redis access
resource "google_compute_firewall" "redis_firewall" {
  name    = "allow-redis"
  network = google_compute_network.redis_network.name

  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }

  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["redis-client"]
}

# Output Redis connection info
output "redis_host" {
  description = "Redis instance host"
  value       = google_redis_instance.main_cache.host
  sensitive   = true
}

output "redis_port" {
  description = "Redis instance port"
  value       = google_redis_instance.main_cache.port
}

output "redis_auth_string" {
  description = "Redis AUTH string"
  value       = google_redis_instance.main_cache.auth_string
  sensitive   = true
}

# Cost estimation comment
# Estimated monthly cost: ¥3,500-5,000
# - Redis Basic 1GB: ¥3,000/month
# - Network egress: ¥500-2,000/month
# Total Phase1 cost: ¥9,750-12,000/month (within ¥15,000 budget)