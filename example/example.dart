// ignore_for_file: avoid_print
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
  // The instance is created immediately and owned by the container.
  container.registerSingleton<Database>(Database());

  // Lazy singleton.
  // The instance is created only when first resolved.
  container.registerLazySingleton<ApiClient>(
    () => ApiClient(container.resolve<Database>()),
  );

  // Factory.
  // A new instance is created every time it is resolved.
  container.registerFactory<UserController>(
    () => UserController(container.resolve<ApiClient>()),
  );

  print(
    'Database registration: '
    '${container.getRegistrationType<Database>()}',
  );

  print(
    'ApiClient registration: '
    '${container.getRegistrationType<ApiClient>()}',
  );

  print(
    'UserController registration: '
    '${container.getRegistrationType<UserController>()}',
  );

  // Resolve singleton.
  final database = container.resolve<Database>();

  // Resolve lazy singleton.
  final apiClient = container.resolve<ApiClient>();

  // Resolve factory twice.
  final firstController = container.resolve<UserController>();
  final secondController = container.resolve<UserController>();

  print('Database: ${database.isDisposed}');
  print('ApiClient uses Database: ${identical(apiClient.database, database)}');
  print(
    'Controllers are different: '
    '${!identical(firstController, secondController)}',
  );

  // Dispose the container.
  //
  // Database and ApiClient are owned by the container and will be disposed
  // if they implement Disposable.
  //
  // UserController is a factory product and is NOT container-owned.
  container.dispose();

  print('Container disposed: ${container.isDisposed}');
}
