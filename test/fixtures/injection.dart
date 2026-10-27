import 'dart:async';

import 'package:di_engine/di_engine.dart';
import 'micro_package/injection.module.dart';
import 'named_services.dart' as named_services;

@InjectableInit(
  initializerName: 'configure',
  preferRelativeImports: true,
  generateForDir: ['test/fixtures'],
  externalPackageModulesBefore: [
    ExternalModule(DiEngineTestModulePackageModule),
  ],
)
void configureDependencies() {}

abstract interface class Logger {}

@LazySingleton(as: Logger, env: [Environment.prod])
class ProductionLogger implements Logger {}

@LazySingleton(as: Logger, env: [Environment.test])
class TestLogger implements Logger {}

@lazySingleton
class ApiClient {
  final Logger logger;
  final String baseUrl;
  bool closed = false;

  ApiClient(this.logger, {@Named('baseUrl') required this.baseUrl});

  @disposeMethod
  Future<void> close() async {
    closed = true;
  }
}

@injectable
class UserController {
  final ApiClient api;
  final String userId;
  final int page;

  UserController(
    this.api,
    @factoryParam this.userId, {
    @factoryParam required this.page,
  });
}

@injectable
class NamedConstructor {
  final ApiClient api;

  @factoryMethod
  NamedConstructor.create(this.api);
}

@injectable
class AsyncService {
  final ApiClient api;

  AsyncService._(this.api);

  @factoryMethod
  static Future<AsyncService> create(ApiClient api) async =>
      AsyncService._(api);
}

@singleton
class AsyncDatabase {
  AsyncDatabase._();

  @factoryMethod
  static Future<AsyncDatabase> create() async => AsyncDatabase._();
}

@singleton
class InitializedService {
  bool initialized = false;

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    initialized = true;
  }
}

@Injectable(cache: true)
class CachedService {}

abstract interface class Cache {}

@named
@LazySingleton(as: Cache)
class MemoryCache implements Cache {}

@injectable
class CacheConsumer {
  final Cache cache;
  CacheConsumer(@Named.from(MemoryCache) this.cache);
}

@module
abstract class AppModule {
  @Named('baseUrl')
  String get baseUrl => 'https://example.test';

  @preResolve
  @singleton
  Future<Uri> get endpoint async => Uri.parse('https://example.test');

  Duration timeout(@Named('baseUrl') String url) =>
      Duration(seconds: url.length);

  RegExp pattern(@factoryParam String source) => RegExp(source);
}

@Scope('session')
@lazySingleton
class SessionService {
  final ApiClient api;
  bool closed = false;
  SessionService(this.api);

  @disposeMethod
  void close() => closed = true;
}

// Intentionally unannotated: registered by di_engine.json's class name convention.
class ConventionService {}

final initializationOrder = <String>[];

@Order(-1)
@singleton
class FirstService {
  FirstService() {
    initializationOrder.add('first');
  }
}

@Order(1)
@singleton
class LastService {
  LastService() {
    initializationOrder.add('last');
  }
}

typedef RequestArgs = ({String userId, int page, bool refresh});

@injectable
class RecordController {
  final ApiClient api;
  final RequestArgs args;
  RecordController(this.api, @factoryParam this.args);
}

@singleton
class PreResolvedService {
  final Uri endpoint;
  PreResolvedService._(this.endpoint);

  @FactoryMethod(preResolve: true)
  static Future<PreResolvedService> create(Uri endpoint) async =>
      PreResolvedService._(endpoint);
}

@injectable
class SyncInitializedService {
  bool initialized = false;

  @postConstruct
  void initialize() => initialized = true;
}

@LazySingleton(dispose: closeResource)
class Resource {
  bool closed = false;
}

Future<void> closeResource(Resource resource) async {
  resource.closed = true;
}

@injectable
class DirectRecordController {
  final ({String id, int page}) args;
  DirectRecordController(@factoryParam this.args);
}

@injectable
class PrefixedNameConsumer {
  final named_services.NamedLogger logger;
  PrefixedNameConsumer(@Named.from(named_services.FileLogger) this.logger);
}

enum Status { idle, ready }

@injectable
class OptionalStatusConsumer {
  final Status status;
  OptionalStatusConsumer({this.status = Status.idle});
}

@module
abstract class EscapedNamesModule {
  @Named('first\nsecond')
  int get newline => 7;

  @Named('\u0041\x42')
  int get unicode => 8;
}

Completer<PendingScopedService>? scopedStartupGate;

@Scope('failedStartup')
@singleton
class PendingScopedService {
  bool closed = false;

  @factoryMethod
  static Future<PendingScopedService> create() => scopedStartupGate!.future;

  @disposeMethod
  void close() => closed = true;
}

@module
abstract class FailedStartupModule {
  @Scope('failedStartup')
  @Order(1)
  @singleton
  @preResolve
  Future<int> get failure async => throw StateError('startup failed');
}
