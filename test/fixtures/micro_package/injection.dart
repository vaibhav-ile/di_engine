import 'package:di_engine/di_engine.dart';

@InjectableInit.microPackage(generateForDir: ['test/fixtures/micro_package'])
void configureMicroPackage() {}

@singleton
class ExternalToken {}
