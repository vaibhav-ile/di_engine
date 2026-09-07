import 'package:di_engine/di_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class Database implements Disposable {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}

class Service implements Disposable {
  final String name;
  final List<String> disposalOrder;

  Service(this.name, this.disposalOrder);

  @override
  void dispose() {
    disposalOrder.add(name);
  }
}

void main() {
  group('Dispose', () {
    test('disposes singleton', () {
      final container = DIContainer();

      final database = Database();

      container.registerSingleton<Database>(database);

      container.dispose();

      expect(database.disposed, isTrue);
    });

    test('disposes lazy singleton if it was created', () {
      final container = DIContainer();

      final database = Database();

      container.registerLazySingleton<Database>(() => database);

      expect(database.disposed, isFalse);

      container.resolve<Database>();

      container.dispose();

      expect(database.disposed, isTrue);
    });

    test('does not create lazy singleton during dispose', () {
      final container = DIContainer();

      var created = false;

      container.registerLazySingleton<Database>(() {
        created = true;

        return Database();
      });

      container.dispose();

      expect(created, isFalse);
    });

    test('dispose is idempotent', () {
      final container = DIContainer();

      var disposeCount = 0;

      container.registerSingleton<Object>(
        Object(),
        dispose: (_) {
          disposeCount++;
        },
      );

      container.dispose();
      container.dispose();

      expect(disposeCount, 1);
    });

    test('disposes dependencies in reverse registration order', () {
      final container = DIContainer();

      final disposalOrder = <String>[];

      container.registerSingleton<Service>(Service('first', disposalOrder));

      container.registerSingleton<Service2>(Service2('second', disposalOrder));

      container.registerSingleton<Service3>(Service3('third', disposalOrder));

      container.dispose();

      expect(disposalOrder, ['third', 'second', 'first']);
    });

    test('continues disposing when one dependency fails', () {
      final container = DIContainer();

      var firstDisposed = false;
      var secondDisposed = false;

      container.registerSingleton<Object>(
        Object(),
        dispose: (_) {
          firstDisposed = true;
        },
      );

      container.registerSingleton<String>(
        'value',
        dispose: (_) {
          throw StateError('dispose failed');
        },
      );

      container.registerSingleton<int>(
        10,
        dispose: (_) {
          secondDisposed = true;
        },
      );

      expect(container.dispose, throwsA(isA<DependencyDisposalException>()));

      expect(firstDisposed, isTrue);
      expect(secondDisposed, isTrue);
      expect(container.isDisposed, isTrue);
    });

    test('disposal exception contains failure details', () {
      final container = DIContainer();

      container.registerSingleton<String>(
        'value',
        dispose: (_) {
          throw StateError('database failure');
        },
      );

      try {
        container.dispose();
        fail('Expected DependencyDisposalException');
      } on DependencyDisposalException catch (exception) {
        expect(exception.failures, hasLength(1));
        expect(exception.failures.first.type, String);
        expect(exception.failures.first.error, isA<StateError>());
      }
    });

    test('reset disposes dependencies and reactivates container', () {
      final container = DIContainer();

      var disposeCount = 0;

      container.registerSingleton<Object>(
        Object(),
        dispose: (_) {
          disposeCount++;
        },
      );

      container.reset();

      expect(disposeCount, 1);
      expect(container.isDisposed, isFalse);
      expect(container.isRegistered<Object>(), isFalse);

      container.registerSingleton<Object>(Object());

      expect(container.isRegistered<Object>(), isTrue);
    });

    test('reset can reactivate a disposed container', () {
      final container = DIContainer();

      container.registerSingleton<Object>(Object());

      container.dispose();

      expect(container.isDisposed, isTrue);

      container.reset();

      expect(container.isDisposed, isFalse);

      container.registerSingleton<Object>(Object());

      expect(container.isRegistered<Object>(), isTrue);
    });

    test('reset continues cleanup when disposal fails', () {
      final container = DIContainer();

      var successfulDispose = false;

      container.registerSingleton<String>(
        'failure',
        dispose: (_) {
          throw StateError('failed');
        },
      );

      container.registerSingleton<int>(
        10,
        dispose: (_) {
          successfulDispose = true;
        },
      );

      expect(container.reset, throwsA(isA<DependencyDisposalException>()));

      expect(successfulDispose, isTrue);
      expect(container.isDisposed, isFalse);

      container.registerSingleton<double>(10.0);

      expect(container.isRegistered<double>(), isTrue);
    });

    test('unregister disposal failure removes registration', () {
      final container = DIContainer();

      container.registerSingleton<String>(
        'value',
        dispose: (_) {
          throw StateError('failed');
        },
      );

      expect(
        () => container.unregister<String>(),
        throwsA(isA<DependencyDisposalException>()),
      );

      expect(container.isRegistered<String>(), isFalse);
    });
  });
}

class Service2 implements Disposable {
  final String name;
  final List<String> disposalOrder;

  Service2(this.name, this.disposalOrder);

  @override
  void dispose() {
    disposalOrder.add(name);
  }
}

class Service3 implements Disposable {
  final String name;
  final List<String> disposalOrder;

  Service3(this.name, this.disposalOrder);

  @override
  void dispose() {
    disposalOrder.add(name);
  }
}
