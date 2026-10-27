import 'package:di_engine/di_engine.dart' hide test;
import 'package:test/test.dart';

class ReadyService {}

void main() {
  late DIEngine engine;
  setUp(() => engine = DIEngine.asNewInstance());
  tearDown(() async => engine.reset());

  test('tryResolve returns null only for absent registrations', () {
    expect(engine.tryResolve<String>(), isNull);
    engine.registerSingleton<String>('named', instanceName: 'label');
    expect(engine.tryResolve<String>(name: 'label'), 'named');
    expect(engine.tryResolve<String>(), isNull);
    engine.registerFactory<int>(() => throw StateError('factory failure'));
    expect(() => engine.tryResolve<int>(), throwsStateError);
  });

  test('tryResolve forwards runtime parameters for registered factories', () {
    engine.registerFactoryParam<String, String, int>(
      (text, count) => '$text:$count',
      instanceName: 'format',
    );
    expect(
      engine.tryResolve<String>(name: 'format', param1: 'page', param2: 2),
      'page:2',
    );
  });

  test('resolveAsync forwards names and factory parameters', () async {
    engine.registerFactoryParamAsync<String, String, int>(
      (text, count) async => '$text:$count',
      instanceName: 'format',
    );
    expect(
      await engine.resolveAsync<String>(
        name: 'format',
        param1: 'page',
        param2: 2,
      ),
      'page:2',
    );
  });

  test('a record carries arbitrarily many typed runtime values', () {
    engine.registerFactoryParam<
      String,
      ({String id, int page, bool refresh}),
      void
    >((args, _) => '${args.id}:${args.page}:${args.refresh}');
    expect(
      engine.resolve<String>(param1: (id: 'u1', page: 2, refresh: true)),
      'u1:2:true',
    );
  });

  test('temporary scopes restore parents and await cleanup', () async {
    engine.registerSingleton<String>('parent');
    var disposed = false;
    final result = await engine.runInScope(
      'request',
      (scoped) async {
        expect(scoped.resolve<String>(), 'child');
        return 42;
      },
      configure: (scoped) {
        scoped.registerSingleton<String>(
          'child',
          dispose: (_) async {
            await Future<void>.delayed(Duration.zero);
            disposed = true;
          },
        );
      },
    );
    expect(result, 42);
    expect(disposed, isTrue);
    expect(engine.hasScope('request'), isFalse);
    expect(engine.resolve<String>(), 'parent');
  });

  test('body failure still disposes a temporary scope', () async {
    final error = StateError('body');
    var disposed = false;
    await expectLater(
      engine.runInScope<void>(
        'request',
        (scoped) => throw error,
        configure: (scoped) => scoped.registerSingleton<String>(
          'child',
          dispose: (_) => disposed = true,
        ),
      ),
      throwsA(same(error)),
    );
    expect(disposed, isTrue);
    expect(engine.hasScope('request'), isFalse);
  });

  test('configuration failure still removes a temporary scope', () async {
    await expectLater(
      engine.runInScope<void>(
        'request',
        (_) {},
        configure: (_) => throw StateError('configuration'),
      ),
      throwsStateError,
    );
    expect(engine.hasScope('request'), isFalse);
  });

  test(
    'duplicate scope names fail without disturbing the existing scope',
    () async {
      engine.pushNewScope(scopeName: 'existing');
      await expectLater(
        engine.runInScope<void>('existing', (_) {}),
        throwsStateError,
      );
      expect(engine.hasScope('existing'), isTrue);
      await engine.popScope();
    },
  );

  test('body and cleanup failures are both preserved', () async {
    final bodyError = StateError('body');
    final cleanupError = StateError('cleanup');
    await expectLater(
      engine.runInScope<void>(
        'request',
        (_) => throw bodyError,
        configure: (scoped) => scoped.registerSingleton<String>(
          'child',
          dispose: (_) => throw cleanupError,
        ),
      ),
      throwsA(
        isA<ScopeRunException>()
            .having((e) => e.bodyError, 'body', same(bodyError))
            .having(
              (e) => (e.cleanupError as DependencyDisposalException)
                  .failures
                  .single
                  .error,
              'cleanup',
              same(cleanupError),
            ),
      ),
    );
    expect(engine.hasScope('request'), isFalse);
  });

  test('manual readiness signaling remains available', () async {
    final service = ReadyService();
    engine.registerSingleton<ReadyService>(service, signalsReady: true);
    expect(engine.allReadySync(), isFalse);
    engine.signalReady(service);
    await engine.allReady(timeout: const Duration(seconds: 1));
    expect(engine.allReadySync(), isTrue);
  });
}
