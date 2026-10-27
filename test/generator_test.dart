import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:di_engine/src/generator/generator.dart';
import 'package:di_engine/src/generator/parser.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('di_engine_generator_');
    Directory('${temporary.path}/lib').createSync();
    File('${temporary.path}/pubspec.yaml').writeAsStringSync(
      'name: generated_fixture\nenvironment:\n  sdk: ^3.12.0\n',
    );
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  File input(String code) =>
      File('${temporary.path}/lib/injection.dart')..writeAsStringSync(code);
  Future<File> generate({bool check = false}) => DependencyGenerator(
    temporary,
  ).generate(entrypoint: 'lib/injection.dart', check: check);

  test('lexer balances nested comments and preserves delimiters in strings', () {
    final tokens = tokenize(
      '/* outer /* inner */ end */ C({String url = "https://host/{x}"}); // tail',
    );
    expect(tokens.first, 'C');
    expect(tokens, contains('"https://host/{x}"'));
    expect(closing(tokens, tokens.indexOf('(')), tokens.length - 2);
  });

  test(
    'generator rejects missing constructor dependencies before writing output',
    () async {
      input(
        '@InjectableInit() void configure() {} @injectable class A { A(Missing value); }',
      );
      await expectLater(
        generate(),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.message,
            'message',
            contains('Missing'),
          ),
        ),
      );
      expect(
        File('${temporary.path}/lib/injection.config.dart').existsSync(),
        isFalse,
      );
    },
  );

  test('generator diagnoses cycles', () async {
    input(
      '@InjectableInit() void configure() {} @injectable class A { A(B value); } @injectable class B { B(A value); }',
    );
    await expectLater(
      generate(),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.message,
          'message',
          contains('Circular dependency'),
        ),
      ),
    );
  });

  test('generator rejects duplicate registrations and generic classes', () async {
    input(
      '@InjectableInit() void configure() {} @Injectable(as: I) class A {} @Injectable(as: I) class B {}',
    );
    await expectLater(
      generate(),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.message,
          'message',
          contains('Duplicate'),
        ),
      ),
    );
    input('@InjectableInit() void configure() {} @injectable class A<T> {}');
    await expectLater(
      generate(),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.message,
          'message',
          contains('generic'),
        ),
      ),
    );
  });

  test('one named constructor must be selected explicitly', () async {
    input(
      '@InjectableInit() void configure() {} @injectable class A { A.create(); }',
    );
    await expectLater(
      generate(),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.message,
          'message',
          contains('@factoryMethod'),
        ),
      ),
    );
  });

  test('check mode detects stale output without overwriting it', () async {
    input('@InjectableInit() void configure() {} @injectable class A {}');
    final result = await generate();
    final generated = result.readAsStringSync();
    await generate(check: true);
    input('@InjectableInit() void configure() {} @singleton class A {}');
    await expectLater(
      generate(check: true),
      throwsA(isA<GenerationException>()),
    );
    expect(result.readAsStringSync(), generated);
  });

  test(
    'optional defaults, named dependencies, and constructor formals are emitted',
    () async {
      input(
        "@InjectableInit() void configure() {} @injectable class A { final String label; A({this.label = 'guest'}); }",
      );
      final file = await generate();
      final code = file.readAsStringSync();
      expect(code, contains('isRegistered<String>()'));
      expect(code, contains("'guest'"));
      expect(code, contains('label:'));
    },
  );

  test(
    'generator supports callback/accessor options and function output',
    () async {
      input(
        '@InjectableInit(usesConstructorCallback: true, generateAccessors: true, asExtension: false) void configure() {} @singleton class A {}',
      );
      final code = (await generate()).readAsStringSync();
      expect(code, contains('constructorCallback'));
      expect(code, contains('a(_di.DIEngine engine)'));
      expect(code, isNot(contains('extension DIEngine')));
    },
  );

  test('source text in constructors is never executed', () async {
    final marker = '${temporary.path}/side-effect';
    input(
      "import 'dart:io'; @InjectableInit() void configure() {} @injectable class A { A() { File('$marker').writeAsStringSync('executed'); } }",
    );
    await generate();
    expect(File(marker).existsSync(), isFalse);
  });
  test(
    'prefixed native annotations and SDK provider types are recognized',
    () async {
      input(
        "import 'package:di_engine/di_engine.dart' as di; import 'dart:io'; @di.InjectableInit() void configure() {} @di.module abstract class Providers { Directory get folder => Directory('.'); } @di.injectable class A { A(Directory folder); }",
      );
      final generated = (await generate()).readAsStringSync();
      expect(generated, contains('dart:io'));
      expect(generated, contains('.Directory>'));
      expect(generated, contains('registerFactory<'));
    },
  );

  test(
    'types with the same name from different libraries retain their identity',
    () async {
      File(
        '${temporary.path}/lib/first.dart',
      ).writeAsStringSync('@injectable class Service {}');
      File(
        '${temporary.path}/lib/second.dart',
      ).writeAsStringSync('@injectable class Service {}');
      input(
        "import 'first.dart' as first; import 'second.dart' as second; @InjectableInit() void configure() {} @injectable class Controller { Controller(first.Service a, second.Service b); }",
      );
      final generated = (await generate()).readAsStringSync();
      expect(generated, contains('first.dart'));
      expect(generated, contains('second.dart'));
    },
  );

  test('pre-resolved module factories retain their startup value', () async {
    input(
      '@InjectableInit() void configure() {} @module abstract class Providers { @preResolve Future<String> get value async => "ready"; }',
    );
    final generated = (await generate()).readAsStringSync();
    expect(generated, contains('_preResolved'));
    expect(generated, contains('registerFactory<String>'));
  });
  test(
    'CLI watch regenerates after input edits and exits on interrupt',
    () async {
      final source = input(
        '@InjectableInit() void configure() {} @injectable class A {}',
      );
      final process = await Process.start(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        File('bin/generate.dart').absolute.path,
        '--entrypoint',
        'lib/injection.dart',
        '--watch',
      ], workingDirectory: temporary.path);
      final watching = Completer<void>();
      final rebuilt = Completer<void>();
      var generated = 0;
      final errors = StringBuffer();
      final out = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('Watching') && !watching.isCompleted) {
              watching.complete();
            }
            if (line.startsWith('Generated') &&
                ++generated >= 2 &&
                !rebuilt.isCompleted) {
              rebuilt.complete();
            }
          });
      final err = process.stderr.transform(utf8.decoder).listen(errors.write);
      try {
        await watching.future.timeout(const Duration(seconds: 10));
        source.writeAsStringSync(
          '@InjectableInit() void configure() {} @singleton class A {}',
        );
        await rebuilt.future.timeout(const Duration(seconds: 10));
        expect(
          File(
            '${temporary.path}/lib/injection.config.dart',
          ).readAsStringSync(),
          contains('registerSingletonFactory'),
        );
        process.kill(ProcessSignal.sigint);
        expect(
          await process.exitCode.timeout(const Duration(seconds: 5)),
          0,
          reason: errors.toString(),
        );
      } finally {
        process.kill();
        await out.cancel();
        await err.cancel();
      }
    },
  );
  test(
    'Named.from removes an import prefix from the registration name',
    () async {
      File(
        '${temporary.path}/lib/service.dart',
      ).writeAsStringSync('@named @injectable class Service {}');
      input(
        "import 'service.dart' as impl; @InjectableInit() void configure() {} @injectable class Consumer { Consumer(@Named.from(impl.Service) impl.Service service); }",
      );
      final code = (await generate()).readAsStringSync();
      expect(code, contains('name: "Service"'));
      expect(code, isNot(contains('name: "impl.Service"')));
    },
  );

  test('optional enum defaults are qualified in generated code', () async {
    input(
      '@InjectableInit() void configure() {} enum Status { idle } @injectable class A { A({Status status = Status.idle}); }',
    );
    final code = (await generate()).readAsStringSync();
    expect(code, matches(RegExp(r': _i[0-9]+\.Status\.idle')));
  });

  test(
    'annotation string literals decode Dart escapes and preserve raw strings',
    () {
      expect(literal(r"'first\nsecond'"), 'first\nsecond');
      expect(literal(r"'\u0041\x42\u{43}'"), 'ABC');
      expect(literal(r"r'first\nsecond'"), r'first\nsecond');
    },
  );

  test('generated scopes instantiate only their own provider modules', () async {
    input(
      "@InjectableInit() void configure() {} @module abstract class Providers { int get value => 1; } @Scope('request') @injectable class Scoped {}",
    );
    final code = (await generate()).readAsStringSync();
    expect(RegExp(r'final _module1 =').allMatches(code), hasLength(1));
  });
  test('SDK symbol lookup skips unrelated implementation signatures', () async {
    File(
      '${temporary.path}/lib/dependency.dart',
    ).writeAsStringSync('@injectable class Dependency {}');
    input(
      "import 'dart:async'; import 'dependency.dart'; @InjectableInit() void configure() {} @injectable class Consumer { Consumer(Dependency dependency); }",
    );
    expect((await generate()).readAsStringSync(), contains('Dependency>'));
  });

  test(
    'field initializers with comparisons do not confuse type balancing',
    () async {
      input(
        '@InjectableInit() void configure() {} @injectable class A { final bool small = 1 < 2; final Map<String, int> values = {"a": 1}; A(); }',
      );
      expect(
        (await generate()).readAsStringSync(),
        contains('registerFactory<'),
      );
    },
  );
  test(
    'constructor initializer assertions are skipped as executable expressions',
    () async {
      input(
        '@InjectableInit() void configure() {} @module abstract class Providers { int get value => 1; } @injectable class A { final int value; A(this.value) : assert(value < 3); }',
      );
      expect((await generate()).readAsStringSync(), contains('resolve<int>'));
    },
  );
}
