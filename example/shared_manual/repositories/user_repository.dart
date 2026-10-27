import '../services/api_client.dart';

class UserRepository {
  final ApiClient api;

  UserRepository(this.api);

  String getUser() => api.fetchUser();
}
