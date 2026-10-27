import 'package:di_engine/di_engine.dart' hide test;
import 'package:test/test.dart';

class A {}

class B {}

void main() {
  test('nested dispose calls invoke each disposer once', () {
    final container = DIContainer();
    var calls = 0;
    container.registerSingleton<A>(
      A(),
      dispose: (_) {
        calls++;
        container.dispose();
      },
    );
    container.dispose();
    expect(calls, 1);
    expect(container.isDisposed, isTrue);
  });

  for (final reset in [false, true]) {
    test('cleanup rejects mutations and still finishes (reset: $reset)', () {
      final container = DIContainer();
      var disposed = false;
      container.registerSingleton<A>(A(), dispose: (_) => disposed = true);
      container.registerSingleton<B>(
        B(),
        dispose: (_) {
          expect(() => container.registerSingleton<int>(1), throwsStateError);
          expect(container.reset, throwsStateError);
          expect(() => container.unregister<A>(), throwsStateError);
          expect(() => container.resolve<A>(), throwsStateError);
        },
      );
      reset ? container.reset() : container.dispose();
      expect(disposed, isTrue);
      expect(container.isDisposed, !reset);
      expect(container.isRegistered<int>(), isFalse);
    });
  }

  test('factories cannot dispose or mutate the container while resolving', () {
    final container = DIContainer();
    container.registerLazySingleton<A>(() {
      expect(container.dispose, throwsStateError);
      expect(container.reset, throwsStateError);
      expect(() => container.unregister<A>(), throwsStateError);
      expect(() => container.registerSingleton<B>(B()), throwsStateError);
      return A();
    });
    expect(container.resolve<A>(), isA<A>());
    expect(container.isDisposed, isFalse);
    container.dispose();
  });

  test('circular dependency exception contains the resolution path', () {
    final container = DIContainer();
    container.registerLazySingleton<A>(() {
      container.resolve<B>();
      return A();
    });
    container.registerFactory<B>(() {
      container.resolve<A>();
      return B();
    });
    expect(
      () => container.resolve<A>(),
      throwsA(
        isA<CircularDependencyException>().having((e) => e.path, 'path', [
          A,
          B,
          A,
        ]),
      ),
    );
    // Failure must unwind the resolution stack so the container remains mutable.
    container.unregister<B>();
    container.registerSingleton<B>(B());
    expect(container.resolve<A>(), isA<A>());
  });

  test('failed lazy factory can be retried', () {
    final container = DIContainer();
    var attempts = 0;
    container.registerLazySingleton<A>(() {
      if (++attempts == 1) throw StateError('temporary');
      return A();
    });
    expect(() => container.resolve<A>(), throwsStateError);
    final value = container.resolve<A>();
    expect(identical(value, container.resolve<A>()), isTrue);
    expect(attempts, 2);
  });

  test('all disposal errors retain their original errors and stack traces', () {
    final container = DIContainer();
    final first = StateError('first');
    final second = StateError('second');
    container.registerSingleton<A>(A(), dispose: (_) => throw first);
    container.registerSingleton<B>(B(), dispose: (_) => throw second);
    expect(
      container.dispose,
      throwsA(
        isA<DependencyDisposalException>()
            .having((e) => e.failures.map((f) => f.error).toList(), 'errors', [
              second,
              first,
            ])
            .having(
              (e) =>
                  e.failures.every((f) => f.stackTrace.toString().isNotEmpty),
              'stacks',
              isTrue,
            ),
      ),
    );
    expect(container.isDisposed, isTrue);
  });
}
