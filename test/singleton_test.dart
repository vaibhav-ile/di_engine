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

class ExplicitDisposeService implements Disposable {
  bool disposableCalled = false;

  @override
  void dispose() {
    disposableCalled = true;
  }
}

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

    test('supports null singleton values', () {
      final container = DIContainer();

      container.registerSingleton<String?>(null);

      final value = container.resolve<String?>();

      expect(value, isNull);
    });

    test('disposes singleton implementing Disposable', () {
      final container = DIContainer();

      final service = DisposableService();

      container.registerSingleton<DisposableService>(service);

      container.dispose();

      expect(service.disposed, isTrue);
    });

    test('explicit dispose callback takes precedence over Disposable', () {
      final container = DIContainer();

      final service = ExplicitDisposeService();

      var explicitDisposeCalled = false;

      container.registerSingleton<ExplicitDisposeService>(
        service,
        dispose: (_) {
          explicitDisposeCalled = true;
        },
      );

      container.dispose();

      expect(explicitDisposeCalled, isTrue);
      expect(service.disposableCalled, isFalse);
    });

    test('unregister disposes singleton', () {
      final container = DIContainer();

      final service = DisposableService();

      container.registerSingleton<DisposableService>(service);

      container.unregister<DisposableService>();

      expect(service.disposed, isTrue);
      expect(container.isRegistered<DisposableService>(), isFalse);
    });

    test('unregister does not dispose singleton twice', () {
      final container = DIContainer();

      var disposeCount = 0;

      final service = Object();

      container.registerSingleton<Object>(
        service,
        dispose: (_) {
          disposeCount++;
        },
      );

      container.unregister<Object>();

      container.dispose();

      expect(disposeCount, 1);
    });
  });
}
