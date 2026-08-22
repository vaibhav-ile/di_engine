import 'package:di_manager/di_core.dart';
import 'package:flutter_test/flutter_test.dart';

class ApiClient {}

void main() {
  group('Lazy Singleton', () {
    test('is not created until resolved', () {
      final container = DIContainer();

      var created = false;

      container.registerLazySingleton<ApiClient>(() {
        created = true;

        return ApiClient();
      });

      expect(created, isFalse);

      container.resolve<ApiClient>();

      expect(created, isTrue);
    });

    test('returns same instance', () {
      final container = DIContainer();

      container.registerLazySingleton<ApiClient>(() => ApiClient());

      final first = container.resolve<ApiClient>();
      final second = container.resolve<ApiClient>();

      expect(identical(first, second), isTrue);
    });
  });
}
