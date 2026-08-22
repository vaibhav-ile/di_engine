import 'package:di_manager/di_core.dart';

class Database implements Disposable {
  @override
  void dispose() {
    print('Database disposed');
  }
}

class ApiClient {
  final Database database;

  ApiClient(this.database);
}

class UserRepository {
  final ApiClient apiClient;

  UserRepository(this.apiClient);
}

class UserController {
  final UserRepository repository;

  UserController(this.repository);
}

void main() {
  final di = DIContainer();

  // Create immediately.
  di.registerSingleton<Database>(Database());

  // Create on first resolve.
  di.registerLazySingleton<ApiClient>(() => ApiClient(di.resolve<Database>()));

  // Create a new instance on every resolve.
  di.registerFactory<UserController>(
    () => UserController(UserRepository(di.resolve<ApiClient>())),
  );

  final controller = di.resolve<UserController>();

  print(controller);

  di.dispose();
}
