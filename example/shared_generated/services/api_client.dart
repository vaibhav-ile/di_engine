import 'package:di_engine/di_engine.dart';

@lazySingleton
class ApiClient implements Disposable {
  bool isDisposed = false;

  String fetchUser() => 'John';

  @override
  void dispose() => isDisposed = true;
}
