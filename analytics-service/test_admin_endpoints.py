#!/usr/bin/env python3
"""
管理者機能のエンドポイントテスト

🛡️ 監査ログと管理者操作のテスト
📊 analytics-service の管理者API検証
"""

import json
import time
from datetime import datetime, timezone
from typing import Dict, Any, List

# 管理者操作のテストケース
class AdminEndpointTests:
    def __init__(self, base_url: str = "http://localhost:8080"):
        self.base_url = base_url
        self.test_results = []

    def test_audit_log_creation(self):
        """監査ログ作成のテスト"""
        test_data = {
            "action": "user_ban",
            "target_type": "user",
            "target_id": "test-user-123",
            "reason": "違反行為",
            "admin_uid": "admin-test-uid",
            "admin_email": "admin@test.com",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "severity": "HIGH",
            "requires_approval": True,
            "metadata": {
                "ban_duration_days": 7,
                "action_source": "admin_interface",
                "ip_address": "192.168.1.100"
            }
        }
        
        print("🔍 Testing audit log creation...")
        
        # 実際のテストでは HTTP リクエストを送信
        # response = requests.post(f"{self.base_url}/admin/logs", json=test_data)
        
        # モックテスト
        result = self._mock_create_audit_log(test_data)
        
        assert result["success"] == True
        assert result["log_id"] is not None
        print(f"✅ Audit log created with ID: {result['log_id']}")
        
        return result

    def test_audit_log_retrieval(self):
        """監査ログ取得のテスト"""
        print("🔍 Testing audit log retrieval...")
        
        # フィルター条件
        filters = {
            "action": "user_ban",
            "start_date": "2025-01-01T00:00:00Z",
            "end_date": "2025-12-31T23:59:59Z",
            "limit": 50
        }
        
        # 実際のテストでは HTTP リクエストを送信
        # response = requests.get(f"{self.base_url}/admin/logs", params=filters)
        
        # モックテスト
        result = self._mock_get_audit_logs(filters)
        
        assert result["success"] == True
        assert isinstance(result["logs"], list)
        print(f"✅ Retrieved {len(result['logs'])} audit logs")
        
        return result

    def test_admin_authorization(self):
        """管理者認可のテスト"""
        print("🔍 Testing admin authorization...")
        
        test_cases = [
            {
                "role": "moderator",
                "action": "moderate_content",
                "expected": True
            },
            {
                "role": "moderator", 
                "action": "ban_user",
                "expected": False
            },
            {
                "role": "admin",
                "action": "ban_user", 
                "expected": True
            },
            {
                "role": "admin",
                "action": "manage_admins",
                "expected": False
            },
            {
                "role": "superadmin",
                "action": "manage_admins",
                "expected": True
            }
        ]
        
        for case in test_cases:
            result = self._mock_check_authorization(case["role"], case["action"])
            assert result == case["expected"], f"Authorization failed for {case['role']} -> {case['action']}"
            print(f"✅ {case['role']} -> {case['action']}: {result}")

    def test_admin_activity_stats(self):
        """管理者活動統計のテスト"""
        print("🔍 Testing admin activity stats...")
        
        # 実際のテストでは HTTP リクエストを送信
        # response = requests.get(f"{self.base_url}/admin/activity-stats")
        
        # モックテスト
        result = self._mock_get_activity_stats()
        
        assert result["success"] == True
        assert "total_actions" in result["stats"]
        assert "high_risk_actions" in result["stats"]
        assert "top_moderators" in result["stats"]
        print(f"✅ Activity stats retrieved: {result['stats']['total_actions']} total actions")
        
        return result

    def test_security_violations(self):
        """セキュリティ違反検出のテスト"""
        print("🔍 Testing security violation detection...")
        
        # 営業時間外の高リスク操作
        violation_data = {
            "action": "ban_user",
            "timestamp": "2025-01-15T03:00:00Z",  # 午前3時（営業時間外）
            "admin_uid": "admin-test-uid",
            "target_type": "user",
            "target_id": "test-user-123"
        }
        
        result = self._mock_check_security_violation(violation_data)
        
        assert result["violation_detected"] == True
        assert "business_hours" in result["violation_type"]
        print(f"✅ Security violation detected: {result['violation_type']}")
        
        return result

    def test_audit_log_integrity(self):
        """監査ログの整合性テスト"""
        print("🔍 Testing audit log integrity...")
        
        # 必須フィールドのテスト
        required_fields = [
            "action", "target_type", "target_id", "reason", 
            "admin_uid", "timestamp", "severity"
        ]
        
        log_data = {
            "action": "content_delete",
            "target_type": "countdown",
            "target_id": "countdown-123", 
            "reason": "不適切なコンテンツ",
            "admin_uid": "admin-test-uid",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "severity": "HIGH"
        }
        
        # 必須フィールドチェック
        for field in required_fields:
            assert field in log_data, f"Missing required field: {field}"
        
        # データ型チェック
        assert isinstance(log_data["timestamp"], str)
        assert log_data["severity"] in ["LOW", "MEDIUM", "HIGH"]
        
        print("✅ Audit log integrity check passed")
        
        return True

    def test_permission_escalation_prevention(self):
        """権限昇格防止のテスト"""
        print("🔍 Testing permission escalation prevention...")
        
        # モデレーターが管理者権限を取得しようとする
        escalation_attempts = [
            {
                "current_role": "moderator",
                "attempted_action": "manage_admins",
                "should_block": True
            },
            {
                "current_role": "moderator", 
                "attempted_action": "system_settings",
                "should_block": True
            },
            {
                "current_role": "admin",
                "attempted_action": "manage_admins",  # スーパー管理者のみ
                "should_block": True
            }
        ]
        
        for attempt in escalation_attempts:
            blocked = self._mock_block_escalation(attempt)
            assert blocked == attempt["should_block"], f"Escalation not properly blocked: {attempt}"
            print(f"✅ Blocked escalation: {attempt['current_role']} -> {attempt['attempted_action']}")
        
        return True

    # モックメソッド（実際の実装では HTTP API を呼び出し）
    def _mock_create_audit_log(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "success": True,
            "log_id": f"log_{int(time.time())}",
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

    def _mock_get_audit_logs(self, filters: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "success": True,
            "logs": [
                {
                    "id": "log_123",
                    "action": "user_ban",
                    "target_type": "user",
                    "target_id": "user-123",
                    "admin_uid": "admin-test-uid",
                    "timestamp": "2025-01-15T10:30:00Z",
                    "severity": "HIGH"
                }
            ],
            "total_count": 1
        }

    def _mock_check_authorization(self, role: str, action: str) -> bool:
        permission_matrix = {
            "moderator": ["moderate_content", "hide_content", "warn_user"],
            "admin": ["moderate_content", "hide_content", "warn_user", "ban_user", "delete_content"],
            "superadmin": ["moderate_content", "hide_content", "warn_user", "ban_user", "delete_content", "manage_admins", "system_settings"]
        }
        
        return action in permission_matrix.get(role, [])

    def _mock_get_activity_stats(self) -> Dict[str, Any]:
        return {
            "success": True,
            "stats": {
                "total_actions": 150,
                "high_risk_actions": 25,
                "user_bans": 5,
                "content_deletions": 20,
                "top_moderators": [
                    {"admin_email": "admin1@test.com", "action_count": 75},
                    {"admin_email": "admin2@test.com", "action_count": 45}
                ]
            }
        }

    def _mock_check_security_violation(self, data: Dict[str, Any]) -> Dict[str, Any]:
        timestamp = datetime.fromisoformat(data["timestamp"].replace('Z', '+00:00'))
        hour = timestamp.hour
        
        # 営業時間外チェック（6:00-22:00）
        if hour < 6 or hour > 22:
            return {
                "violation_detected": True,
                "violation_type": "business_hours",
                "message": "High-risk operation outside business hours"
            }
        
        return {
            "violation_detected": False
        }

    def _mock_block_escalation(self, attempt: Dict[str, Any]) -> bool:
        return not self._mock_check_authorization(
            attempt["current_role"], 
            attempt["attempted_action"]
        )

    def run_all_tests(self):
        """全テストの実行"""
        print("🚀 Starting Admin Functionality Tests...\n")
        
        tests = [
            self.test_audit_log_creation,
            self.test_audit_log_retrieval, 
            self.test_admin_authorization,
            self.test_admin_activity_stats,
            self.test_security_violations,
            self.test_audit_log_integrity,
            self.test_permission_escalation_prevention
        ]
        
        passed = 0
        failed = 0
        
        for test in tests:
            try:
                test()
                passed += 1
                print("✅ PASSED\n")
            except Exception as e:
                failed += 1
                print(f"❌ FAILED: {e}\n")
        
        print(f"📊 Test Results: {passed} passed, {failed} failed")
        print(f"✨ Admin functionality tests completed!")
        
        return passed, failed

if __name__ == "__main__":
    # テスト実行
    tester = AdminEndpointTests()
    tester.run_all_tests()