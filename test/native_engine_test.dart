import 'dart:async';

import 'package:di_engine/di_engine.dart' hide test;
import 'package:test/test.dart';

class A {}

class B {}

class C {}

class AsyncResource implements AsyncDisposable {
  bool closed = false;
  @override
  Future<void> dispose() async {
    await Future<void>.delayed(Duration.zero);
    closed = true;
  }
}

void main() {
  late DIEngine engine;
  setUp(() => engine = DIEngine());
  tearDown(() async => engine.reset());

  test(
    'concurrent lazy async resolution shares one creation without false cycles',
    () async {
      var calls = 0;
      final gate = Completer<A>();
      engine.registerLazySingletonAsync<A>(() {
        calls++;
        return gate.future;
      });
      final first = engine.resolveAsync<A>();
      final second = engine.resolveAsync<A>();
      gate.complete(A());
      final values = await Future.wait([first, second]);
      expect(values[0], same(values[1]));
      expect(calls, 1);
    },
  );

  test(
    'async cycles fail with a path instead of waiting on their own pending future',
    () async {
      engine.registerLazySingletonAsync<A>(() async {
        await engine.resolveAsync<B>();
        return A();
      });
      engine.registerLazySingletonAsync<B>(() async {
        await engine.resolveAsync<A>();
        return B();
      });
      await expectLater(
        engine.resolveAsync<A>().timeout(const Duration(seconds: 1)),
        throwsA(
          isA<CircularDependencyException>().having((e) => e.path, 'path', [
            A,
            B,
            A,
          ]),
        ),
      );
    },
  );

  test('a lazy async factory can retry after a failure', () async {
    var calls = 0;
    engine.registerLazySingletonAsync<A>(() async {
      if (++calls == 1) throw StateError('temporary');
      return A();
    });
    await expectLater(engine.resolveAsync<A>(), throwsStateError);
    final result = await engine.resolveAsync<A>();
    expect(await engine.resolveAsync<A>(), same(result));
    expect(calls, 2);
  });

  test('queued eager work cannot be orphaned by reset', () async {
    final gate = Completer<A>();
    var released = false;
    engine.registerSingletonAsync<A>(
      () => gate.future,
      dispose: (_) => released = true,
    );
    await expectLater(engine.reset(), throwsStateError);
    gate.complete(A());
    await engine.allReady();
    await engine.reset();
    expect(released, isTrue);
  });

  test('eager initialization failures propagate through allReady', () async {
    engine.registerSingletonAsync<A>(
      () async => throw StateError('connection'),
    );
    await expectLater(engine.allReady(), throwsStateError);
    await engine.reset();
    expect(engine.isRegistered<A>(), isFalse);
  });

  test(
    'factory side effects cannot dispose or unregister their own registry',
    () async {
      engine.registerLazySingletonAsync<A>(() async {
        await expectLater(engine.dispose(), throwsStateError);
        await expectLater(engine.unregister<A>(), throwsStateError);
        expect(() => engine.registerSingleton<B>(B()), throwsStateError);
        return A();
      });
      expect(await engine.resolveAsync<A>(), isA<A>());
    },
  );

  test(
    'sync and async cleanup failures aggregate while all services are attempted',
    () async {
      final order = <String>[];
      final firstError = StateError('a');
      final secondError = StateError('b');
      engine.registerSingleton<A>(
        A(),
        dispose: (_) {
          order.add('a');
          throw firstError;
        },
      );
      engine.registerSingleton<B>(
        B(),
        dispose: (_) async {
          await Future<void>.delayed(Duration.zero);
          order.add('b');
          throw secondError;
        },
      );
      await expectLater(
        engine.reset(),
        throwsA(
          isA<DependencyDisposalException>().having(
            (e) => e.failures.map((f) => f.error).toList(),
            'errors',
            [secondError, firstError],
          ),
        ),
      );
      expect(order, ['b', 'a']);
      expect(engine.isRegistered<A>(), isFalse);
      engine.registerSingleton<A>(A());
    },
  );

  test('native AsyncDisposable is awaited automatically', () async {
    final resource = AsyncResource();
    engine.registerSingleton<AsyncResource>(resource);
    await engine.dispose();
    expect(resource.closed, isTrue);
    expect(engine.isDisposed, isTrue);
    await engine.dispose();
    expect(() => engine.resolve<AsyncResource>(), throwsStateError);
    await engine.reset();
    expect(engine.isDisposed, isFalse);
  });

  test('cached factories are caller-owned and can be invalidated', () async {
    var calls = 0;
    engine.registerCachedFactory<AsyncResource>(() {
      calls++;
      return AsyncResource();
    });
    final first = engine.resolve<AsyncResource>();
    expect(engine.resolve<AsyncResource>(), same(first));
    engine.resetCachedFactory<AsyncResource>();
    final second = engine.resolve<AsyncResource>();
    expect(second, isNot(same(first)));
    expect(calls, 2);
    await engine.reset();
    expect(first.closed, isFalse);
    expect(second.closed, isFalse);
    await first.dispose();
    await second.dispose();
  });

  test(
    'async cached factories share creation and permit explicit invalidation',
    () async {
      var calls = 0;
      engine.registerCachedFactoryAsync<A>(() async {
        calls++;
        return A();
      });
      final first = await engine.resolveAsync<A>();
      expect(await engine.resolveAsync<A>(), same(first));
      engine.resetCachedFactory<A>();
      expect(await engine.resolveAsync<A>(), isNot(same(first)));
      expect(calls, 2);
    },
  );

  test('nullable lazy async instances are cached once', () async {
    var calls = 0;
    engine.registerLazySingletonAsync<String?>(() async {
      calls++;
      return null;
    });
    expect(await engine.resolveAsync<String?>(), isNull);
    expect(await engine.resolveAsync<String?>(), isNull);
    expect(calls, 1);
  });

  test(
    'names, multiple implementations, and scope shadowing share one registry',
    () async {
      engine.enableRegisteringMultipleInstancesOfOneType();
      engine.registerSingleton<String>('a');
      engine.registerSingleton<String>('b');
      engine.registerSingleton<String>('named', instanceName: 'tag');
      expect(engine.getAll<String>(), ['a', 'b', 'named']);
      engine.pushNewScope(scopeName: 'child');
      engine.registerSingleton<String>('child');
      expect(engine.resolve<String>(), 'child');
      expect(engine.resolve<String>(name: 'tag'), 'named');
      expect(engine.getAll<String>(), ['child', 'named']);
      await engine.popScope();
      expect(engine.resolve<String>(), 'b');
    },
  );

  test('cleanup is reentrant-safe and rejects late registrations', () async {
    var calls = 0;
    engine.registerSingleton<A>(
      A(),
      dispose: (_) async {
        calls++;
        await engine.dispose();
        expect(() => engine.registerSingleton<B>(B()), throwsStateError);
        await expectLater(engine.reset(), throwsStateError);
      },
    );
    await engine.dispose();
    expect(calls, 1);
  });
  test(
    'concurrently started async services detect a shared wait cycle',
    () async {
      // Separate root resolutions deliberately have separate Zone paths.
      final local = DIEngine();
      final gate = Completer<void>();
      local.registerLazySingletonAsync<A>(() async {
        await gate.future;
        await local.resolveAsync<B>();
        return A();
      });
      local.registerLazySingletonAsync<B>(() async {
        await gate.future;
        await local.resolveAsync<A>();
        return B();
      });
      final both = Future.wait<Object>([
        local.resolveAsync<A>(),
        local.resolveAsync<B>(),
      ]);
      gate.complete();
      await expectLater(
        both.timeout(const Duration(milliseconds: 200)),
        throwsA(isA<CircularDependencyException>()),
      );
      await local.reset();
    },
  );

  test('concurrent dispose callers all await the same async cleanup', () async {
    final gate = Completer<void>();
    engine.registerSingleton<A>(A(), dispose: (_) => gate.future);
    final first = engine.dispose();
    var secondFinished = false;
    final secondClose = engine.dispose();
    expect(secondClose, same(first));
    final second = secondClose.then((_) => secondFinished = true);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);
    } finally {
      gate.complete();
      await Future.wait([first, second]);
    }
  });

  test('tryResolve obeys the disposed-engine lifecycle guard', () async {
    await engine.dispose();
    expect(() => engine.tryResolve<A>(), throwsStateError);
  });

  test(
    'deferred callbacks do not retain a completed factory resolution path',
    () async {
      final completed = Completer<void>();
      engine.registerFactory<A>(() {
        Future<void>.microtask(() {
          try {
            engine.registerSingleton<B>(B());
            completed.complete();
          } catch (error, stack) {
            completed.completeError(error, stack);
          }
        });
        return A();
      });
      engine.resolve<A>();
      await completed.future;
      expect(engine.resolve<B>(), isA<B>());
    },
  );
  test('wait cycles through transient factories are also detected', () async {
    final local = DIEngine();
    final gate = Completer<void>();
    local.registerLazySingletonAsync<A>(() async {
      await gate.future;
      await local.resolveAsync<B>();
      return A();
    });
    local.registerFactoryAsync<B>(() async {
      await local.resolveAsync<C>();
      return B();
    });
    local.registerLazySingletonAsync<C>(() async {
      await gate.future;
      await local.resolveAsync<A>();
      return C();
    });
    final both = Future.wait<Object>([
      local.resolveAsync<A>(),
      local.resolveAsync<C>(),
    ]);
    gate.complete();
    await expectLater(
      both.timeout(const Duration(seconds: 1)),
      throwsA(isA<CircularDependencyException>()),
    );
    await local.reset();
  });
  test(
    'managed scopes finish pending creation before cleanup after body failure',
    () async {
      final gate = Completer<A>();
      final error = StateError('body failed');
      var disposed = false;
      final result = engine.runInScope<void>(
        'starting',
        (_) => throw error,
        configure: (scoped) => scoped.registerSingletonAsync<A>(
          () => gate.future,
          dispose: (_) => disposed = true,
        ),
      );
      final expectation = expectLater(result, throwsA(same(error)));
      gate.complete(A());
      try {
        await expectation;
        expect(disposed, isTrue);
        expect(engine.hasScope('starting'), isFalse);
      } finally {
        await engine.allReady();
      }
    },
  );
}
