import 'package:di_engine/di_engine.dart';
import 'package:di_engine/src/registration_type.dart';
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

    test('getRegistrationType returns registered type', () {
      final container = DIContainer();

      container.registerSingleton<ApiClient>(ApiClient());

      expect(
        container.getRegistrationType<ApiClient>(),
        RegistrationType.singleton,
      );
    });

    test('getRegistrationType returns null when not registered', () {
      final container = DIContainer();

      expect(container.getRegistrationType<ApiClient>(), isNull);
    });

    test('isDisposed is false initially', () {
      final container = DIContainer();

      expect(container.isDisposed, isFalse);
    });

    test('isDisposed becomes true after dispose', () {
      final container = DIContainer();

      container.dispose();

      expect(container.isDisposed, isTrue);
    });

    test('isRegistered returns false after dispose', () {
      final container = DIContainer();

      container.registerSingleton<ApiClient>(ApiClient());

      container.dispose();

      expect(container.isRegistered<ApiClient>(), isFalse);
    });

    test('resolve throws after dispose', () {
      final container = DIContainer();

      container.registerSingleton<ApiClient>(ApiClient());

      container.dispose();

      expect(() => container.resolve<ApiClient>(), throwsA(isA<StateError>()));
    });

    test('register throws after dispose', () {
      final container = DIContainer();

      container.dispose();

      expect(
        () => container.registerSingleton<ApiClient>(ApiClient()),
        throwsA(isA<StateError>()),
      );
    });

    test('unregister removes registration', () {
      final container = DIContainer();

      container.registerSingleton<ApiClient>(ApiClient());

      expect(container.isRegistered<ApiClient>(), isTrue);

      container.unregister<ApiClient>();

      expect(container.isRegistered<ApiClient>(), isFalse);
    });

    test('unregister of missing dependency does nothing', () {
      final container = DIContainer();

      expect(() => container.unregister<ApiClient>(), returnsNormally);
    });
  });
}
