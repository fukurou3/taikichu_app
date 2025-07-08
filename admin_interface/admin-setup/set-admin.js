const admin = require('firebase-admin');

// Firebase Admin SDK初期化（Application Default Credentials使用）
admin.initializeApp({
  projectId: 'taikichu-app-c8dcd'
});

async function setAdminClaims() {
  try {
    // ユーザーを取得
    const user = await admin.auth().getUserByEmail('gensye.lab@gmail.com');
    console.log('User found:', user.uid);

    // カスタムクレーム設定
    await admin.auth().setCustomUserClaims(user.uid, {
      role: 'superadmin',
      permissions: [
        'view_reports', 'view_audit_logs', 'view_users', 
        'moderate_content', 'hide_content', 'warn_user', 'resolve_report',
        'ban_user', 'delete_content', 'delete_user', 'mass_action',
        'manage_admins', 'system_settings'
      ],
      isAdmin: true,
      assignedAt: new Date().toISOString()
    });

    console.log('✅ Successfully set superadmin claims for gensye.lab@gmail.com');
    
    // 確認
    const updatedUser = await admin.auth().getUser(user.uid);
    console.log('Updated claims:', updatedUser.customClaims);
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
  
  process.exit(0);
}

setAdminClaims();