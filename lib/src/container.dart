import 'dart:collection';

import 'exceptions.dart';
import 'registration.dart';
import 'registration_type.dart';

class DIContainer {
  final LinkedHashMap<Type, Registration<dynamic>> _registrations =
      LinkedHashMap<Type, Registration<dynamic>>();

  bool _disposed = false;

  /// Whether this container has been disposed.
  bool get isDisposed => _disposed;

  /// Registers an eagerly-created singleton.
  ///
  /// The container takes ownership of the instance and will dispose it when
  /// the registration is removed or the container is disposed.
  void registerSingleton<T>(T instance, {void Function(T instance)? dispose}) {
    _checkNotDisposed();
    _checkNotRegistered<T>();

    _registrations[T] = Registration<T>.singleton(instance, dispose: dispose);
  }

  /// Registers a lazily-created singleton.
  ///
  /// The factory is not executed until the first resolution.
  ///
  /// The resulting instance is owned by the container and will be disposed
  /// when the registration is removed or the container is disposed.
  void registerLazySingleton<T>(
    T Function() factory, {
    void Function(T instance)? dispose,
  }) {
    _checkNotDisposed();
    _checkNotRegistered<T>();

    _registrations[T] = Registration<T>.lazySingleton(
      factory,
      dispose: dispose,
    );
  }

  /// Registers a transient factory.
  ///
  /// A new instance is created for every resolution.
  ///
  /// Factory-created instances are not owned or disposed by the container.
  /// The caller is responsible for their lifecycle.
  void registerFactory<T>(T Function() factory) {
    _checkNotDisposed();
    _checkNotRegistered<T>();

    _registrations[T] = Registration<T>.factory(factory);
  }

  /// Resolves the dependency registered for [T].
  T resolve<T>() {
    _checkNotDisposed();

    final registration = _registrations[T];

    if (registration == null) {
      throw DependencyNotRegisteredException(T);
    }

    return registration.resolve() as T;
  }

  /// Returns whether a dependency is registered for [T].
  ///
  /// This method is safe to call even after the container has been disposed.
  bool isRegistered<T>() {
    return _registrations.containsKey(T);
  }

  /// Returns the registration type for [T], or null if it is not registered.
  ///
  /// This method is safe to call even after the container has been disposed.
  RegistrationType? getRegistrationType<T>() {
    return _registrations[T]?.type;
  }

  /// Removes the dependency registered for [T].
  ///
  /// If the registration owns an instance, that instance is disposed.
  ///
  /// A lazy singleton that has never been resolved is not created during
  /// unregister.
  ///
  /// Factory-created instances are not disposed.
  void unregister<T>() {
    _checkNotDisposed();

    final registration = _registrations.remove(T);

    if (registration == null) {
      return;
    }

    try {
      registration.dispose();
    } catch (error, stackTrace) {
      throw DependencyDisposalException([
        DependencyDisposalFailure(
          type: T,
          error: error,
          stackTrace: stackTrace,
        ),
      ]);
    }
  }

  /// Disposes all container-owned dependencies.
  ///
  /// Dependencies are disposed in reverse registration order.
  ///
  /// All dependencies are given an opportunity to dispose even if one or more
  /// disposal operations fail.
  ///
  /// The container is always marked as disposed after this operation.
  ///
  /// Calling dispose more than once is safe.
  void dispose() {
    if (_disposed) {
      return;
    }

    final failures = <DependencyDisposalFailure>[];

    final registrations = _registrations.entries.toList().reversed;

    for (final entry in registrations) {
      try {
        entry.value.dispose();
      } catch (error, stackTrace) {
        failures.add(
          DependencyDisposalFailure(
            type: entry.key,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    _registrations.clear();
    _disposed = true;

    if (failures.isNotEmpty) {
      throw DependencyDisposalException(failures);
    }
  }

  /// Disposes all dependencies and makes the container usable again.
  ///
  /// Like [dispose], all dependencies are given an opportunity to dispose
  /// before any disposal exception is reported.
  void reset() {
    final failures = <DependencyDisposalFailure>[];

    final registrations = _registrations.entries.toList().reversed;

    for (final entry in registrations) {
      try {
        entry.value.dispose();
      } catch (error, stackTrace) {
        failures.add(
          DependencyDisposalFailure(
            type: entry.key,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    _registrations.clear();
    _disposed = false;

    if (failures.isNotEmpty) {
      throw DependencyDisposalException(failures);
    }
  }

  void _checkNotRegistered<T>() {
    if (_registrations.containsKey(T)) {
      throw DependencyAlreadyRegisteredException(T);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('Container has already been disposed.');
    }
  }
}
