import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// エラー報告ユーティリティクラス
/// 
/// 🎯 目的: アプリ全体のエラー報告を統一し、Firebase Crashlyticsに送信
/// 📊 効果: プロアクティブなバグ検出、ユーザー体験向上
class ErrorReporter {
  
  /// 非致命的エラーを報告
  /// 
  /// ユーザーの操作は継続できるが、修正が必要なエラー
  static Future<void> reportError(
    dynamic error, 
    StackTrace? stackTrace, {
    String? reason,
    Map<String, dynamic>? customData,
    bool fatal = false,
  }) async {
    try {
      // デバッグモードではコンソール出力のみ
      if (kDebugMode) {
        print('🐛 Error Report (Debug Mode): $error');
        if (reason != null) print('📝 Reason: $reason');
        if (stackTrace != null) print('📚 Stack: $stackTrace');
        if (customData != null) print('🔍 Custom Data: $customData');
        return;
      }

      // カスタムデータをCrashlyticsに設定
      if (customData != null) {
        for (final entry in customData.entries) {
          await FirebaseCrashlytics.instance.setCustomKey(
            entry.key, 
            entry.value?.toString() ?? 'null',
          );
        }
      }

      // Crashlyticsにエラーを送信
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: reason,
        fatal: fatal,
      );

    } catch (e) {
      // Crashlytics自体のエラーは静かに処理
      if (kDebugMode) {
        print('⚠️ Failed to report error to Crashlytics: $e');
      }
    }
  }

  /// API関連エラーを報告
  /// 
  /// バックエンドAPI通信のエラーを専用形式で報告
  static Future<void> reportApiError(
    String endpoint,
    int? statusCode,
    String? responseBody,
    dynamic error,
    StackTrace? stackTrace,
  ) async {
    await reportError(
      error,
      stackTrace,
      reason: 'API Error: $endpoint',
      customData: {
        'api_endpoint': endpoint,
        'status_code': statusCode ?? 0,
        'response_body': responseBody?.substring(0, 500) ?? 'empty', // 500文字まで
        'error_type': 'api_error',
      },
    );
  }

  /// Firebase関連エラーを報告
  /// 
  /// Firestore、Auth等のFirebaseサービスエラーを報告
  static Future<void> reportFirebaseError(
    String service,
    String operation,
    dynamic error,
    StackTrace? stackTrace,
  ) async {
    await reportError(
      error,
      stackTrace,
      reason: 'Firebase $service Error: $operation',
      customData: {
        'firebase_service': service,
        'firebase_operation': operation,
        'error_type': 'firebase_error',
      },
    );
  }

  /// UI関連エラーを報告
  /// 
  /// ウィジェットレンダリングやUI操作のエラーを報告
  static Future<void> reportUiError(
    String screen,
    String widget,
    dynamic error,
    StackTrace? stackTrace,
  ) async {
    await reportError(
      error,
      stackTrace,
      reason: 'UI Error: $screen/$widget',
      customData: {
        'screen_name': screen,
        'widget_name': widget,
        'error_type': 'ui_error',
      },
    );
  }

  /// パフォーマンス関連の警告を報告
  /// 
  /// 性能問題や遅延を報告
  static Future<void> reportPerformanceIssue(
    String operation,
    Duration duration,
    Duration threshold, {
    Map<String, dynamic>? additionalData,
  }) async {
    await reportError(
      'Performance Issue: $operation took ${duration.inMilliseconds}ms (threshold: ${threshold.inMilliseconds}ms)',
      StackTrace.current,
      reason: 'Performance Issue: $operation',
      customData: {
        'operation': operation,
        'duration_ms': duration.inMilliseconds,
        'threshold_ms': threshold.inMilliseconds,
        'error_type': 'performance_issue',
        ...?additionalData,
      },
      fatal: false,
    );
  }

  /// ユーザーアクションの失敗を報告
  /// 
  /// ユーザーの操作が期待通りに動作しなかった場合
  static Future<void> reportUserActionFailure(
    String action,
    String context,
    dynamic error,
    StackTrace? stackTrace,
  ) async {
    await reportError(
      error,
      stackTrace,
      reason: 'User Action Failed: $action in $context',
      customData: {
        'user_action': action,
        'action_context': context,
        'error_type': 'user_action_failure',
      },
    );
  }

  /// カスタムログメッセージを追加
  /// 
  /// デバッグ用の追加情報をCrashlyticsに記録
  static Future<void> addCustomLog(String message) async {
    try {
      if (!kDebugMode) {
        await FirebaseCrashlytics.instance.log(message);
      } else {
        print('📝 Custom Log (Debug Mode): $message');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to add custom log: $e');
      }
    }
  }

  /// ユーザー情報を設定
  /// 
  /// クラッシュレポートにユーザー識別情報を含める
  static Future<void> setUserInfo({
    String? userId,
    String? email,
    Map<String, String>? customKeys,
  }) async {
    try {
      if (!kDebugMode) {
        if (userId != null) {
          await FirebaseCrashlytics.instance.setUserIdentifier(userId);
        }

        if (customKeys != null) {
          for (final entry in customKeys.entries) {
            await FirebaseCrashlytics.instance.setCustomKey(
              entry.key, 
              entry.value,
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to set user info: $e');
      }
    }
  }

  /// 手動でクラッシュをテスト
  /// 
  /// 開発中にCrashlyticsの動作確認用
  static Future<void> testCrash() async {
    if (kDebugMode) {
      print('🧪 Test crash triggered (Debug Mode - not sent to Crashlytics)');
      return;
    }
    
    await FirebaseCrashlytics.instance.crash();
  }

  /// 非致命的例外をテスト
  /// 
  /// 開発中にエラーレポートの動作確認用
  static Future<void> testNonFatalException() async {
    await reportError(
      Exception('Test non-fatal exception'),
      StackTrace.current,
      reason: 'Testing error reporting functionality',
      customData: {
        'is_test': true,
        'test_type': 'non_fatal_exception',
      },
    );
  }
}

/// エラーレポート用の拡張メソッド
extension ErrorReporting on Future {
  /// Future にエラーレポート機能を追加
  Future<T> withErrorReporting<T>({
    String? operation,
    Map<String, dynamic>? customData,
  }) async {
    try {
      return await this;
    } catch (error, stackTrace) {
      await ErrorReporter.reportError(
        error,
        stackTrace,
        reason: operation ?? 'Future operation failed',
        customData: customData,
      );
      rethrow;
    }
  }
}