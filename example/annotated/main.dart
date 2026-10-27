import 'package:di_engine/di_engine.dart';

import 'main.config.dart';

@lazySingleton
class ApiClient {}

@injectable
class UserRepository {
  final ApiClient api;
  UserRepository(this.api);
}

@injectable
class UserController {
  final UserRepository repository;
  final String userId;

  UserController(this.repository, @factoryParam this.userId);
}

@InjectableInit(
  generateForDir: ['example/annotated'],
  preferRelativeImports: true,
)
void configureDependencies() {}

Future<void> main() async {
  final engine = DIEngine.asNewInstance();
  await engine.init();

  final controller = engine.resolve<UserController>(param1: 'user-123');
  print('Created controller for ${controller.userId}');
  print('Injected repository: ${controller.repository.runtimeType}');

  await engine.reset();
}
