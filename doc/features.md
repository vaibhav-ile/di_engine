# Native injection and generation

Everything described here is implemented by di_engine itself. Runtime libraries
import only Dart SDK libraries and other di_engine files. Generation uses an
SDK-only lexical signature reader and formatter. No reflection, third-party
parser, external DI runtime, or build runner is needed.

## Bindings and environments

```dart
abstract interface class Logger {}

@LazySingleton(as: Logger, env: [Environment.prod])
class ConsoleLogger implements Logger {}

@LazySingleton(as: Logger, env: [Environment.test])
class FakeLogger implements Logger {}

@injectable
class Repository {
  final Logger logger;
  final String baseUrl;
  Repository(this.logger, {@Named('baseUrl') required this.baseUrl});
}

@module
abstract class Configuration {
  @Named('baseUrl')
  String get baseUrl => 'https://example.com';
}
```

Call `await engine.init(environment: Environment.prod)`. `@Environment('qa')`
supports custom environments. Dependencies without environment keys always match.
Use `SimpleEnvironmentFilter`, `NoEnvOrContainsAny`, `NoEnvOrContainsAll`, or a
custom subclass of `EnvironmentFilter` for filtering.

Use `@named` to name a registration after its implementation class. Inject it
with `@Named.from(Implementation)` or resolve it with `name: 'Implementation'`.
Unqualified names and import-prefixed annotations/types are recognized.

## Creation and ownership

| Lifetime | Creation | Owned | Identity |
| --- | --- | --- | --- |
| Singleton | Initialization | Yes | Reused |
| Lazy singleton | First resolution | Yes | Reused |
| Factory | Every resolution | No | Provider decides |
| Cached factory | First resolution / after invalidation | No | Strongly reused |

Provider callbacks must actually create an instance if a fresh instance is
needed. A pre-resolved factory deliberately returns the value created at startup.
Factories with runtime arguments are transient; cached/owned parameterized
factories are rejected to avoid ambiguous ownership and argument caching.

`@factoryMethod` selects a public named constructor, factory constructor, or
public static creator. `Future<T>` creators use async registration. Async
constructor dependencies propagate async creation to their consumers; resolve
those consumers with `resolveAsync<T>()`.

`@postConstruct` marks one public, parameterless instance initialization method.
An async method can be awaited at startup with `@PostConstruct(preResolve: true)`.
`@preResolve` on a module provider or `@FactoryMethod(preResolve: true)` also
awaits creation before registering the result. Initialization methods return
void/Future<void>; their returned values do not replace the constructed object.

`@disposeMethod` selects one public, parameterless cleanup method on an owned
class. `dispose` on `@Singleton` / `@LazySingleton` accepts a public top-level or
static callback. A registration callback takes precedence over automatic
`AsyncDisposable` or `Disposable` handling. Transient products remain caller-owned.

## Async correctness and readiness

Concurrent resolutions of one lazy async singleton join its pending creation.
Each independent resolution chain has its own cycle path, including across async
awaits. A wait graph also detects cycles between concurrently started services.
Independent callers of `dispose()` await the same cleanup operation. Failed lazy creations can be retried. Eager async failures remain
observable through `allReady`/`resolveAsync`; unregister and re-register to retry.

Use `@Singleton(signalsReady: true)` for externally coordinated startup. Call
`engine.signalReady(instance)` when ready, then await
`engine.allReady(timeout: const Duration(seconds: 10))`.
Lazy registrations do not start merely because `allReady` is called.

Await eager startup with `allReady` before resetting an engine or changing its
scopes. Destructive lifetime changes are rejected while any creation is pending,
including eager work that has been queued but not started.

## Scopes and modules

```dart
@Scope('session')
@lazySingleton
class Session {
  @disposeMethod
  Future<void> close() async {}
}

// After generation:
await engine.initSessionScope();
final session = engine.resolve<Session>();
await engine.popScope();
```

Scoped registrations shadow the same type/name in parent scopes. Scope cleanup
attempts every owned disposer and removes the scope even if cleanup fails.
Generated scope initialization rolls back the new scope on failure. Managed
scopes and rollback wait for in-flight creation to settle before cleanup; factories
must eventually finish or provide their own cancellation/timeout handling.

A generated micro module implements `DIModule.register`. Annotate its source
initializer with `@InjectableInit.microPackage()`, generate its `.module.dart`,
and import that generated module in the consuming initializer:

```dart
@InjectableInit(
  externalPackageModulesBefore: [ExternalModule(FeaturePackageModule)],
  externalPackageModulesAfter: [ExternalModule(OtherPackageModule, scope: 'session')],
  throwOnMissingDependencies: false,
)
void configureDependencies() {}
```

External providers are not inferred from arbitrary module implementation bodies.
Disable strict missing-dependency validation when required dependencies are
supplied externally. Keep duplicate registration checks enabled unless multiple
implementations are intentional. `allowMultipleRegistrations: true` enables the
native multi-registration API; retrieve the implementations with `getAll<T>()`.

## Generator configuration

The root JSON configuration uses explicit, ordered targets:

```json
{
  "targets": [
    {
      "entrypoint": "lib/injection.dart",
      "exclude": ["lib/generated"],
      "classNamePattern": "Service$|Repository$",
      "fileNamePattern": "_controller\\.dart$"
    }
  ]
}
```

Each target may specify `output` and a generated micro `moduleName`. Paths are
relative to the current project's root. Generate modules before their consumers.
Regex conventions register unannotated concrete classes; annotations take
precedence. The repository's `di_engine.json` contains working module, example,
and integration-test targets.

`@InjectableInit` supports `initializerName`, `generateForDir`,
`preferRelativeImports`, `asExtension`, `throwOnMissingDependencies`,
`generateAccessors`, `usesConstructorCallback`, and `allowMultipleRegistrations`.
All initializers return a Future, including configurations containing only sync
providers. Generator errors do not replace an existing output file. `--check`
validates freshness without overwriting output. `--watch` polls input changes.

## Generator limits

The generator reads declaration signatures rather than performing a complete
Dart semantic analysis. Use explicit parameter/field types and direct native
annotations with literal arguments. Custom const annotation aliases, arbitrary
constant-expression evaluation, mixin-provided constructors, extension types,
and generic injectable classes are not supported. A concrete module provider can
register constructed generic types. Use typedefs for function-typed dependencies. Optional defaults must be literals
or public expressions accessible from the generated library; private constants
require a concrete module provider.

Named constructors require `@factoryMethod`. Classes must be public, and
initialization/disposal hooks must be public and parameterless. Abstract module
getters are synthesized using the returned type's unnamed zero-argument
constructor; provide a concrete getter/method for more complex construction.

Conditional imports, part-based injectable discovery, and export show/hide
combinations are not a full analyzer replacement. Keep injectable declarations
in ordinary libraries with unambiguous imports. Run `dart analyze` after
generation: the SDK formatter checks output syntax, while the compiler/analyzer
checks type accessibility, assignability, and constructor validity. A Flutter
project should use its normal Flutter analysis/build checks.

Existing configurations from external generators need migration to this native
API. There is no GetIt/injectable/LeanBuilder adapter or binary compatibility
promise. The original `DIContainer` remains an independent synchronous API.
