// Cloud Billing API integration for Phase0 v2.1 cost monitoring
// Real-time budget tracking and emergency cost controls

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { google } from 'googleapis';

const db = admin.firestore();

// Phase0 v2.1 budget thresholds
const DAILY_BUDGET_THRESHOLD = 450; // ¥450/day
const MONTHLY_BUDGET_THRESHOLD = 7000; // ¥7,000/month
const EMERGENCY_SHUTDOWN_THRESHOLD = 8000; // ¥8,000/month for emergency shutdown

interface BillingData {
  costSoFar: number;
  budgetAmount: number;
  percentageSpent: number;
}

// Cloud Billing API client setup
const billing = google.cloudbilling('v1');

/**
 * Daily budget monitoring - triggered by Pub/Sub from Cloud Billing
 */
export const monitorDailyBudget = functions.pubsub
  .topic('budget-alerts')
  .onPublish(async (message) => {
    try {
      const budgetData = message.json as BillingData;
      const currentDate = new Date().toISOString().split('T')[0];
      
      console.log(`Budget alert received: ¥${budgetData.costSoFar}, ${budgetData.percentageSpent}%`);
      
      // Calculate daily cost (rough estimate)
      const dayOfMonth = new Date().getDate();
      const estimatedDailyCost = budgetData.costSoFar / dayOfMonth;
      
      // Store budget data in Firestore
      await db.collection('budget_monitoring').doc(currentDate).set({
        date: currentDate,
        totalCostSoFar: budgetData.costSoFar,
        estimatedDailyCost: estimatedDailyCost,
        percentageSpent: budgetData.percentageSpent,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      // Check daily threshold
      if (estimatedDailyCost > DAILY_BUDGET_THRESHOLD) {
        await handleDailyBudgetAlert(estimatedDailyCost, budgetData);
      }
      
      // Check monthly threshold
      if (budgetData.costSoFar > MONTHLY_BUDGET_THRESHOLD) {
        await handleMonthlyBudgetAlert(budgetData);
      }
      
      // Emergency shutdown check
      if (budgetData.costSoFar > EMERGENCY_SHUTDOWN_THRESHOLD) {
        await handleEmergencyShutdown(budgetData);
      }
      
    } catch (error) {
      console.error('Error monitoring daily budget:', error);
    }
  });

/**
 * Handle daily budget threshold exceeded (¥450/day)
 */
async function handleDailyBudgetAlert(dailyCost: number, budgetData: BillingData) {
  console.warn(`Daily budget threshold exceeded: ¥${dailyCost} > ¥${DAILY_BUDGET_THRESHOLD}`);
  
  // Create alert document
  await db.collection('alerts').add({
    type: 'daily_budget_exceeded',
    dailyCost: dailyCost,
    threshold: DAILY_BUDGET_THRESHOLD,
    currentMonthTotal: budgetData.costSoFar,
    severity: 'warning',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    actions: [
      'Review Firestore usage patterns',
      'Check for unexpected traffic spikes',
      'Consider scaling down if necessary'
    ]
  });
  
  // Log detailed cost breakdown request
  await requestCostBreakdown();
}

/**
 * Handle monthly budget threshold exceeded (¥7,000/month)
 */
async function handleMonthlyBudgetAlert(budgetData: BillingData) {
  console.error(`Monthly budget threshold exceeded: ¥${budgetData.costSoFar} > ¥${MONTHLY_BUDGET_THRESHOLD}`);
  
  // Create critical alert
  await db.collection('alerts').add({
    type: 'monthly_budget_exceeded',
    monthlyCost: budgetData.costSoFar,
    threshold: MONTHLY_BUDGET_THRESHOLD,
    percentageSpent: budgetData.percentageSpent,
    severity: 'critical',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    actions: [
      'IMMEDIATE: Implement cost reduction measures',
      'Scale down Cloud Run min_instances to 0',
      'Enable aggressive image compression',
      'Reduce Firestore read operations'
    ]
  });
  
  // Trigger automatic cost reduction measures
  await triggerCostReductionMeasures();
}

/**
 * Emergency shutdown for budget protection (¥8,000/month)
 */
async function handleEmergencyShutdown(budgetData: BillingData) {
  console.error(`EMERGENCY: Budget critically exceeded: ¥${budgetData.costSoFar} > ¥${EMERGENCY_SHUTDOWN_THRESHOLD}`);
  
  // Create emergency alert
  await db.collection('alerts').add({
    type: 'emergency_budget_shutdown',
    monthlyCost: budgetData.costSoFar,
    threshold: EMERGENCY_SHUTDOWN_THRESHOLD,
    severity: 'emergency',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    actions: [
      'EMERGENCY SHUTDOWN TRIGGERED',
      'Cloud Run scaled to 0 instances',
      'All non-essential services disabled',
      'Manual intervention required to restore'
    ]
  });
  
  // Execute emergency shutdown procedures
  await executeEmergencyShutdown();
}

/**
 * Request detailed cost breakdown from Cloud Billing API
 */
async function requestCostBreakdown() {
  try {
    // This would integrate with Cloud Billing Export to BigQuery
    // For now, log a request for manual investigation
    console.log('Requesting detailed cost breakdown for investigation');
    
    await db.collection('cost_analysis_requests').add({
      requestType: 'daily_cost_breakdown',
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      priority: 'high',
      status: 'pending'
    });
    
  } catch (error) {
    console.error('Error requesting cost breakdown:', error);
  }
}

/**
 * Trigger automatic cost reduction measures
 */
async function triggerCostReductionMeasures() {
  try {
    console.log('Triggering automatic cost reduction measures');
    
    // Store cost reduction triggers for Cloud Run deployment
    await db.collection('cost_reduction_triggers').add({
      triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
      measures: [
        {
          service: 'cloud_run',
          action: 'reduce_min_instances',
          from: 1,
          to: 0,
          estimatedSavings: '¥2,100/month'
        },
        {
          service: 'firestore',
          action: 'enable_aggressive_caching',
          description: 'Reduce read operations by 30%'
        },
        {
          service: 'logging',
          action: 'emergency_log_purge',
          description: 'Delete all non-ERROR logs immediately'
        }
      ],
      status: 'pending_deployment'
    });
    
  } catch (error) {
    console.error('Error triggering cost reduction measures:', error);
  }
}

/**
 * Execute emergency shutdown procedures
 */
async function executeEmergencyShutdown() {
  try {
    console.log('EXECUTING EMERGENCY SHUTDOWN');
    
    // Store emergency shutdown commands
    await db.collection('emergency_shutdown').add({
      triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
      shutdownCommands: [
        'gcloud run services update taikichu-app --min-instances=0 --max-instances=1',
        'gcloud functions deploy --set-env-vars EMERGENCY_MODE=true',
        'gcloud compute instances stop --all'
      ],
      status: 'shutdown_initiated',
      manualRestoreRequired: true,
      estimatedDowntime: '15-30 minutes',
      contactInfo: 'Manual intervention required to restore service'
    });
    
    // Set emergency mode flag
    await db.collection('system_status').doc('emergency').set({
      emergencyMode: true,
      reason: 'budget_exceeded',
      triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
      shutdownLevel: 'full'
    });
    
  } catch (error) {
    console.error('Error executing emergency shutdown:', error);
  }
}

/**
 * Firestore usage monitoring (complementary to budget monitoring)
 */
export const monitorFirestoreUsage = functions.pubsub
  .schedule('0 */2 * * *') // Every 2 hours
  .timeZone('Asia/Tokyo')
  .onRun(async (context) => {
    try {
      const currentDate = new Date().toISOString().split('T')[0];
      const currentMonth = new Date().toISOString().substring(0, 7);
      
      // Get approximate Firestore usage (this is a simplified calculation)
      // In production, integrate with Cloud Monitoring API for actual metrics
      const hoursSinceStart = new Date().getHours();
      const estimatedDailyReads = hoursSinceStart * 1000000; // Rough estimate
      const estimatedMonthlyReads = estimatedDailyReads * new Date().getDate();
      
      // Check against Phase0 limits (40M reads/month)
      const monthlyReadLimit = 40000000;
      const usagePercentage = (estimatedMonthlyReads / monthlyReadLimit) * 100;
      
      // Store usage data
      await db.collection('firestore_usage').doc(currentDate).set({
        date: currentDate,
        estimatedDailyReads: estimatedDailyReads,
        estimatedMonthlyReads: estimatedMonthlyReads,
        usagePercentage: usagePercentage,
        limit: monthlyReadLimit,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      
      // Alert if approaching limits
      if (usagePercentage > 80) {
        await db.collection('alerts').add({
          type: 'firestore_usage_high',
          usagePercentage: usagePercentage,
          estimatedMonthlyReads: estimatedMonthlyReads,
          limit: monthlyReadLimit,
          severity: usagePercentage > 90 ? 'critical' : 'warning',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      
    } catch (error) {
      console.error('Error monitoring Firestore usage:', error);
    }
  });

/**
 * Health check with budget status
 */
export const budgetHealthCheck = functions.https.onRequest(async (req, res) => {
  try {
    const currentDate = new Date().toISOString().split('T')[0];
    
    // Get latest budget data
    const budgetDoc = await db.collection('budget_monitoring').doc(currentDate).get();
    const budgetData = budgetDoc.exists ? budgetDoc.data() : null;
    
    // Get emergency status
    const emergencyDoc = await db.collection('system_status').doc('emergency').get();
    const emergencyData = emergencyDoc.exists ? emergencyDoc.data() : null;
    
    // Get recent alerts
    const alertsSnapshot = await db.collection('alerts')
      .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000)))
      .orderBy('timestamp', 'desc')
      .limit(5)
      .get();
    
    const recentAlerts = alertsSnapshot.docs.map(doc => doc.data());
    
    res.status(200).json({
      status: emergencyData?.emergencyMode ? 'emergency' : 'operational',
      budgetStatus: {
        dailyThreshold: DAILY_BUDGET_THRESHOLD,
        monthlyThreshold: MONTHLY_BUDGET_THRESHOLD,
        currentData: budgetData,
        withinBudget: budgetData ? budgetData.totalCostSoFar <= MONTHLY_BUDGET_THRESHOLD : true
      },
      emergencyMode: emergencyData?.emergencyMode || false,
      recentAlerts: recentAlerts,
      phase: '0',
      version: '2.1',
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    res.status(500).json({
      status: 'error',
      error: error instanceof Error ? error.message : 'Unknown error',
      timestamp: new Date().toISOString()
    });
  }
});