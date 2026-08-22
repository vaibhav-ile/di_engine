import 'disposable.dart';
import 'registration_type.dart';

typedef DisposeCallback<T> = void Function(T instance);

class Registration<T> {
  final RegistrationType type;

  final T Function()? factory;

  final DisposeCallback<T>? disposeCallback;

  T? _instance;

  bool _created = false;

  Registration({
    required this.type,
    this.factory,
    this.disposeCallback,
    T? instance,
  }) {
    if (instance != null) {
      _instance = instance;
      _created = true;
    }
  }

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
    if (!_created) {
      throw StateError('Singleton registration does not contain an instance.');
    }

    return _instance as T;
  }

  T _resolveLazySingleton() {
    if (!_created) {
      final create = factory;

      if (create == null) {
        throw StateError('Lazy singleton does not have a factory.');
      }

      _instance = create();
      _created = true;
    }

    return _instance as T;
  }

  T _resolveFactory() {
    final create = factory;

    if (create == null) {
      throw StateError('Factory registration does not have a factory.');
    }

    return create();
  }

  void dispose() {
    if (!_created) {
      return;
    }

    final instance = _instance;

    if (instance == null) {
      return;
    }

    if (disposeCallback != null) {
      disposeCallback!(instance);
    } else if (instance is Disposable) {
      instance.dispose();
    }

    _instance = null;
    _created = false;
  }
}
