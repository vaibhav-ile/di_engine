import 'di.dart';
import 'features/profile_screen.dart';
import 'repositories/user_repository.dart';
import 'services/api_client.dart';

void main() {
  // Register once, before constructing classes that resolve dependencies.
  configureDependencies();
  final api = container.resolve<ApiClient>();

  try {
    final repository = container.resolve<UserRepository>();
    print('Main file: ${repository.getUser()}');

    final profile = ProfileScreen();
    profile.show();

    // Repositories are transient; their lazy singleton API client is shared.
    if (!identical(repository.api, profile.repository.api)) {
      throw StateError('Both files must resolve the same API client.');
    }
    print('Same API client across files: true');
  } finally {
    container.dispose();
  }
  print('Shared API client disposed: ${api.isDisposed}');
}
