import '../di.dart';
import '../repositories/user_repository.dart';

// An application boundary can resolve from the shared container. Services and
// repositories themselves use constructor injection to remain easy to test.
class ProfileScreen {
  final UserRepository repository = container.resolve<UserRepository>();

  void show() => print('Profile screen: ${repository.getUser()}');
}
