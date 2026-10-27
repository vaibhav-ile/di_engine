import 'package:di_engine/di_engine.dart' hide test;
import 'package:test/test.dart';

class UserController {}

class DisposableController implements Disposable {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  group('Factory', () {
    test('creates new instance every time', () {
      final container = DIContainer();

      container.registerFactory<UserController>(() => UserController());

      final first = container.resolve<UserController>();
      final second = container.resolve<UserController>();

      expect(identical(first, second), isFalse);
    });

    test('factory is not disposed by container', () {
      final container = DIContainer();

      final instances = <DisposableController>[];

      container.registerFactory<DisposableController>(() {
        final instance = DisposableController();
        instances.add(instance);

        return instance;
      });

      final first = container.resolve<DisposableController>();
      final second = container.resolve<DisposableController>();

      container.dispose();

      expect(first.disposed, isFalse);
      expect(second.disposed, isFalse);
    });

    test('factory registration is removed when container is disposed', () {
      final container = DIContainer();

      container.registerFactory<UserController>(() => UserController());

      expect(container.isRegistered<UserController>(), isTrue);

      container.dispose();

      expect(container.isRegistered<UserController>(), isFalse);
    });
  });
}
