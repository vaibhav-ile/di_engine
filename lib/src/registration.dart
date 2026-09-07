import 'disposable.dart';
import 'registration_type.dart';

typedef DisposeCallback<T> = void Function(T instance);

class Registration<T> {
  final RegistrationType type;
  final T Function()? _factory;
  final DisposeCallback<T>? _disposeCallback;

  T? _instance;
  bool _hasInstance = false;

  Registration._({
    required this.type,
    T? instance,
    bool hasInstance = false,
    T Function()? factory,
    DisposeCallback<T>? disposeCallback,
  }) : _factory = factory,
       _disposeCallback = disposeCallback,
       _instance = instance,
       _hasInstance = hasInstance;

  /// Creates an eagerly-created singleton registration.
  factory Registration.singleton(T instance, {DisposeCallback<T>? dispose}) {
    return Registration._(
      type: RegistrationType.singleton,
      instance: instance,
      hasInstance: true,
      disposeCallback: dispose,
    );
  }

  /// Creates a lazily-created singleton registration.
  factory Registration.lazySingleton(
    T Function() factory, {
    DisposeCallback<T>? dispose,
  }) {
    return Registration._(
      type: RegistrationType.lazySingleton,
      factory: factory,
      disposeCallback: dispose,
    );
  }

  /// Creates a transient factory registration.
  ///
  /// Factory-created instances are not owned by the container and therefore
  /// are not disposed by the container.
  factory Registration.factory(T Function() factory) {
    return Registration._(type: RegistrationType.factory, factory: factory);
  }

  /// Resolves an instance according to this registration's lifecycle.
  T resolve() {
    switch (type) {
      case RegistrationType.singleton:
        return _resolveSingleton();

      case RegistrationType.lazySingleton:
        return _resolveLazySingleton();

      case RegistrationType.factory:
        return _resolveFactory();
    }
  }

  T _resolveSingleton() {
    assert(_hasInstance, 'Singleton registration must contain an instance.');

    return _instance as T;
  }

  T _resolveLazySingleton() {
    if (!_hasInstance) {
      final factory = _factory;

      assert(
        factory != null,
        'Lazy singleton registration must contain a factory.',
      );

      _instance = factory!();
      _hasInstance = true;
    }

    return _instance as T;
  }

  T _resolveFactory() {
    final factory = _factory;

    assert(factory != null, 'Factory registration must contain a factory.');

    return factory!();
  }

  /// Disposes the container-owned instance if one exists.
  ///
  /// This method never creates a lazy singleton.
  ///
  /// Factory registrations do not own their created instances and therefore
  /// have nothing to dispose.
  void dispose() {
    if (type == RegistrationType.factory) {
      return;
    }

    if (!_hasInstance) {
      return;
    }

    final instance = _instance;

    try {
      if (_disposeCallback != null) {
        _disposeCallback(instance as T);
      } else if (instance is Disposable) {
        instance.dispose();
      }
    } finally {
      _instance = null;
      _hasInstance = false;
    }
  }
}
