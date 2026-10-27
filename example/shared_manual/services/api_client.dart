import 'package:di_engine/di_engine.dart';

class ApiClient implements Disposable {
  bool isDisposed = false;

  String fetchUser() => 'John';

  @override
  void dispose() => isDisposed = true;
}
