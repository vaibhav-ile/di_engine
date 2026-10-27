import 'dart:convert';
import 'dart:io';

/// Checks the published consumer path with a completely empty pub cache and no
/// network. Development-only test/lint dependencies are intentionally absent.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final app = Directory.systemTemp.createTempSync('di_engine_independent_');
  try {
    Directory('${app.path}/lib').createSync();
    Directory('${app.path}/bin').createSync();
    File('${app.path}/pubspec.yaml').writeAsStringSync(
      '''name: independence_probe
environment:
  sdk: ^3.12.0
dependencies:
  di_engine:
    path: ${jsonEncode(root)}
''',
    );
    File('${app.path}/lib/injection.dart').writeAsStringSync(
      '''import 'package:di_engine/di_engine.dart';
@singleton
class Api { final int value = 42; }
@injectable
class Repository {
  final Api api;
  final String user;
  Repository(this.api, @factoryParam this.user);
}
@InjectableInit(generateAccessors: true, usesConstructorCallback: true)
void configure() {}
''',
    );
    File('${app.path}/bin/main.dart').writeAsStringSync(
      '''import 'package:di_engine/di_engine.dart';
import '../lib/injection.dart';
import '../lib/injection.config.dart';
Future<void> main() async {
  final engine = DIEngine();
  var constructors = 0;
  await engine.init(constructorCallback: <T>(T instance) {
    constructors++;
    return instance;
  });
  final result = engine.resolve<Repository>(param1: 'independent');
  if (result.api.value != 42 || result.user != 'independent') {
    throw StateError('Constructor injection failed.');
  }
  if (engine.api.value != 42 || constructors != 2) throw StateError('Generated accessors/callbacks failed.');
  await engine.dispose();
  print('Independent constructor injection passed.');
}
''',
    );
    final environment = {'PUB_CACHE': '${app.path}/empty-cache'};
    Future<String> run(List<String> arguments) async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        arguments,
        workingDirectory: app.path,
        environment: environment,
      );
      if (result.exitCode != 0) {
        throw StateError(
          '${arguments.join(' ')}\n${result.stdout}\n${result.stderr}',
        );
      }
      return result.stdout as String;
    }

    await run(['pub', 'get', '--offline']);
    final deps =
        jsonDecode(await run(['pub', 'deps', '--json']))
            as Map<String, dynamic>;
    final packages = (deps['packages'] as List)
        .map((p) => p['name'] as String)
        .toSet();
    if (packages.length != 2 ||
        !packages.containsAll({'independence_probe', 'di_engine'})) {
      throw StateError('Unexpected package dependencies: $packages');
    }
    await run([
      'run',
      'di_engine:generate',
      '--entrypoint',
      'lib/injection.dart',
    ]);
    await run([
      'run',
      'di_engine:generate',
      '--entrypoint',
      'lib/injection.dart',
      '--check',
    ]);
    stdout.write(await run(['run', 'bin/main.dart']));
    stdout.writeln(
      'Consumer resolves only di_engine; generation and runtime work with an empty offline pub cache.',
    );
  } finally {
    app.deleteSync(recursive: true);
  }
}
