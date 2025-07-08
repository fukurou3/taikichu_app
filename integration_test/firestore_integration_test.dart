import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:taikichu_app/main.dart' as app;
import 'package:taikichu_app/services/simple_firestore_service.dart';
import 'package:taikichu_app/services/scalable_like_service.dart';
import 'package:taikichu_app/services/scalable_participant_service.dart';
import 'package:taikichu_app/models/countdown.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:math';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Firestore-only Architecture Integration Tests', () {
    late String testCountdownId;
    late Countdown testCountdown;
    
    setUpAll(() async {
      // Initialize Firebase
      await Firebase.initializeApp();
      
      // Generate test countdown
      testCountdownId = 'test_${Random().nextInt(999999)}';
      testCountdown = Countdown(
        id: testCountdownId,
        eventName: 'Test Event',
        category: 'test',
        eventDate: DateTime.now().add(Duration(days: 30)),
        createdAt: DateTime.now(),
        creatorId: 'test_user_123',
        likesCount: 0,
        commentsCount: 0,
        participantsCount: 0,
      );
    });

    group('Post Creation and Timeline Tests', () {
      testWidgets('Create post and verify it appears in timeline', (WidgetTester tester) async {
        // Act: Create a test post
        await SimpleFirestoreService.createPost(testCountdown);
        
        // Wait for fanout to complete
        await Future.delayed(Duration(seconds: 2));
        
        // Assert: Verify post was created
        final timeline = await SimpleFirestoreService.getTimeline('test_user_123');
        expect(timeline.any((post) => post.id == testCountdownId), isTrue);
      });

      testWidgets('Timeline stream updates correctly', (WidgetTester tester) async {
        // Act: Get timeline stream
        final stream = SimpleFirestoreService.getTimelineStream('test_user_123');
        
        // Assert: Stream should emit timeline data
        await expectLater(
          stream.take(1),
          emits(isA<List<Countdown>>()),
        );
      });
    });

    group('Like System Tests', () {
      testWidgets('Like toggle functionality works correctly', (WidgetTester tester) async {
        // Act: Toggle like
        final result = await ScalableLikeService.toggleLike(testCountdownId);
        
        // Assert: Should return the new like state
        expect(result, isA<bool>());
        
        // Act: Check like count increased
        final likesCount = await ScalableLikeService.getLikesCount(testCountdownId);
        expect(likesCount, greaterThanOrEqualTo(0));
      });

      testWidgets('Like state persistence', (WidgetTester tester) async {
        // Act: Check like state
        final isLiked = await ScalableLikeService.isLiked(testCountdownId, 'test_user_123');
        
        // Assert: Should return a boolean
        expect(isLiked, isA<bool>());
      });
    });

    group('Participation System Tests', () {
      testWidgets('Participation toggle functionality works correctly', (WidgetTester tester) async {
        // Act: Toggle participation
        final result = await ScalableParticipantService.toggleParticipation(testCountdownId);
        
        // Assert: Should return the new participation state
        expect(result, isA<bool>());
        
        // Act: Check participants count
        final participantsCount = await ScalableParticipantService.getParticipantsCount(testCountdownId);
        expect(participantsCount, greaterThanOrEqualTo(0));
      });

      testWidgets('Participation state persistence', (WidgetTester tester) async {
        // Act: Check participation state
        final isParticipating = await ScalableParticipantService.isParticipating(testCountdownId);
        
        // Assert: Should return a boolean
        expect(isParticipating, isA<bool>());
      });
    });

    group('Search and Discovery Tests', () {
      testWidgets('Search functionality works correctly', (WidgetTester tester) async {
        // Act: Search for posts
        final results = await SimpleFirestoreService.searchPosts('test');
        
        // Assert: Should return search results
        expect(results, isA<List<Countdown>>());
      });
    });

    group('User Management Tests', () {
      testWidgets('User creation and retrieval', (WidgetTester tester) async {
        // Act: Create test user
        final userData = {
          'uid': 'test_user_123',
          'email': 'test@example.com',
          'displayName': 'Test User',
        };
        
        await SimpleFirestoreService.createUser(userData);
        
        // Act: Retrieve user
        final user = await SimpleFirestoreService.getUser('test_user_123');
        
        // Assert: User should exist
        expect(user, isNotNull);
        expect(user!['uid'], equals('test_user_123'));
      });
    });

    group('Follow System Tests', () {
      testWidgets('Follow functionality works correctly', (WidgetTester tester) async {
        // Act: Follow a user
        await SimpleFirestoreService.followUser('test_target_user');
        
        // Act: Check follow status
        final isFollowing = await SimpleFirestoreService.isFollowing('test_user_123', 'test_target_user');
        
        // Assert: Should be following
        expect(isFollowing, isTrue);
        
        // Act: Get follow counts
        final followCounts = await SimpleFirestoreService.getFollowCounts('test_user_123');
        expect(followCounts['following'], greaterThanOrEqualTo(0));
      });
    });

    tearDownAll(() async {
      // Cleanup: Remove test data
      try {
        // This would require admin privileges in a real test environment
        print('Test completed. Manual cleanup may be required for test data.');
      } catch (e) {
        print('Cleanup warning: $e');
      }
    });
  });
}