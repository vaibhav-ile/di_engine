# di_engine

Independent dependency injection for Dart and Flutter. The runtime, annotations,
and constructor generator use only Dart SDK libraries. There are **no runtime
package dependencies** and no external generator or build runner to install.
`test` and `lints` are development tools for this repository only.

## Choose an approach

| Approach | Use it for | Generation required? | Runnable example |
| --- | --- | --- | --- |
| Manual `DIContainer` | Explicit sync registrations and simple lifecycles | No | [Manual registration](example/example.dart) |
| Annotation-driven `DIEngine` | Automatically wiring constructor dependencies | Yes, after adding or changing injectable signatures | [Constructor injection](example/annotated/main.dart) |
| Manual `DIEngine` | Explicit registration with async factories, scopes, or runtime arguments | No | See “Manual DIEngine” below |

## Constructor injection

Add the package:

```yaml
dependencies:
  di_engine: ^2.0.0
```

Create `lib/injection.dart`:

```dart
import 'package:di_engine/di_engine.dart';

@lazySingleton
class ApiClient {}

@injectable
class UserRepository {
  final ApiClient api;
  UserRepository(this.api);
}

@injectable
class UserController {
  final UserRepository repository;
  final String userId;

  UserController(this.repository, @factoryParam this.userId);
}

@InjectableInit()
void configureDependencies() {}
```

Generate registrations:

```sh
dart run di_engine:generate --entrypoint lib/injection.dart
```

Initialize and resolve from your application:

```dart
import 'package:di_engine/di_engine.dart';
import 'injection.dart';
import 'injection.config.dart';

Future<void> main() async {
  final engine = DIEngine();
  await engine.init();

  final controller = engine.resolve<UserController>(param1: 'user-123');
  print(controller.userId);

  await engine.dispose();
}
```

Constructor dependencies, including required named arguments, are supplied by
the generated code. Use `@factoryParam` for values supplied at resolution time.
Two runtime argument slots are available; a typed record or value object can
carry additional values in one slot.

The generator reads source signatures without executing application code or
using reflection. Its output is ordinary Dart and can be compiled for Flutter,
web, server, and CLI applications. The generator itself runs on the Dart VM.

## Native features

| Feature | API |
| --- | --- |
| Transient constructor injection | `@injectable` |
| Eager / lazy owned instances | `@singleton`, `@lazySingleton` |
| Strongly cached, caller-owned factories | `@Injectable(cache: true)` |
| Runtime constructor parameters | `@factoryParam`, `param1`, `param2` |
| Interface bindings | `@Injectable(as: Interface)` |
| Named dependencies / auto names | `@Named('tag')`, `@named`, `@Named.from(Type)` |
| Environments / custom filters | `@Environment`, `env`, `EnvironmentFilter` |
| Third-party type providers | `@module` getters and methods |
| Named constructors / static creators | `@factoryMethod` |
| Async factories and singletons | `Future<T>` creators, `resolveAsync<T>()` |
| Startup pre-resolution | `@preResolve`, `preResolve: true` |
| Initialization / disposal hooks | `@postConstruct`, `@disposeMethod` |
| Explicit readiness | `signalsReady`, `signalReady`, `allReady` |
| Scopes / temporary overrides | `@Scope`, generated scope initializers, `runInScope` |
| Modules across packages | `@InjectableInit.microPackage()`, `DIModule`, `ExternalModule` |
| Convention registration | CLI / JSON class and filename regexes |
| Dependency order and priority | generated graph order, `@Order` |
| Multiple implementations | `allowMultipleRegistrations`, `getAll<T>()` |
| Optional generated helpers | constructor callbacks, accessors, function output |
| Nullable instances | supported by the native runtime |
| Cycle diagnostics | generation-time and sync/async runtime checks |
| Cleanup failures | reverse-order cleanup with aggregated failures |

These are di_engine's own implementations and annotations. They are **not**
wrappers or drop-in replacements for another package's complete API.
See [features and generator limits](doc/features.md).

## Manual registration without generation

### DIContainer

Create a container and register dependencies explicitly. Constructor parameters
are supplied by your factory callbacks; annotations and generation are not needed.

```dart
import 'package:di_engine/di_engine.dart';

class ApiClient {}

class UserRepository {
  final ApiClient api;
  UserRepository(this.api);
}

void main() {
  final container = DIContainer();
  container.registerSingleton<ApiClient>(ApiClient());
  container.registerLazySingleton<UserRepository>(
    () => UserRepository(container.resolve<ApiClient>()),
  );

  final repository = container.resolve<UserRepository>();
  print(repository.api);

  container.dispose();
}
```

`registerSingleton` reuses a provided instance. `registerLazySingleton` calls its
factory once on first resolution. `registerFactory` calls its factory for each
resolution. `DIContainer` cleanup is synchronous.

Run the [complete manual example](example/example.dart):

```sh
dart run example/example.dart
```

### Manual DIEngine

For async creation/cleanup, scopes, or parameters passed at resolution time,
register with `DIEngine` manually. It also works without annotations or generation.
Using the classes from the constructor-injection example:


```dart
final engine = DIEngine();
engine.registerSingletonFactory<ApiClient>(ApiClient.new);
engine.registerLazySingleton<UserRepository>(
  () => UserRepository(engine.resolve<ApiClient>()),
);
engine.registerFactoryParam<UserController, String, void>(
  (userId, _) => UserController(engine.resolve<UserRepository>(), userId),
);
final controller = engine.resolve<UserController>(param1: 'user-123');
await engine.dispose();
```

`resolveAsync`, `tryResolve`, named registrations, async factories, and nullable
values use this same registry. `get`, `getAsync`, and callable-engine syntax are
convenience aliases.

`DIContainer` remains available through `package:di_engine/di_engine.dart` for
existing synchronous applications. It keeps its separate, original registry and
synchronous cleanup contract. See the [manual container example](example/example.dart).

## Sharing dependencies across files

Create one container/engine in `di.dart`, initialize it once at startup, and
import that same instance from application boundaries such as screens or
controllers. Keep services and repositories using constructor injection.
Do not create a new container in each file.

Two complete examples show this structure, with separate service, repository,
configuration, feature, and entry-point files:

| Approach | Shared instance | Example |
| --- | --- | --- |
| Manual registration | `final container = DIContainer()` | [Manual shared container](example/shared_manual/main.dart) |
| Generated registration | `final engine = DIEngine()` | [Generated shared engine](example/shared_generated/main.dart) |

Run them from the repository root:

```sh
dart run example/shared_manual/main.dart
dart run di_engine:generate --entrypoint example/shared_generated/di.dart
dart run example/shared_generated/main.dart
```

Both resolve repositories from `main.dart` and `features/profile_screen.dart`,
verify that the repositories share the same lazy singleton `ApiClient`, and
dispose that client when the application finishes. The manual example needs
no generation; the generated example awaits `initializeDependencies()` before
resolving registered classes.

## Lifecycles

Singletons and resolved lazy singletons are container-owned. Use a disposal
callback, `Disposable`, or `AsyncDisposable` for cleanup. Await native engine
`reset`, `dispose`, `unregister`, and scope removal. Factory and cached-factory
results are caller-owned.

Cached factories retain their last instance strongly until invalidation or
scope removal. Call `resetCachedFactory<T>()` to invalidate one. This behavior is
explicit and does not depend on garbage collection.

`dispose()` closes the engine. `reset()` releases instances and makes it reusable.
Cleanup attempts every owned disposer, then reports `DependencyDisposalException`
with all failures. Registrations/scopes are removed even when cleanup fails.
Creation or cleanup callbacks cannot change registration lifetimes.

Temporary scoped overrides always attempt cleanup:

```dart
final id = await engine.runInScope('request', (scoped) async {
  return scoped.resolve<UserController>(param1: 'user-123').userId;
}, configure: (scoped) {
  scoped.registerSingleton<ApiClient>(ApiClient());
});
```

When the body and cleanup both fail, `ScopeRunException` retains both errors and
stack traces. Scopes belong to an engine; do not manipulate them concurrently or
leave extra scopes open inside `runInScope`.

## Generator commands

```sh
# Discover annotated initializers under lib/:
dart run di_engine:generate
# Explicit input, continuous generation, or CI freshness checks:
dart run di_engine:generate --entrypoint lib/injection.dart --watch
dart run di_engine:generate --entrypoint lib/injection.dart --check
# Multiple targets, including external modules before their consumers:
dart run di_engine:generate --config di_engine.json
```

Run the [annotation-based example](example/annotated/main.dart) from this repository:

```sh
dart run di_engine:generate --config di_engine.json
dart run example/annotated/main.dart
```

During development, `--watch` regenerates registrations automatically when source
inputs change. New injectable classes and constructor signature changes require
regeneration; manual registrations never do.

Generated initializers are always async; await them. Their default method name
is `init`, configurable through `initializerName`.

## Development

Requires Dart 3.12 or newer. The Flutter SDK is not required.

```sh
dart pub get
dart run di_engine:generate --config di_engine.json
dart run di_engine:generate --config di_engine.json --check
dart format --output=none --set-exit-if-changed lib bin test example tool
dart analyze
dart test
dart run example/annotated/main.dart
dart run tool/verify_independent.dart
```

The independence check creates a consumer with an empty pub cache, resolves
offline, verifies there are no transitive runtime dependencies, generates code,
and runs constructor injection. Generated fixtures are checked into the repository.

## License

[MIT](LICENSE).
