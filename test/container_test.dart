import 'package:di_manager/di_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class ApiClient {}

class UserRepository {
  final ApiClient api;

  UserRepository(this.api);
}

void main() {
  group('Container', () {
    test('resolves dependencies', () {
      final container = DIContainer();

      container.registerSingleton<ApiClient>(ApiClient());

      container.registerLazySingleton<UserRepository>(
        () => UserRepository(container.resolve<ApiClient>()),
      );

      final repository = container.resolve<UserRepository>();

      expect(repository.api, isA<ApiClient>());
    });

    test('throws when dependency is not registered', () {
      final container = DIContainer();

      expect(
        () => container.resolve<ApiClient>(),
        throwsA(isA<DependencyNotRegisteredException>()),
      );
    });

    test('throws when dependency is registered twice', () {
      final container = DIContainer();

      container.registerSingleton<ApiClient>(ApiClient());

      expect(
        () => container.registerSingleton<ApiClient>(ApiClient()),
        throwsA(isA<DependencyAlreadyRegisteredException>()),
      );
    });

    test('isRegistered works', () {
      final container = DIContainer();

      expect(container.isRegistered<ApiClient>(), isFalse);

      container.registerSingleton<ApiClient>(ApiClient());

      expect(container.isRegistered<ApiClient>(), isTrue);
    });
  });
}
