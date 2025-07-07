import 'package:flutter_test/flutter_test.dart';
import 'package:taikichu_app/services/countdown_search_service.dart';

void main() {
  group('CountdownSearchService Tests', () {
    test('service should be available', () {
      // Simple test to ensure the service is available
      expect(CountdownSearchService, isNotNull);
      print('CountdownSearchService is available');
    });

    test('getPopularCategories should return default categories', () async {
      // Test that the service returns default categories when no data is available
      final categories = await CountdownSearchService.getPopularCategories();
      expect(categories.isNotEmpty, true);
      print('Default categories: $categories');
    });
  });
}