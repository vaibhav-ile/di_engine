import 'exceptions.dart';
import 'registration.dart';
import 'registration_type.dart';

class DIContainer {
  final Map<Type, Registration<dynamic>> _registrations = {};

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // REGISTER SINGLETON
  // ---------------------------------------------------------------------------

  void registerSingleton<T>(T instance, {void Function(T instance)? dispose}) {
    _checkNotDisposed();
    _checkNotRegistered<T>();

    _registrations[T] = Registration<T>(
      type: RegistrationType.singleton,
      instance: instance,
      disposeCallback: dispose,
    );
  }

  // ---------------------------------------------------------------------------
  // REGISTER LAZY SINGLETON
  // ---------------------------------------------------------------------------

  void registerLazySingleton<T>(
    T Function() factory, {
    void Function(T instance)? dispose,
  }) {
    _checkNotDisposed();
    _checkNotRegistered<T>();

    _registrations[T] = Registration<T>(
      type: RegistrationType.lazySingleton,
      factory: factory,
      disposeCallback: dispose,
    );
  }

  // ---------------------------------------------------------------------------
  // REGISTER FACTORY
  // ---------------------------------------------------------------------------

  void registerFactory<T>(
    T Function() factory, {
    void Function(T instance)? dispose,
  }) {
    _checkNotDisposed();
    _checkNotRegistered<T>();

    _registrations[T] = Registration<T>(
      type: RegistrationType.factory,
      factory: factory,
      disposeCallback: dispose,
    );
  }

  // ---------------------------------------------------------------------------
  // RESOLVE
  // ---------------------------------------------------------------------------

  T resolve<T>() {
    _checkNotDisposed();

    final registration = _registrations[T];

    if (registration == null) {
      throw DependencyNotRegisteredException(T);
    }

    return registration.resolve() as T;
  }

  // ---------------------------------------------------------------------------
  // CHECK REGISTRATION
  // ---------------------------------------------------------------------------

  bool isRegistered<T>() {
    return _registrations.containsKey(T);
  }

  // ---------------------------------------------------------------------------
  // UNREGISTER
  // ---------------------------------------------------------------------------

  void unregister<T>() {
    _checkNotDisposed();

    final registration = _registrations.remove(T);

    if (registration == null) {
      return;
    }

    registration.dispose();
  }

  // ---------------------------------------------------------------------------
  // DISPOSE CONTAINER
  // ---------------------------------------------------------------------------

  void dispose() {
    if (_disposed) {
      return;
    }

    for (final registration in _registrations.values) {
      registration.dispose();
    }

    _registrations.clear();

    _disposed = true;
  }

  // ---------------------------------------------------------------------------
  // RESET
  // ---------------------------------------------------------------------------

  void reset() {
    for (final registration in _registrations.values) {
      registration.dispose();
    }

    _registrations.clear();

    _disposed = false;
  }

  // ---------------------------------------------------------------------------
  // INTERNAL
  // ---------------------------------------------------------------------------

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
