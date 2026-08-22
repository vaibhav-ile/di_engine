import 'package:di_manager/di_core.dart';
import 'package:flutter_test/flutter_test.dart';

class ApiClient {}

void main() {
  group('Singleton', () {
    test('returns the same instance', () {
      final container = DIContainer();

      final api = ApiClient();

      container.registerSingleton<ApiClient>(api);

      final first = container.resolve<ApiClient>();
      final second = container.resolve<ApiClient>();

      expect(identical(first, second), isTrue);
      expect(identical(first, api), isTrue);
    });
  });
}
