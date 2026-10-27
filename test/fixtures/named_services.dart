import 'package:di_engine/di_engine.dart';

abstract interface class NamedLogger {}

@named
@LazySingleton(as: NamedLogger)
class FileLogger implements NamedLogger {}
