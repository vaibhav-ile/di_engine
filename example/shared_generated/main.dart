import 'di.dart';
import 'features/profile_screen.dart';
import 'repositories/user_repository.dart';
import 'services/api_client.dart';

Future<void> main() async {
  // Await generated registration once, before the application resolves anything.
  await initializeDependencies();
  final api = engine.resolve<ApiClient>();

  try {
    final repository = engine.resolve<UserRepository>();
    print('Main file: ${repository.getUser()}');

    final profile = ProfileScreen();
    profile.show();

    // The generator injects the same lazy singleton into both repositories.
    if (!identical(repository.api, profile.repository.api)) {
      throw StateError('Both files must resolve the same API client.');
    }
    print('Same API client across files: true');
  } finally {
    await engine.dispose();
  }
  print('Shared API client disposed: ${api.isDisposed}');
}
