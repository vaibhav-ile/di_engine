import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:di_engine/src/generator/generator.dart';
import 'package:di_engine/src/generator/parser.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln('''di_engine SDK-only constructor generator

  dart run di_engine:generate [--entrypoint lib/injection.dart]
  dart run di_engine:generate --config di_engine.json

Options:
  --entrypoint PATH       Annotated initializer (defaults to discovery in lib/)
  --config PATH           JSON file with an ordered "targets" list
  --exclude PATH          Exclude an input directory (repeatable)
  --class-name-pattern RE Register unannotated classes matching a regex
  --file-name-pattern RE  Register classes in files matching a regex
  --module-name NAME     Generated micro-module class name
  --check                Fail if generated files are missing or stale
  --watch                Regenerate when Dart inputs or JSON configuration change
''');
    return;
  }
  try {
    final options = <String, String>{};
    final excludes = <String>[];
    var watch = false;
    var check = false;
    for (var i = 0; i < arguments.length; i++) {
      final arg = arguments[i];
      if (arg == '--watch') {
        watch = true;
        continue;
      }
      if (arg == '--check') {
        check = true;
        continue;
      }
      if (!{
            '--entrypoint',
            '--config',
            '--exclude',
            '--class-name-pattern',
            '--file-name-pattern',
            '--module-name',
          }.contains(arg) ||
          i + 1 >= arguments.length) {
        throw FormatException(
          'Unknown option or missing value: $arg. Run --help.',
        );
      }
      final value = arguments[++i];
      if (arg == '--exclude') {
        excludes.add(value);
      } else {
        options[arg] = value;
      }
    }
    if (check && watch) {
      throw const FormatException('--check and --watch cannot be combined.');
    }
    final root = Directory.current;
    Future<void> build() async {
      final generator = DependencyGenerator(root);
      final List<Map<String, dynamic>> targets;
      final config = options['--config'];
      if (config != null) {
        final data =
            jsonDecode(File(config).readAsStringSync()) as Map<String, dynamic>;
        targets = (data['targets'] as List).cast<Map<String, dynamic>>();
      } else {
        final entrypoint = options['--entrypoint'];
        final entries = entrypoint == null ? _discover(root) : [entrypoint];
        if (entries.isEmpty) {
          throw const FormatException(
            'No @InjectableInit found in lib/. Specify --entrypoint.',
          );
        }
        targets = [
          for (final entry in entries) {'entrypoint': entry},
        ];
      }
      for (final target in targets) {
        final output = await generator.generate(
          entrypoint: target['entrypoint'] as String,
          exclude: [
            ...excludes,
            ...(target['exclude'] as List? ?? []).cast<String>(),
          ],
          classNamePattern:
              target['classNamePattern'] as String? ??
              options['--class-name-pattern'],
          fileNamePattern:
              target['fileNamePattern'] as String? ??
              options['--file-name-pattern'],
          moduleName:
              target['moduleName'] as String? ?? options['--module-name'],
          output: target['output'] as String?,
          check: check,
        );
        stdout.writeln(
          '${check ? 'Verified' : 'Generated'} ${output.path.substring(root.path.length + 1)}',
        );
      }
    }

    await build();
    if (!watch) return;
    var previous = _snapshot(root);
    stdout.writeln('Watching Dart inputs. Press Ctrl+C to stop.');
    final stop = Completer<void>();
    final signal = ProcessSignal.sigint.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
    var running = false;
    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (running) return;
      final current = _snapshot(root);
      if (current == previous) return;
      previous = current;
      running = true;
      try {
        await build();
      } catch (error) {
        stderr.writeln(error);
      } finally {
        running = false;
      }
    });
    await stop.future;
    timer.cancel();
    await signal.cancel();
  } catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  }
}

Iterable<File> _walk(Directory directory) sync* {
  for (final entry in directory.listSync(followLinks: false)) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name.startsWith('.')) continue;
    if (entry is Directory) {
      yield* _walk(entry);
    } else if (entry is File &&
        (name.endsWith('.dart') || name.endsWith('.json')) &&
        !name.endsWith('.config.dart') &&
        !name.endsWith('.module.dart') &&
        !name.endsWith('.di_engine.tmp.dart')) {
      yield entry;
    }
  }
}

List<File> _inputs(Directory root) =>
    _walk(root).toList()..sort((a, b) => a.path.compareTo(b.path));

List<String> _discover(Directory root) {
  final lib = Directory('${root.path}/lib');
  if (!lib.existsSync()) return [];
  return [
    for (final file in _inputs(lib).where((f) => f.path.endsWith('.dart')))
      if (DartSource.read(file.path).initializer != null) file.path,
  ];
}

String _snapshot(Directory root) {
  final values = <String>[];
  for (final file in _inputs(root)) {
    try {
      values.add('${file.path}:${file.readAsStringSync().hashCode}');
    } on FileSystemException {
      /* A file may be replaced by an editor mid-scan. */
    }
  }
  return values.join('\n');
}
