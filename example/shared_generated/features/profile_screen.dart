import '../di.dart';
import '../repositories/user_repository.dart';

// This file imports the shared engine; it does not create a new DIEngine.
class ProfileScreen {
  final UserRepository repository = engine.resolve<UserRepository>();

  void show() => print('Profile screen: ${repository.getUser()}');
}
