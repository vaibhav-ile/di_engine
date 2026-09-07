# di_engine

A lightweight dependency injection container for Dart and Flutter.

`di_engine` provides a simple and predictable way to register and resolve dependencies using three registration lifetimes:

* **Singleton** — created immediately and reused.
* **Lazy Singleton** — created on first use and reused.
* **Factory** — a new instance is created for every resolution.

The package is designed to stay small, explicit, and easy to understand without annotations, code generation, or complex dependency graphs.

---

## Features

* Singleton registration
* Lazy singleton registration
* Factory registration
* Constructor-based dependency injection
* Nullable dependency support
* Custom disposal callbacks
* `Disposable` interface support
* Automatic lifecycle management for owned dependencies
* Reverse-order disposal
* Disposal failure aggregation
* Dependency registration checks
* Dependency unregistration
* Container reset
* Container lifecycle state
* Works with both Dart and Flutter

---

## Installation

Add `di_engine` to your `pubspec.yaml`:

```yaml
dependencies:
  di_engine: ^1.1.0
```

Then run:

```bash
flutter pub get
```

Import the package:

```dart
import 'package:di_engine/di_engine.dart';
```

---

## Basic Usage

Create a container:

```dart
final container = DIContainer();
```

Register a dependency:

```dart
container.registerSingleton<Database>(
  Database(),
);
```

Resolve it:

```dart
final database = container.resolve<Database>();
```

The same instance is returned every time:

```dart
final first = container.resolve<Database>();
final second = container.resolve<Database>();

print(identical(first, second)); // true
```

---

# Registration Types

`di_engine` supports three registration types.

| Registration   | Creation      | Reused | Owned by Container |
| -------------- | ------------- | ------ | ------------------ |
| Singleton      | Immediately   | Yes    | Yes                |
| Lazy Singleton | First resolve | Yes    | Yes                |
| Factory        | Every resolve | No     | No                 |

---

## Singleton

A singleton is created immediately when it is registered.

```dart
container.registerSingleton<Database>(
  Database(),
);
```

Every resolution returns the same instance:

```dart
final database1 = container.resolve<Database>();
final database2 = container.resolve<Database>();

print(identical(database1, database2)); // true
```

### Lifecycle

The container owns the singleton instance.

When the container is disposed, the singleton is disposed automatically if it supports disposal.

---

## Lazy Singleton

A lazy singleton is created only when it is first resolved.

```dart
container.registerLazySingleton<ApiClient>(
  () => ApiClient(
    container.resolve<Database>(),
  ),
);
```

The factory is not executed during registration:

```dart
container.registerLazySingleton<ApiClient>(
  () {
    print('Creating ApiClient');
    return ApiClient(
      container.resolve<Database>(),
    );
  },
);

print('Registered');

// ApiClient is created here.
final apiClient = container.resolve<ApiClient>();
```

Once created, the same instance is returned:

```dart
final first = container.resolve<ApiClient>();
final second = container.resolve<ApiClient>();

print(identical(first, second)); // true
```

### Lifecycle

The container owns the lazy singleton **only after it has been created**.

If a lazy singleton is never resolved, it will not be created just because the container is disposed.

---

## Factory

A factory creates a new instance every time it is resolved.

```dart
container.registerFactory<UserController>(
  () => UserController(
    container.resolve<ApiClient>(),
  ),
);
```

Each resolution returns a different instance:

```dart
final first = container.resolve<UserController>();
final second = container.resolve<UserController>();

print(identical(first, second)); // false
```

### Lifecycle

Factory instances are transient.

The container does **not** track or dispose factory-created instances.

For this reason, factory registrations do not accept a disposal callback.

If a factory-created object owns resources that require cleanup, the code that creates or owns that object should manage its lifecycle.

---

# Dependency Injection

Dependencies can be resolved inside registration factories.

For example:

```dart
class Database {
  // ...
}

class ApiClient {
  final Database database;

  ApiClient(this.database);
}

class UserController {
  final ApiClient apiClient;

  UserController(this.apiClient);
}
```

Register them:

```dart
final container = DIContainer();

container.registerSingleton<Database>(
  Database(),
);

container.registerLazySingleton<ApiClient>(
  () => ApiClient(
    container.resolve<Database>(),
  ),
);

container.registerFactory<UserController>(
  () => UserController(
    container.resolve<ApiClient>(),
  ),
);
```

Resolve the controller:

```dart
final controller = container.resolve<UserController>();
```

The dependency chain is:

```text
UserController
      ↓
  ApiClient
      ↓
   Database
```

---

# Disposal

`di_engine` supports two ways to dispose owned dependencies.

## `Disposable`

Implement the `Disposable` interface:

```dart
class Database implements Disposable {
  @override
  void dispose() {
    print('Database disposed');
  }
}
```

Register it:

```dart
container.registerSingleton<Database>(
  Database(),
);
```

When the container is disposed:

```dart
container.dispose();
```

`Database.dispose()` is called automatically.

---

## Custom Disposal Callback

A custom disposal callback can be supplied during singleton or lazy singleton registration:

```dart
container.registerSingleton<Database>(
  Database(),
  dispose: (database) {
    database.close();
  },
);
```

The same is supported for lazy singletons:

```dart
container.registerLazySingleton<ApiClient>(
  () => ApiClient(
    container.resolve<Database>(),
  ),
  dispose: (apiClient) {
    apiClient.close();
  },
);
```

### Disposal precedence

If both a custom disposal callback and `Disposable` are available, the custom callback takes precedence.

```dart
container.registerSingleton<Database>(
  Database(),
  dispose: (database) {
    database.close();
  },
);
```

Only the provided callback is executed.

---

# Disposal Order

Dependencies are disposed in **reverse registration order**.

For example:

```dart
container.registerSingleton<Database>(
  Database(),
);

container.registerSingleton<ApiClient>(
  ApiClient(),
);

container.registerSingleton<UserService>(
  UserService(),
);
```

They are disposed in this order:

```text
UserService
    ↓
ApiClient
    ↓
Database
```

This follows a LIFO-style lifecycle model and is useful when later registrations depend on earlier registrations.

---

# Disposal Failures

A failure while disposing one dependency does not prevent other dependencies from being disposed.

For example, if:

```text
UserService  → throws
ApiClient    → succeeds
Database     → succeeds
```

the container still attempts to dispose all three.

After all disposal attempts are complete, `DependencyDisposalException` is thrown containing the individual failures.

```dart
try {
  container.dispose();
} on DependencyDisposalException catch (exception) {
  print(exception);

  for (final failure in exception.failures) {
    print(failure.type);
    print(failure.error);
    print(failure.stackTrace);
  }
}
```

This prevents one faulty disposer from leaving the rest of the container undisposed.

---

# Nullable Dependencies

Nullable dependencies are supported.

For example:

```dart
Database? database;
```

Register a nullable singleton:

```dart
container.registerSingleton<Database?>(
  null,
);
```

Resolve it:

```dart
final database = container.resolve<Database?>();

print(database); // null
```

A nullable lazy singleton is also supported:

```dart
container.registerLazySingleton<Database?>(
  () => null,
);
```

The container uses explicit lifecycle state rather than `null` to determine whether a singleton has been created.

---

# Checking Registration

Use `isRegistered<T>()` to check whether a dependency has been registered:

```dart
if (container.isRegistered<Database>()) {
  final database = container.resolve<Database>();
}
```

For an unregistered dependency:

```dart
print(
  container.isRegistered<Database>(),
); // false
```

`isRegistered<T>()` is safe to call even after the container has been disposed.

---

# Unregistering Dependencies

A dependency can be removed from the container:

```dart
container.unregister<Database>();
```

If the dependency is owned by the container, it is disposed during unregistration.

After unregistration:

```dart
print(
  container.isRegistered<Database>(),
); // false
```

Attempting to resolve it results in:

```text
DependencyNotRegisteredException
```

If disposal fails during unregistration, `DependencyDisposalException` is thrown.

---

# Container Lifecycle

The container has an explicit lifecycle.

## Active

A newly created container is active:

```dart
final container = DIContainer();

print(container.isDisposed); // false
```

Registrations and resolutions are allowed.

---

## Disposed

Dispose the container:

```dart
container.dispose();

print(container.isDisposed); // true
```

After disposal, attempting to register or resolve dependencies throws a `StateError`.

```dart
container.resolve<Database>();
```

is not allowed after disposal.

Calling `dispose()` multiple times is safe:

```dart
container.dispose();
container.dispose();
```

The second call has no effect.

---

# Reset

`reset()` disposes all currently registered dependencies, removes all registrations, and makes the container active again.

```dart
container.reset();
```

After reset:

```dart
print(container.isDisposed); // false
```

The container can be reused:

```dart
container.reset();

container.registerSingleton<Database>(
  Database(),
);

final database = container.resolve<Database>();
```

If one or more dependencies fail during reset, all dependencies are still given an opportunity to dispose. After cleanup, the container is reset to an active state and `DependencyDisposalException` is thrown.

---

# Duplicate Registrations

A dependency cannot be registered more than once using the same type.

For example:

```dart
container.registerSingleton<Database>(
  Database(),
);

container.registerSingleton<Database>(
  Database(),
);
```

The second registration throws:

```text
DependencyAlreadyRegisteredException
```

`di_engine` intentionally does not silently replace existing registrations.

---

# Exceptions

## `DependencyNotRegisteredException`

Thrown when resolving a dependency that has not been registered.

```dart
container.resolve<Database>();
```

---

## `DependencyAlreadyRegisteredException`

Thrown when registering a dependency that is already registered.

```dart
container.registerSingleton<Database>(
  Database(),
);

container.registerSingleton<Database>(
  Database(),
);
```

---

## `DependencyDisposalException`

Thrown when one or more dependencies fail during disposal.

The exception contains all disposal failures:

```dart
try {
  container.dispose();
} on DependencyDisposalException catch (exception) {
  for (final failure in exception.failures) {
    print(failure.type);
    print(failure.error);
    print(failure.stackTrace);
  }
}
```

---

# Interface-Based Dependencies

Interfaces can be registered using an explicit generic type.

For example:

```dart
abstract interface class Logger {
  void log(String message);
}

class ConsoleLogger implements Logger {
  @override
  void log(String message) {
    print(message);
  }
}
```

Register the implementation as the interface:

```dart
container.registerSingleton<Logger>(
  ConsoleLogger(),
);
```

Resolve the interface:

```dart
final logger = container.resolve<Logger>();

logger.log('Hello');
```

This allows the consuming code to depend on abstractions rather than concrete implementations.

---

# Complete Example

```dart
import 'package:di_engine/di_engine.dart';

class Database implements Disposable {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    print('Database disposed');
  }
}

class ApiClient {
  final Database database;

  ApiClient(this.database);
}

class UserController {
  final ApiClient apiClient;

  UserController(this.apiClient);
}

void main() {
  final container = DIContainer();

  // Eager singleton.
  // Created immediately and owned by the container.
  container.registerSingleton<Database>(
    Database(),
  );

  // Lazy singleton.
  // Created only on first resolution and then cached.
  container.registerLazySingleton<ApiClient>(
    () => ApiClient(
      container.resolve<Database>(),
    ),
  );

  // Factory.
  // A new instance is created for every resolution.
  // Factory instances are not owned by the container.
  container.registerFactory<UserController>(
    () => UserController(
      container.resolve<ApiClient>(),
    ),
  );

  final database = container.resolve<Database>();
  final apiClient = container.resolve<ApiClient>();

  final firstController = container.resolve<UserController>();
  final secondController = container.resolve<UserController>();

  print(
    'ApiClient uses Database: '
    '${identical(apiClient.database, database)}',
  );

  print(
    'Controllers are different: '
    '${!identical(firstController, secondController)}',
  );

  container.dispose();

  print(
    'Database disposed: '
    '${database.isDisposed}',
  );

  print(
    'Container disposed: '
    '${container.isDisposed}',
  );
}
```

Output will be conceptually similar to:

```text
ApiClient uses Database: true
Controllers are different: true
Database disposed
Database disposed: true
Container disposed: true
```

---

# Dart and Flutter

`di_engine` works with both **Dart applications** and **Flutter applications**.

It can be used for services such as:

* API clients
* Repositories
* Databases
* Local storage
* Configuration services
* Logging services
* Application services
* Controllers
* Business logic components

Example Flutter setup:

```dart
final container = DIContainer();

container.registerSingleton<ApiClient>(
  ApiClient(),
);

container.registerLazySingleton<UserRepository>(
  () => UserRepository(
    container.resolve<ApiClient>(),
  ),
);
```

The container can then be provided to the application's composition root and used to construct application dependencies.

---

# Design Principles

`di_engine` intentionally follows a small set of principles:

### Explicit

Dependencies are registered and resolved explicitly.

### Predictable

Each registration type has a clearly defined lifecycle.

### Lightweight

No annotations, code generation, reflection, or generated dependency graphs are required.

### Lifecycle-aware

The container manages the lifecycle of singleton and lazy singleton dependencies.

### Safe disposal

Disposal failures are collected instead of preventing other dependencies from being cleaned up.

### Minimal API

The package focuses on the core dependency injection use cases without adding unnecessary framework-level abstractions.

---

# What `di_engine` Does Not Provide

The package intentionally does not include:

* Automatic dependency discovery
* Annotations
* Code generation
* Reflection-based injection
* Named dependencies
* Dependency scopes
* Async dependency registration
* Circular dependency detection
* Global service locator
* Automatic constructor injection
* Thread/isolate synchronization

These features may be considered separately in future versions if they fit the project's goals.

---

# Versioning

`di_engine` follows semantic versioning.

Breaking API changes may result in a major version increase.

For example:

```text
1.0.0 → 1.1.0
```

adds backward-compatible functionality, while a breaking API change may require:

```text
1.x.x → 2.0.0
```

---

# License

This project is licensed under the MIT License.

See the [LICENSE](LICENSE) file for details.

---

# Author

Copyright © 2026 V V
