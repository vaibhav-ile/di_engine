import 'package:di_engine/di_engine.dart';

import 'repositories/user_repository.dart';
import 'services/api_client.dart';

// Import this instance wherever application code needs to resolve a dependency.
// Creating another container in each file would create separate registries.
final container = DIContainer();

void configureDependencies() {
  container.registerLazySingleton<ApiClient>(ApiClient.new);
  container.registerFactory<UserRepository>(
    () => UserRepository(container.resolve<ApiClient>()),
  );
}
