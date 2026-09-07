import 'package:di_engine/di_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class ApiClient {}

class DisposableService implements Disposable {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}

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

    test('creates instance only once', () {
      final container = DIContainer();

      var creationCount = 0;

      container.registerLazySingleton<ApiClient>(() {
        creationCount++;

        return ApiClient();
      });

      container.resolve<ApiClient>();
      container.resolve<ApiClient>();
      container.resolve<ApiClient>();

      expect(creationCount, 1);
    });

    test('supports null lazy singleton values', () {
      final container = DIContainer();

      var creationCount = 0;

      container.registerLazySingleton<String?>(() {
        creationCount++;

        return null;
      });

      expect(container.resolve<String?>(), isNull);
      expect(container.resolve<String?>(), isNull);

      expect(creationCount, 1);
    });

    test('does not create instance during dispose', () {
      final container = DIContainer();

      var created = false;

      container.registerLazySingleton<ApiClient>(() {
        created = true;

        return ApiClient();
      });

      container.dispose();

      expect(created, isFalse);
    });

    test('disposes created lazy singleton', () {
      final container = DIContainer();

      final service = DisposableService();

      container.registerLazySingleton<DisposableService>(() => service);

      container.resolve<DisposableService>();

      container.dispose();

      expect(service.disposed, isTrue);
    });

    test('does not dispose uncreated lazy singleton', () {
      final container = DIContainer();

      var disposed = false;

      container.registerLazySingleton<Object>(
        () => Object(),
        dispose: (_) {
          disposed = true;
        },
      );

      container.dispose();

      expect(disposed, isFalse);
    });

    test('unregister does not create lazy singleton', () {
      final container = DIContainer();

      var created = false;

      container.registerLazySingleton<ApiClient>(() {
        created = true;

        return ApiClient();
      });

      container.unregister<ApiClient>();

      expect(created, isFalse);
    });
  });
}
