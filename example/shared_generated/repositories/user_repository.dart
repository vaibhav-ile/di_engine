import 'package:di_engine/di_engine.dart';

import '../services/api_client.dart';

@injectable
class UserRepository {
  final ApiClient api;

  // The generated registration supplies ApiClient automatically.
  UserRepository(this.api);

  String getUser() => api.fetchUser();
}
