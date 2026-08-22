import 'package:di_manager/di_core.dart';
import 'package:flutter_test/flutter_test.dart';

class UserController {}

void main() {
  group('Factory', () {
    test('creates new instance every time', () {
      final container = DIContainer();

      container.registerFactory<UserController>(() => UserController());

      final first = container.resolve<UserController>();
      final second = container.resolve<UserController>();

      expect(identical(first, second), isFalse);
    });
  });
}
