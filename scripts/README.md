# Phase Migration Scripts

This directory contains scripts for managing transitions between Phase0 (Firestore-only) and Phase1 (Redis-cached) architectures.

## Scripts Overview

### 1. `prepare-redis-phase1.tf` 
**Terraform configuration for Redis infrastructure**
- Creates Redis instance (Basic tier, 1GB)
- Sets up VPC network and firewall rules
- Cost: ~¥3,500-5,000/month
- **Note**: Does not auto-deploy - requires manual terraform apply

### 2. `migrate-to-phase1.sh`
**Automated Phase1 migration script**
- Deploys Redis infrastructure using Terraform
- Updates Cloud Run service with Redis integration
- Configures Phase1 environment variables
- Validates deployment and Redis connectivity
- Estimated migration time: 10-15 minutes

**Usage:**
```bash
./migrate-to-phase1.sh
```

### 3. `rollback-to-phase0.sh`
**Rollback script to Phase0**
- Redeploys original Phase0 configuration
- Optional Redis resource cleanup
- Removes Phase1 artifacts
- Validates Phase0 functionality

**Usage:**
```bash
./rollback-to-phase0.sh
```

### 4. `monitor-phase-triggers.sh`
**Monitoring script for migration triggers**
- Checks MAU, Firestore reads, and P95 latency
- Tracks consecutive threshold violations
- Provides migration recommendations
- Should be run daily for continuous monitoring

**Usage:**
```bash
./monitor-phase-triggers.sh
```

## Migration Triggers (from phase0-config.json)

Migrate to Phase1 when **any** of these conditions are met:

| Metric | Threshold | Duration |
|--------|-----------|----------|
| MAU | ≥ 8,000 users | Immediate |
| Firestore Reads | ≥ 35M/day | 3 consecutive days |
| P95 Latency | ≥ 780ms | 1 week |

## Cost Summary

| Phase | Configuration | Monthly Cost |
|-------|--------------|--------------|
| Phase0 | Firestore + Cloud Run (1 instance) | ¥6,250 |
| Phase1 | Phase0 + Redis Basic 1GB | ¥9,750-12,000 |

## Prerequisites

1. **Google Cloud SDK** installed and authenticated
2. **Terraform** installed (for Redis deployment)
3. **Project permissions**: Cloud Run Admin, Redis Admin, Compute Admin
4. **Billing** enabled on GCP project

## Emergency Procedures

### If Phase1 migration fails:
```bash
./rollback-to-phase0.sh
```

### If costs exceed budget:
1. Check `./monitor-phase-triggers.sh` output
2. Consider rollback if Phase1 benefits don't justify cost
3. Review Firestore usage patterns

### If Redis connectivity issues:
1. Check firewall rules: `gcloud compute firewall-rules list`
2. Verify network configuration in Terraform
3. Test Redis connectivity from Cloud Shell

## Monitoring Commands

```bash
# Check current phase
curl https://your-service-url/health

# Monitor costs
gcloud billing budgets list

# Check Firestore usage
gcloud logging read "resource.type=gce_instance" --limit=50

# View Redis metrics (if in Phase1)
gcloud redis instances describe taikichu-cache --region=asia-northeast1
```

## Files Created During Migration

- `.env.phase1` - Phase1 environment variables
- `phase1-monitoring.json` - Phase1 monitoring configuration
- `/tmp/high_reads_days.log` - Firestore usage tracking
- `/tmp/high_latency_weeks.log` - Latency tracking

## Support

For issues with these scripts:
1. Check GCP console for service status
2. Review Cloud Run logs: `gcloud run logs tail`
3. Verify Terraform state: `terraform show`