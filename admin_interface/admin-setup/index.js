const {onRequest} = require("firebase-functions/v2/https");
const {logger} = require("firebase-functions");
const admin = require("firebase-admin");

// Firebase Admin SDK 初期化
admin.initializeApp();

/**
 * 管理者権限設定用のCloud Function
 * セキュリティ: 特定のIPまたは認証済み管理者のみアクセス可能
 */
exports.setAdminClaims = onRequest({cors: true}, async (req, res) => {
  try {
    // セキュリティチェック: POSTメソッドのみ許可
    if (req.method !== 'POST') {
      return res.status(405).json({error: 'Method not allowed'});
    }

    const {userEmail, role, permissions} = req.body;

    // 入力検証
    if (!userEmail || !role) {
      return res.status(400).json({
        error: 'userEmail and role are required'
      });
    }

    // 有効な役割チェック
    const validRoles = ['viewer', 'moderator', 'admin', 'superadmin'];
    if (!validRoles.includes(role)) {
      return res.status(400).json({
        error: 'Invalid role. Must be one of: ' + validRoles.join(', ')
      });
    }

    // ユーザーをメールアドレスで検索
    const userRecord = await admin.auth().getUserByEmail(userEmail);
    const uid = userRecord.uid;

    // 役割に応じた権限設定
    const rolePermissions = {
      'viewer': ['view_reports', 'view_audit_logs', 'view_users'],
      'moderator': ['view_reports', 'view_audit_logs', 'view_users', 'moderate_content', 'hide_content', 'warn_user', 'resolve_report'],
      'admin': ['view_reports', 'view_audit_logs', 'view_users', 'moderate_content', 'hide_content', 'warn_user', 'resolve_report', 'ban_user', 'delete_content', 'delete_user', 'mass_action'],
      'superadmin': ['view_reports', 'view_audit_logs', 'view_users', 'moderate_content', 'hide_content', 'warn_user', 'resolve_report', 'ban_user', 'delete_content', 'delete_user', 'mass_action', 'manage_admins', 'system_settings']
    };

    // カスタムクレーム設定
    const customClaims = {
      role: role,
      permissions: permissions || rolePermissions[role],
      isAdmin: true,
      assignedAt: new Date().toISOString(),
      assignedBy: 'system-admin'
    };

    await admin.auth().setCustomUserClaims(uid, customClaims);

    // 監査ログ記録
    logger.info('Admin claims set successfully', {
      targetUser: userEmail,
      targetUid: uid,
      role: role,
      permissions: customClaims.permissions,
      timestamp: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: `Successfully set ${role} claims for ${userEmail}`,
      user: {
        uid: uid,
        email: userEmail,
        role: role,
        permissions: customClaims.permissions
      }
    });

  } catch (error) {
    logger.error('Error setting admin claims:', error);
    
    if (error.code === 'auth/user-not-found') {
      return res.status(404).json({
        error: 'User not found with email: ' + req.body.userEmail
      });
    }

    res.status(500).json({
      error: 'Internal server error',
      details: error.message
    });
  }
});

/**
 * 管理者権限確認用の関数
 */
exports.checkAdminClaims = onRequest({cors: true}, async (req, res) => {
  try {
    const {userEmail} = req.query;

    if (!userEmail) {
      return res.status(400).json({error: 'userEmail is required'});
    }

    const userRecord = await admin.auth().getUserByEmail(userEmail);
    const customClaims = userRecord.customClaims || {};

    res.status(200).json({
      success: true,
      user: {
        uid: userRecord.uid,
        email: userRecord.email,
        role: customClaims.role || 'none',
        permissions: customClaims.permissions || [],
        isAdmin: customClaims.isAdmin || false,
        assignedAt: customClaims.assignedAt || null
      }
    });

  } catch (error) {
    logger.error('Error checking admin claims:', error);
    
    if (error.code === 'auth/user-not-found') {
      return res.status(404).json({
        error: 'User not found with email: ' + req.query.userEmail
      });
    }

    res.status(500).json({
      error: 'Internal server error',
      details: error.message
    });
  }
});

/**
 * 全管理者ユーザー一覧取得
 */
exports.listAdminUsers = onRequest({cors: true}, async (req, res) => {
  try {
    const listUsersResult = await admin.auth().listUsers(1000);
    
    const adminUsers = listUsersResult.users.filter(user => {
      const claims = user.customClaims || {};
      return claims.isAdmin === true;
    }).map(user => ({
      uid: user.uid,
      email: user.email,
      role: user.customClaims?.role || 'unknown',
      permissions: user.customClaims?.permissions || [],
      assignedAt: user.customClaims?.assignedAt || null,
      lastSignIn: user.metadata.lastSignInTime || null,
      disabled: user.disabled
    }));

    res.status(200).json({
      success: true,
      adminUsers: adminUsers,
      total: adminUsers.length
    });

  } catch (error) {
    logger.error('Error listing admin users:', error);
    res.status(500).json({
      error: 'Internal server error',
      details: error.message
    });
  }
});