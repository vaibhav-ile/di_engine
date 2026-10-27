import 'package:di_engine/di_engine.dart';

import 'di.config.dart';

// One instance shared by main.dart and features/profile_screen.dart.
final engine = DIEngine();

// This example lives outside lib/, so discovery is explicitly scoped to it.
// In a consuming application, @InjectableInit() discovers lib/ by default.
@InjectableInit(generateForDir: ['example/shared_generated'])
void configureDependencies() {}

Future<void> initializeDependencies() async {
  await engine.init();
}
