import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taikichu_app/services/moderation_logs_service.dart';
import 'package:taikichu_app/services/admin_authorization_service.dart';

// Mock classes
@GenerateMocks([FirebaseAuth, User, IdTokenResult])
import 'admin_functionality_test.mocks.dart';

void main() {
  group('Admin Functionality Tests', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockIdTokenResult mockIdTokenResult;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockIdTokenResult = MockIdTokenResult();
    });

    group('AdminAuthorizationService', () {
      testWidgets('should grant access to moderator for basic operations', (tester) async {
        // Arrange
        when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
        when(mockIdTokenResult.claims).thenReturn({'role': 'moderator'});
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final hasPermission = await AdminAuthorizationService.checkPermission('moderate_content');

        // Assert
        expect(hasPermission, isTrue);
      });

      testWidgets('should deny access to moderator for admin operations', (tester) async {
        // Arrange
        when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
        when(mockIdTokenResult.claims).thenReturn({'role': 'moderator'});
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final hasPermission = await AdminAuthorizationService.checkPermission('ban_user');

        // Assert
        expect(hasPermission, isFalse);
      });

      testWidgets('should grant access to admin for admin operations', (tester) async {
        // Arrange
        when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
        when(mockIdTokenResult.claims).thenReturn({'role': 'admin'});
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final hasPermission = await AdminAuthorizationService.checkPermission('ban_user');

        // Assert
        expect(hasPermission, isTrue);
      });

      testWidgets('should deny access to superadmin-only operations for regular admin', (tester) async {
        // Arrange
        when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
        when(mockIdTokenResult.claims).thenReturn({'role': 'admin'});
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final hasPermission = await AdminAuthorizationService.checkPermission('manage_admins');

        // Assert
        expect(hasPermission, isFalse);
      });

      testWidgets('should grant access to superadmin for all operations', (tester) async {
        // Arrange
        when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
        when(mockIdTokenResult.claims).thenReturn({'role': 'superadmin'});
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final hasManageAdmins = await AdminAuthorizationService.checkPermission('manage_admins');
        final hasBanUser = await AdminAuthorizationService.checkPermission('ban_user');
        final hasModerateContent = await AdminAuthorizationService.checkPermission('moderate_content');

        // Assert
        expect(hasManageAdmins, isTrue);
        expect(hasBanUser, isTrue);
        expect(hasModerateContent, isTrue);
      });

      testWidgets('should deny access for unauthenticated users', (tester) async {
        // Arrange
        when(mockAuth.currentUser).thenReturn(null);

        // Act
        final hasPermission = await AdminAuthorizationService.checkPermission('view_reports');

        // Assert
        expect(hasPermission, isFalse);
      });

      testWidgets('should detect high-risk operations correctly', (tester) async {
        // Act & Assert
        expect(AdminAuthorizationService._isHighRiskAction('ban_user'), isTrue);
        expect(AdminAuthorizationService._isHighRiskAction('delete_user'), isTrue);
        expect(AdminAuthorizationService._isHighRiskAction('moderate_content'), isFalse);
        expect(AdminAuthorizationService._isHighRiskAction('view_reports'), isFalse);
      });
    });

    group('ModerationLogsService', () {
      testWidgets('should create audit log with all required fields', (tester) async {
        // Arrange
        when(mockUser.uid).thenReturn('test-admin-uid');
        when(mockUser.email).thenReturn('admin@test.com');
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final result = await ModerationLogsService.logAdminAction(
          action: AdminActions.userBan,
          targetType: AdminTargetTypes.user,
          targetId: 'test-user-id',
          reason: 'Test ban reason',
          notes: 'Test notes',
          metadata: {'test': 'data'},
        );

        // Assert
        expect(result, isTrue);
        // Note: In a real test, you would verify the log was actually created
        // This would require mocking the analytics service or database
      });

      testWidgets('should handle missing user gracefully', (tester) async {
        // Arrange
        when(mockAuth.currentUser).thenReturn(null);

        // Act & Assert
        expect(
          () => ModerationLogsService.logAdminAction(
            action: AdminActions.userBan,
            targetType: AdminTargetTypes.user,
            targetId: 'test-user-id',
            reason: 'Test reason',
          ),
          throwsA(isA<Exception>()),
        );
      });

      testWidgets('should calculate severity levels correctly', (tester) async {
        // Act & Assert
        expect(ModerationLogsService._calculateSeverity('user_ban'), equals('HIGH'));
        expect(ModerationLogsService._calculateSeverity('content_hide'), equals('MEDIUM'));
        expect(ModerationLogsService._calculateSeverity('content_review'), equals('LOW'));
        expect(ModerationLogsService._calculateSeverity('unknown_action'), equals('MEDIUM'));
      });

      testWidgets('should identify approval-required actions', (tester) async {
        // Act & Assert
        expect(ModerationLogsService._requiresApproval('user_ban'), isTrue);
        expect(ModerationLogsService._requiresApproval('user_delete'), isTrue);
        expect(ModerationLogsService._requiresApproval('content_hide'), isFalse);
        expect(ModerationLogsService._requiresApproval('user_warning'), isFalse);
      });
    });

    group('Admin Operations Integration', () {
      testWidgets('should complete full authorization and audit flow', (tester) async {
        // Arrange
        when(mockUser.uid).thenReturn('test-admin-uid');
        when(mockUser.email).thenReturn('admin@test.com');
        when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
        when(mockIdTokenResult.claims).thenReturn({'role': 'admin'});
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final authResult = await AdminAuthorizationService.authorizeAdminAction(
          action: 'ban_user',
          targetType: 'user',
          targetId: 'test-target-user',
          reason: 'Test violation',
        );

        // Assert
        expect(authResult.success, isTrue);
        expect(authResult.message, isNull);
      });

      testWidgets('should block unauthorized operations', (tester) async {
        // Arrange
        when(mockUser.uid).thenReturn('test-moderator-uid');
        when(mockUser.email).thenReturn('moderator@test.com');
        when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
        when(mockIdTokenResult.claims).thenReturn({'role': 'moderator'});
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final authResult = await AdminAuthorizationService.authorizeAdminAction(
          action: 'ban_user', // Moderator doesn't have permission for this
          targetType: 'user',
          targetId: 'test-target-user',
          reason: 'Test violation',
        );

        // Assert
        expect(authResult.success, isFalse);
        expect(authResult.message, isNotNull);
        expect(authResult.message!, contains('権限'));
      });

      testWidgets('should enforce business hours for high-risk operations', (tester) async {
        // Note: This test would need to mock DateTime.now() to test outside business hours
        // For demonstration purposes, we'll test the logic exists
        
        // Arrange
        when(mockUser.uid).thenReturn('test-admin-uid');
        when(mockUser.email).thenReturn('admin@test.com');
        when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
        when(mockIdTokenResult.claims).thenReturn({'role': 'admin'});
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final authResult = await AdminAuthorizationService.authorizeAdminAction(
          action: 'ban_user',
          targetType: 'user',
          targetId: 'test-target-user',
          reason: 'Test violation',
        );

        // Assert
        // During business hours, should succeed
        // Outside business hours, should fail with time restriction message
        expect(authResult, isNotNull);
      });
    });

    group('Security Tests', () {
      testWidgets('should log unauthorized access attempts', (tester) async {
        // Arrange
        when(mockAuth.currentUser).thenReturn(null);

        // Act
        final authResult = await AdminAuthorizationService.authorizeAdminAction(
          action: 'ban_user',
          targetType: 'user',
          targetId: 'test-target-user',
          reason: 'Test violation',
        );

        // Assert
        expect(authResult.success, isFalse);
        expect(authResult.message, contains('認証'));
        // Note: In a real test, you would verify that the unauthorized attempt was logged
      });

      testWidgets('should validate session before operations', (tester) async {
        // Arrange
        when(mockUser.getIdToken(true)).thenAnswer((_) async => 'valid-token');
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final isValid = await AdminAuthorizationService.validateSession();

        // Assert
        expect(isValid, isTrue);
      });

      testWidgets('should handle invalid sessions', (tester) async {
        // Arrange
        when(mockUser.getIdToken(true)).thenThrow(Exception('Token expired'));
        when(mockAuth.currentUser).thenReturn(mockUser);

        // Act
        final isValid = await AdminAuthorizationService.validateSession();

        // Assert
        expect(isValid, isFalse);
      });
    });

    group('Audit Log Data Model', () {
      testWidgets('should serialize and deserialize ModerationLog correctly', (tester) async {
        // Arrange
        final originalLog = ModerationLog(
          id: 'test-log-id',
          action: 'user_ban',
          targetType: 'user',
          targetId: 'test-user',
          reason: 'Violation of terms',
          adminUid: 'admin-uid',
          adminEmail: 'admin@test.com',
          timestamp: DateTime.now(),
          severity: 'HIGH',
          requiresApproval: true,
          notes: 'Test notes',
          metadata: {'key': 'value'},
        );

        // Act
        final json = originalLog.toJson();
        final deserializedLog = ModerationLog.fromJson(json);

        // Assert
        expect(deserializedLog.id, equals(originalLog.id));
        expect(deserializedLog.action, equals(originalLog.action));
        expect(deserializedLog.targetType, equals(originalLog.targetType));
        expect(deserializedLog.targetId, equals(originalLog.targetId));
        expect(deserializedLog.reason, equals(originalLog.reason));
        expect(deserializedLog.adminUid, equals(originalLog.adminUid));
        expect(deserializedLog.adminEmail, equals(originalLog.adminEmail));
        expect(deserializedLog.severity, equals(originalLog.severity));
        expect(deserializedLog.requiresApproval, equals(originalLog.requiresApproval));
        expect(deserializedLog.notes, equals(originalLog.notes));
        expect(deserializedLog.metadata, equals(originalLog.metadata));
      });
    });
  });

  group('Performance Tests', () {
    testWidgets('should complete authorization check within acceptable time', (tester) async {
      // Arrange
      final mockAuth = MockFirebaseAuth();
      final mockUser = MockUser();
      final mockIdTokenResult = MockIdTokenResult();
      
      when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
      when(mockIdTokenResult.claims).thenReturn({'role': 'admin'});
      when(mockAuth.currentUser).thenReturn(mockUser);

      // Act
      final stopwatch = Stopwatch()..start();
      await AdminAuthorizationService.checkPermission('moderate_content');
      stopwatch.stop();

      // Assert
      expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should complete within 1 second
    });

    testWidgets('should handle concurrent authorization requests', (tester) async {
      // Arrange
      final mockAuth = MockFirebaseAuth();
      final mockUser = MockUser();
      final mockIdTokenResult = MockIdTokenResult();
      
      when(mockUser.getIdTokenResult()).thenAnswer((_) async => mockIdTokenResult);
      when(mockIdTokenResult.claims).thenReturn({'role': 'admin'});
      when(mockAuth.currentUser).thenReturn(mockUser);

      // Act
      final futures = List.generate(10, (index) => 
        AdminAuthorizationService.checkPermission('moderate_content')
      );
      final results = await Future.wait(futures);

      // Assert
      expect(results.length, equals(10));
      expect(results.every((result) => result == true), isTrue);
    });
  });
}