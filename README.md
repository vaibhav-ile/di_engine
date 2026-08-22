# DI Core

A lightweight and type-safe dependency injection container for Dart and Flutter applications.

## Features

* Register singleton dependencies.
* Register lazy singleton dependencies.
* Register factory dependencies.
* Resolve dependencies using their type.
* Dispose registered dependencies.
* Simple and lightweight API.
* No unnecessary dependencies.
* Suitable for both Dart and Flutter applications.

## Installation

Add `di_core` to your `pubspec.yaml`:

```yaml
dependencies:
  di_core: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Getting Started

Import the package:

```dart
import 'package:di_core/di_core.dart';
```

Create a dependency container:

```dart
final container = DIContainer();
```

### Register a Singleton

A singleton creates one instance and returns the same instance whenever it is resolved.

```dart
container.registerSingleton<ApiService>(
  ApiService(),
);
```

Resolve it:

```dart
final apiService = container.resolve<ApiService>();
```

### Register a Lazy Singleton

A lazy singleton is created only when it is first requested.

```dart
container.registerLazySingleton<ApiService>(
  () => ApiService(),
);
```

Then:

```dart
final apiService = container.resolve<ApiService>();
```

### Register a Factory

A factory creates a new instance every time it is resolved.

```dart
container.registerFactory<SomeService>(
  () => SomeService(),
);
```

Each call creates a new instance:

```dart
final service1 = container.resolve<SomeService>();
final service2 = container.resolve<SomeService>();
```

### Dispose Dependencies

When a dependency is no longer needed, it can be disposed through the container.

```dart
container.dispose<ApiService>();
```

## Example

A simple application setup could look like:

```dart
final container = DIContainer();

void setupDependencies() {
  container.registerLazySingleton<ApiService>(
    () => ApiService(),
  );

  container.registerLazySingleton<UserRepository>(
    () => UserRepository(
      container.resolve<ApiService>(),
    ),
  );

  container.registerFactory<UserController>(
    () => UserController(
      container.resolve<UserRepository>(),
    ),
  );
}
```

Then resolve the controller:

```dart
final controller = container.resolve<UserController>();
```

## Registration Types

| Registration            | Instance Creation | Same Instance |
| ----------------------- | ----------------- | ------------- |
| `registerSingleton`     | Immediately       | Yes           |
| `registerLazySingleton` | On first resolve  | Yes           |
| `registerFactory`       | On every resolve  | No            |

## Type Safety

Dependencies are resolved using their registered type:

```dart
final repository = container.resolve<UserRepository>();
```

This keeps dependency resolution explicit and type-safe.

## Flutter Usage

The package can be initialized during application startup:

```dart
void main() {
  setupDependencies();

  runApp(const MyApp());
}
```

Dependencies can then be resolved wherever they are required.

## Why DI Core?

DI Core is designed to provide a small and straightforward dependency injection solution without forcing a large framework or complex architecture on your application.

It can be used for:

* Flutter applications
* Dart applications
* Services and repositories
* Controllers
* API clients
* Application-level dependencies
* Testable application architectures

## Requirements

* Dart SDK compatible with the package SDK constraint.
* Flutter SDK for Flutter applications.

## Contributing

Contributions, bug reports, and feature requests are welcome.

Please open an issue or submit a pull request on the project's GitHub repository.

## License

This project is licensed under the MIT License.
