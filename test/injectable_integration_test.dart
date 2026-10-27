import 'dart:async';

import 'package:di_engine/di_engine.dart' hide test;
import 'package:test/test.dart';
import 'fixtures/micro_package/injection.dart';
import 'fixtures/named_services.dart';

import 'fixtures/injection.dart';
import 'fixtures/injection.config.dart';

void main() {
  late DIEngine engine;

  setUp(() async {
    initializationOrder.clear();
    engine = DIEngine.asNewInstance();
    await engine.configure(environment: Environment.test);
    await engine.allReady(timeout: const Duration(seconds: 5));
  });

  tearDown(() async => engine.reset());

  test('injects required named and positional constructor parameters', () {
    final controller = engine.resolve<UserController>(
      param1: 'alice',
      param2: 3,
    );
    expect(controller.userId, 'alice');
    expect(controller.page, 3);
    expect(controller.api.logger, isA<TestLogger>());
    expect(controller.api.baseUrl, 'https://example.test');
    final other = engine.resolve<UserController>(param1: 'bob', param2: 4);
    expect(identical(controller, other), isFalse);
    expect(identical(controller.api, other.api), isTrue);
  });

  test(
    'isolated engines select different environment implementations',
    () async {
      final production = DIEngine.asNewInstance();
      try {
        await production.configure(environment: Environment.prod);
        await production.allReady(timeout: const Duration(seconds: 5));
        expect(production.resolve<Logger>(), isA<ProductionLogger>());
        expect(engine.resolve<Logger>(), isA<TestLogger>());
      } finally {
        await production.reset();
      }
    },
  );

  test('named constructors, type-based names, and cached factories work', () {
    expect(
      engine.resolve<NamedConstructor>().api,
      same(engine.resolve<ApiClient>()),
    );
    expect(engine.resolve<CacheConsumer>().cache, isA<MemoryCache>());
    final cached = engine.resolve<CachedService>();
    expect(engine.resolve<CachedService>(), same(cached));
  });

  test('module getters and methods register third-party types', () {
    expect(engine.resolve<Uri>().host, 'example.test');
    expect(engine.resolve<Duration>().inSeconds, 'https://example.test'.length);
    expect(
      engine.resolve<RegExp>(param1: '^user').hasMatch('user-123'),
      isTrue,
    );
  });

  test(
    'async factories, async singletons, and post construct are usable',
    () async {
      final service = await engine.resolveAsync<AsyncService>();
      expect(service.api, same(engine.resolve<ApiClient>()));
      final database = await engine.resolveAsync<AsyncDatabase>();
      expect(await engine.resolveAsync<AsyncDatabase>(), same(database));
      expect(engine.resolve<InitializedService>().initialized, isTrue);
    },
  );

  test(
    'generated scopes initialize and dispose their owned registrations',
    () async {
      expect(engine.isRegistered<SessionService>(), isFalse);
      await engine.initSessionScope();
      final session = engine.resolve<SessionService>();
      expect(session.api, same(engine.resolve<ApiClient>()));
      await engine.popScope();
      expect(session.closed, isTrue);
      expect(engine.isRegistered<SessionService>(), isFalse);
      expect(engine.isRegistered<ApiClient>(), isTrue);
    },
  );

  test('annotated async disposer is awaited during reset', () async {
    final api = engine.resolve<ApiClient>();
    await engine.reset();
    expect(api.closed, isTrue);
  });

  test('external modules and convention registration are generated', () {
    expect(engine.resolve<ExternalToken>(), isA<ExternalToken>());
    expect(engine.resolve<ConventionService>(), isA<ConventionService>());
  });

  test(
    'typed record constructor arguments support more than two runtime values',
    () {
      final controller = engine.resolve<RecordController>(
        param1: (userId: 'carol', page: 5, refresh: true),
      );
      expect(controller.args, (userId: 'carol', page: 5, refresh: true));
      expect(controller.api, same(engine.resolve<ApiClient>()));
    },
  );

  test('static creators can be pre-resolved and sync hooks run', () {
    expect(engine.resolve<PreResolvedService>().endpoint.host, 'example.test');
    expect(engine.resolve<SyncInitializedService>().initialized, isTrue);
  });

  test('annotation disposal callbacks are awaited', () async {
    final resource = engine.resolve<Resource>();
    await engine.reset();
    expect(resource.closed, isTrue);
  });

  test('manual initialization ordering is honored', () {
    expect(initializationOrder, ['first', 'last']);
  });
  test(
    'direct record types retain field labels in generated factory signatures',
    () {
      final value = engine.resolve<DirectRecordController>(
        param1: (id: 'direct', page: 3),
      );
      expect(value.args, (id: 'direct', page: 3));
    },
  );
  test(
    'prefixed Named.from bindings compile and resolve by implementation name',
    () {
      expect(engine.resolve<PrefixedNameConsumer>().logger, isA<FileLogger>());
    },
  );

  test(
    'optional enum defaults compile and registered overrides take precedence',
    () {
      expect(engine.resolve<OptionalStatusConsumer>().status, Status.idle);
      engine.registerSingleton<Status>(Status.ready);
      expect(engine.resolve<OptionalStatusConsumer>().status, Status.ready);
    },
  );

  test('escaped annotation names match Dart runtime string values', () {
    expect(engine.resolve<int>(name: 'first\nsecond'), 7);
    expect(engine.resolve<int>(name: 'AB'), 8);
  });
  test(
    'generated startup rollback waits for pending scoped resources',
    () async {
      final gate = Completer<PendingScopedService>();
      final resource = PendingScopedService();
      scopedStartupGate = gate;
      var finished = false;
      final initializing = engine.initFailedStartupScope().then<Object?>(
        (_) {
          finished = true;
          return null;
        },
        onError: (Object error) {
          finished = true;
          return error;
        },
      );
      try {
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        gate.complete(resource);
        expect(await initializing, isA<StateError>());
        expect(resource.closed, isTrue);
        expect(engine.hasScope('failedStartup'), isFalse);
      } finally {
        if (!gate.isCompleted) gate.complete(resource);
        await initializing;
        await engine.allReady();
        scopedStartupGate = null;
      }
    },
  );
}
