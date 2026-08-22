import 'package:di_core/di_core.dart';
import 'package:flutter_test/flutter_test.dart';

class Database implements Disposable {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
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
  });
}
