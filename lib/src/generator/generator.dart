import 'dart:convert';
import 'dart:io';

import 'parser.dart';

String _quote(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
String _pascal(String value) => value
    .split(RegExp(r'[^A-Za-z0-9]+'))
    .where((v) => v.isNotEmpty)
    .map((v) => v[0].toUpperCase() + v.substring(1))
    .join();
String _normal(String value) => compact(value);

class GenerationException implements Exception {
  final String message;
  GenerationException(this.message);
  @override
  String toString() => 'DI generation failed: $message';
}

class _Registration {
  final ClassDeclaration owner;
  final Member member;
  final String type;
  final String lifetime;
  final String? name;
  final Set<String> environments;
  final String? scope;
  final int order;
  final bool preResolve;
  final String? dispose;
  final Member? disposeMethod;
  final Member? postConstruct;
  final bool signalsReady;
  final bool module;
  bool asynchronous;
  _Registration({
    required this.owner,
    required this.member,
    required this.type,
    required this.lifetime,
    required this.name,
    required this.environments,
    required this.scope,
    required this.order,
    required this.preResolve,
    required this.dispose,
    required this.disposeMethod,
    required this.postConstruct,
    required this.signalsReady,
    required this.module,
    required this.asynchronous,
  });
  List<Parameter> get parameters => member.parameters;
  List<Parameter> get runtime => parameters.where((p) => p.runtime).toList();
  bool get exposedAsync => asynchronous && !preResolve;
}

class _External {
  final String type;
  final String? scope;
  _External(this.type, this.scope);
}

/// SDK-only source generator. It reads signatures and emits normal Dart code.
/// It neither executes application code nor imports VM reflection into apps.
class DependencyGenerator {
  final Directory root;
  final Map<String, DartSource> _sources = {};
  final Map<String, DartSource> _symbolSources = {};
  final Map<String, String> _packageRoots = {};
  DependencyGenerator(this.root) {
    final file = File('${root.path}/.dart_tool/package_config.json');
    if (file.existsSync()) {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final p in data['packages'] as List) {
        final uri = file.uri
            .resolve(p['rootUri'] as String)
            .resolve((p['packageUri'] as String?) ?? 'lib/');
        if (uri.scheme == 'file') {
          _packageRoots[p['name'] as String] = uri.toFilePath();
        }
      }
    }
  }

  DartSource _read(String path) => _sources.putIfAbsent(
    File(path).absolute.path,
    () => DartSource.read(File(path).absolute.path),
  );

  String? _resolveImport(String uri, DartSource source) {
    if (uri.startsWith('dart:')) {
      final library = uri.substring(5);
      final sdk = File(Platform.resolvedExecutable).parent.parent.path;
      final file = '$sdk/lib/$library/$library.dart';
      return File(file).existsSync() ? file : null;
    }
    if (uri.startsWith('package:')) {
      final parts = uri.substring(8).split('/');
      final folder = _packageRoots[parts.first];
      return folder == null ? null : '$folder${parts.skip(1).join('/')}';
    }
    final resolved = File(source.path).uri.resolve(uri);
    return resolved.scheme == 'file' ? resolved.toFilePath() : null;
  }

  String? _origin(String path, String symbol, Set<String> visited) {
    if (!visited.add(path) || !File(path).existsSync()) return null;
    // Imported libraries only need a symbol table. Their executable/member
    // implementation details must not constrain injectable signature parsing.
    final source =
        _sources[path] ??
        _symbolSources.putIfAbsent(
          path,
          () => DartSource.read(path, signatures: false),
        );
    if (source.symbols.contains(symbol)) return path;
    for (final part in source.parts) {
      final target = _resolveImport(part, source);
      if (target != null && _origin(target, symbol, visited) != null) {
        return path;
      }
    }
    for (final export in source.exports) {
      final target = _resolveImport(export, source);
      if (target != null) {
        final origin = _origin(target, symbol, visited);
        if (origin != null) return origin;
      }
    }
    return null;
  }

  /// Generate one initializer. Targets are explicit, making discovery predictable
  /// in monorepos and keeping generated output independent of working directory.
  Future<File> generate({
    required String entrypoint,
    List<String> exclude = const [],
    String? classNamePattern,
    String? fileNamePattern,
    String? moduleName,
    String? output,
    bool check = false,
  }) async {
    final entry = _read(root.uri.resolve(entrypoint).toFilePath());
    final annotation = entry.initializer;
    if (annotation == null) {
      throw GenerationException(
        '$entrypoint has no @InjectableInit annotation.',
      );
    }
    final dirs = annotation.strings('generateForDir');
    final directories = dirs.isEmpty ? ['lib'] : dirs;
    final files = <String>{entry.path};
    final excluded = exclude
        .map((e) => root.uri.resolve(e).toFilePath())
        .toList();
    for (final directory in directories) {
      final dir = Directory.fromUri(root.uri.resolve(directory));
      if (!dir.existsSync()) {
        throw GenerationException('Input directory does not exist: $directory');
      }
      void collect(Directory folder) {
        for (final entity in folder.listSync(followLinks: false)) {
          final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (name.startsWith('.') ||
              excluded.any(
                (e) =>
                    entity.path == e ||
                    entity.path.startsWith('$e${Platform.pathSeparator}'),
              )) {
            continue;
          }
          if (entity is Directory) {
            collect(entity);
          } else if (entity is File &&
              name.endsWith('.dart') &&
              !name.endsWith('.config.dart') &&
              !name.endsWith('.module.dart') &&
              !name.endsWith('.di_engine.tmp.dart')) {
            files.add(entity.absolute.path);
          }
        }
      }

      collect(dir);
    }

    final classes = [
      for (final file in files.toList()..sort()) ..._read(file).classes,
    ];
    final registrations = <_Registration>[];
    final classPattern = classNamePattern == null
        ? null
        : RegExp(classNamePattern);
    final filePattern = fileNamePattern == null
        ? null
        : RegExp(fileNamePattern);
    for (final declaration in classes) {
      if (_annotation(declaration.annotations, {'module', 'Module'}) != null) {
        for (final member in declaration.members) {
          if (member.constructor ||
              member.name.startsWith('_') ||
              member.type == 'void') {
            continue;
          }
          registrations.add(_registration(declaration, member, module: true));
        }
        continue;
      }
      final marked = _annotation(declaration.annotations, _lifetimes) != null;
      final convention =
          !declaration.abstractClass &&
          ((classPattern?.hasMatch(declaration.name) ?? false) ||
              (filePattern?.hasMatch(declaration.source.path) ?? false));
      if (!marked && !convention) continue;
      if (declaration.name.startsWith('_')) {
        throw GenerationException(
          '${declaration.name}: injectable classes must be public.',
        );
      }
      if (declaration.generic) {
        throw GenerationException(
          '${declaration.name}: generic injectable classes need a concrete module provider.',
        );
      }
      final factories = declaration.members
          .where(
            (m) =>
                _annotation(m.annotations, {
                  'factoryMethod',
                  'FactoryMethod',
                }) !=
                null,
          )
          .toList();
      if (factories.length > 1) {
        throw GenerationException(
          '${declaration.name}: mark only one creation method with @factoryMethod.',
        );
      }
      Member? member = factories.isEmpty ? null : factories.single;
      if (member != null && !member.constructor && !member.isStatic) {
        throw GenerationException(
          '${declaration.name}: a factory method must be static or a constructor.',
        );
      }
      final constructors = declaration.members
          .where((m) => m.constructor)
          .toList();
      member ??= constructors.where((m) => m.name.isEmpty).firstOrNull;
      if (member == null && constructors.isNotEmpty) {
        throw GenerationException(
          '${declaration.name}: mark the named constructor with @factoryMethod.',
        );
      }
      member ??= Member('', declaration.name, [], [], constructor: true);
      if (declaration.abstractClass &&
          member.constructor &&
          factories.isEmpty) {
        throw GenerationException(
          '${declaration.name}: abstract bindings require a concrete implementation or a factory method.',
        );
      }
      for (final p in member.parameters.where((p) => p.type.isEmpty)) {
        ClassDeclaration? parent = classes
            .where((c) => c.name == declaration.parent)
            .firstOrNull;
        while (parent != null && p.type.isEmpty) {
          p.type =
              parent.fields[p.name] ??
              parent.members
                  .expand((m) => m.parameters)
                  .where((v) => v.name == p.name)
                  .firstOrNull
                  ?.type ??
              '';
          parent = classes.where((c) => c.name == parent?.parent).firstOrNull;
        }
        if (p.type.isEmpty) {
          throw GenerationException(
            '${declaration.name}.${p.name}: declare the parameter type explicitly.',
          );
        }
      }
      registrations.add(_registration(declaration, member));
    }
    final micro =
        annotation.name.endsWith('.microPackage') ||
        annotation.base == 'microPackageInit';
    final outputPath = output == null
        ? entry.path.replaceFirst(
            RegExp(r'\.dart$'),
            micro ? '.module.dart' : '.config.dart',
          )
        : root.uri.resolve(output).toFilePath();
    final emitter = _Emitter(
      this,
      entry,
      annotation,
      registrations,
      outputPath,
      moduleName,
      micro,
    );
    final code = emitter.build();
    // Syntax errors in the output must be found before replacing a good file.
    // dart format is part of the SDK and validates the emitted Dart grammar.
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    // Keep formatter inputs out of source discovery and IDE analysis, including
    // when --watch and the analyzer run at the same time.
    final cache = Directory('${root.path}/.dart_tool/di_engine_codegen')
      ..createSync(recursive: true);
    final staging = cache.createTempSync('format_');
    final temporary = File('${staging.path}/generated.dart');
    try {
      temporary.writeAsStringSync(code);
      final formatted = await Process.run(Platform.resolvedExecutable, [
        'format',
        temporary.path,
      ]);
      if (formatted.exitCode != 0) {
        throw GenerationException(
          'Emitted invalid Dart for $entrypoint:\n${formatted.stderr}',
        );
      }
      final next = temporary.readAsStringSync();
      if (!file.existsSync() || file.readAsStringSync() != next) {
        if (check) {
          throw GenerationException(
            'Generated file is missing or stale: $outputPath. Run the generator without --check.',
          );
        }
        file.writeAsStringSync(next);
      }
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
    return file;
  }
}

const _lifetimes = {
  'injectable',
  'Injectable',
  'singleton',
  'Singleton',
  'lazySingleton',
  'LazySingleton',
};
Annotation? _annotation(List<Annotation> values, Set<String> names) =>
    values.where((a) => names.contains(a.base)).firstOrNull;
String? _instanceName(List<Annotation> annotations, String ownerName) {
  final name = _annotation(annotations, {'Named', 'named'});
  if (name == null) return null;
  if (name.base == 'named') return ownerName;
  if (name.name.endsWith('.from')) {
    return compact(text(name.positional.first)).split('.').last;
  }
  return name.positional.isEmpty
      ? ownerName
      : literal(text(name.positional.first));
}

_Registration _registration(
  ClassDeclaration owner,
  Member member, {
  bool module = false,
}) {
  final annotations = module ? member.annotations : owner.annotations;
  final lifetime = _annotation(annotations, _lifetimes);
  final factory = _annotation(member.annotations, {
    'factoryMethod',
    'FactoryMethod',
  });
  final scope = _annotation(annotations, {'Scope'});
  final order = _annotation(annotations, {'Order'});
  final environments = <String>{...lifetime?.strings('env') ?? []};
  for (final a in annotations) {
    if (a.base == 'Environment' && a.positional.isNotEmpty) {
      environments.add(literal(text(a.positional.first)));
    }
    if ({'dev', 'prod', 'test'}.contains(a.base)) environments.add(a.base);
  }
  final posts = owner.members
      .where(
        (m) =>
            _annotation(m.annotations, {'postConstruct', 'PostConstruct'}) !=
            null,
      )
      .toList();
  final disposers = owner.members
      .where(
        (m) =>
            _annotation(m.annotations, {'disposeMethod', 'DisposeMethod'}) !=
            null,
      )
      .toList();
  if (!module && (posts.length > 1 || disposers.length > 1)) {
    throw GenerationException(
      '${owner.name}: use at most one initialization hook and one disposal method.',
    );
  }
  final post = module ? null : posts.firstOrNull;
  final postAnnotation = post == null
      ? null
      : _annotation(post.annotations, {'postConstruct', 'PostConstruct'});
  if (post != null &&
      (post.parameters.isNotEmpty ||
          post.isStatic ||
          post.name.startsWith('_'))) {
    throw GenerationException(
      '${owner.name}: initialization hooks must be public instance methods without arguments.',
    );
  }
  final disposer = module ? null : disposers.firstOrNull;
  if (disposer != null &&
      (disposer.parameters.isNotEmpty ||
          disposer.isStatic ||
          disposer.name.startsWith('_'))) {
    throw GenerationException(
      '${owner.name}: disposal hooks must be public instance methods without arguments.',
    );
  }
  final type = text(lifetime?.value('as') ?? []).trim();
  final resultType = module ? _unwrapFuture(member.type) : owner.name;
  final asynchronous =
      compact(member.type).startsWith('Future<') ||
      (post != null && compact(post.type).startsWith('Future<'));
  final kind = lifetime?.base.toLowerCase();
  final life = kind == 'singleton'
      ? 'singleton'
      : kind == 'lazysingleton'
      ? 'lazySingleton'
      : (lifetime?.flag('cache') ?? false)
      ? 'cachedFactory'
      : 'factory';
  final registration = _Registration(
    owner: owner,
    member: member,
    type: type.isEmpty ? resultType : type,
    lifetime: life,
    name: _instanceName(annotations, owner.name),
    environments: environments,
    scope: scope?.positional.isNotEmpty == true
        ? literal(text(scope!.positional.first))
        : lifetime?.stringValue('scope'),
    order:
        int.tryParse(
          order?.positional.isNotEmpty == true
              ? compact(text(order!.positional.first))
              : compact(text(lifetime?.value('order') ?? [])),
        ) ??
        0,
    preResolve:
        factory?.flag('preResolve') == true ||
        postAnnotation?.flag('preResolve') == true ||
        _annotation(member.annotations, {'preResolve', 'PreResolve'}) != null,
    dispose: lifetime?.value('dispose') == null
        ? null
        : text(lifetime!.value('dispose')!),
    disposeMethod: disposer,
    postConstruct: post,
    signalsReady: lifetime?.flag('signalsReady') ?? false,
    module: module,
    asynchronous: asynchronous,
  );
  if (registration.runtime.length > 2) {
    throw GenerationException(
      '${owner.name}: use a record or parameter object for more than two @factoryParam values.',
    );
  }
  if (registration.runtime.isNotEmpty &&
      (life != 'factory' || registration.preResolve)) {
    throw GenerationException(
      '${owner.name}: runtime arguments are supported by transient factories only.',
    );
  }
  return registration;
}

String _unwrapFuture(String type) {
  final tokens = tokenize(type);
  if (tokens.length > 3 && tokens.first == 'Future' && tokens[1] == '<') {
    return text(tokens.sublist(2, tokens.length - 1));
  }
  return type;
}

class _Emitter {
  final DependencyGenerator generator;
  final DartSource entry;
  final Annotation annotation;
  final List<_Registration> registrations;
  final String output;
  final String? moduleName;
  final bool micro;
  final Map<String, String> imports = {};
  final Map<ClassDeclaration, String> modules = {};
  _Emitter(
    this.generator,
    this.entry,
    this.annotation,
    this.registrations,
    this.output,
    this.moduleName,
    this.micro,
  );

  String _uriFor(String path) {
    final sdkLib =
        '${File(Platform.resolvedExecutable).parent.parent.path}/lib/';
    if (path.startsWith(sdkLib)) {
      return 'dart:${path.substring(sdkLib.length).split('/').first}';
    }
    final ownRoot = '${generator.root.absolute.path}/';
    for (final package in generator._packageRoots.entries) {
      if (path.startsWith(package.value) && !path.startsWith(ownRoot)) {
        return 'package:${package.key}/${path.substring(package.value.length)}';
      }
    }
    final ownLib = '${ownRoot}lib/';
    if (annotation.value('preferRelativeImports') != null &&
        !annotation.flag('preferRelativeImports') &&
        path.startsWith(ownLib)) {
      final spec = File(
        '${generator.root.path}/pubspec.yaml',
      ).readAsStringSync();
      final name = RegExp(
        r'^name:\s*(\S+)',
        multiLine: true,
      ).firstMatch(spec)?.group(1);
      if (name != null) return 'package:$name/${path.substring(ownLib.length)}';
    }
    final from = File(
      output,
    ).parent.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final to = File(
      path,
    ).absolute.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    var shared = 0;
    while (shared < from.length &&
        shared < to.length &&
        from[shared] == to[shared]) {
      shared++;
    }
    return [
      ...List.filled(from.length - shared, '..'),
      ...to.skip(shared),
    ].join('/');
  }

  String _import(String uri) =>
      imports.putIfAbsent(uri, () => '_i${imports.length + 1}');
  String _source(DartSource source) => _import(_uriFor(source.path));

  static final _builtins = {
    'void',
    'dynamic',
    'Never',
    'Null',
    'Object',
    'Type',
    'Symbol',
    'Function',
    'String',
    'bool',
    'num',
    'int',
    'double',
    'List',
    'Set',
    'Map',
    'Iterable',
    'Iterator',
    'MapEntry',
    'Future',
    'Stream',
    'Record',
    'DateTime',
    'Duration',
    'RegExp',
    'Uri',
    'BigInt',
    'Error',
    'Exception',
    'StackTrace',
    'StringBuffer',
    'Comparable',
    'Enum',
    'Pattern',
    'required',
    'covariant',
  };
  String _symbol(String name, DartSource source) {
    if (_builtins.contains(name)) return name;
    if (name == 'FutureOr') return '${_import('dart:async')}.$name';
    if (source.symbols.contains(name)) return '${_source(source)}.$name';
    final matches = <ImportSpec>[];
    for (final imported in source.imports.where(
      (i) => i.prefix == null && i.exposes(name),
    )) {
      if (imported.uri.startsWith('package:di_engine/')) {
        if ({
          'DIEngine',
          'DIModule',
          'EnvironmentFilter',
          'AsyncDisposable',
          'Disposable',
        }.contains(name)) {
          return '_di.$name';
        }
        continue;
      }
      final path = generator._resolveImport(imported.uri, source);
      if (path != null && generator._origin(path, name, {}) != null) {
        matches.add(imported);
      }
    }
    if (matches.length > 1) {
      throw GenerationException(
        '${source.path}: ambiguous imported symbol $name. Use an import prefix.',
      );
    }
    if (matches.length == 1) {
      final imported = matches.single;
      final path = generator._resolveImport(imported.uri, source)!;
      final origin = generator._origin(path, name, {})!;
      return '${_import(_uriFor(origin))}.$name';
    }
    final local = registrations
        .where((r) => r.owner.name == name)
        .map((r) => r.owner.source)
        .toSet();
    if (local.length == 1) return '${_source(local.single)}.$name';
    // Top-level callback functions need not be injectable declarations.
    return '${_source(source)}.$name';
  }

  String _type(String type, DartSource source) {
    final tokens = tokenize(type);
    final result = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == '(' || token == '{' || token == '[') {
        final end = closing(tokens, i);
        final fields = <String>[];
        for (final field in splitTokens(tokens.sublist(i + 1, end))) {
          final hasLabel =
              field.length > 1 &&
              RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(field.last) &&
              field[field.length - 2] != '.';
          fields.add(
            hasLabel
                ? '${_type(text(field.sublist(0, field.length - 1)), source)} ${field.last}'
                : _type(text(field), source),
          );
        }
        result.add('$token${fields.join(', ')}${tokens[end]}');
        i = end;
        continue;
      }
      if (!RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(token)) {
        result.add(token);
        continue;
      }
      if (i + 2 < tokens.length && tokens[i + 1] == '.') {
        final imported = source.imports
            .where((p) => p.prefix == token)
            .firstOrNull;
        if (imported != null) {
          final path = generator._resolveImport(imported.uri, source);
          final origin = path == null
              ? null
              : generator._origin(path, tokens[i + 2], {});
          final uri = origin == null ? imported.uri : _uriFor(origin);
          result.add('${_import(uri)}.${tokens[i + 2]}');
          i += 2;
          continue;
        }
      }
      // Named record fields are labels rather than type identifiers.
      if (i + 1 < tokens.length && tokens[i + 1] == ':') {
        result.add(token);
        continue;
      }
      if (i > 0 && tokens[i - 1] == '.') {
        result.add(token);
        continue;
      }
      result.add(_symbol(token, source));
    }
    return result.join(' ');
  }

  List<_Registration> _dependencies(_Registration r) => [
    for (final parameter in r.parameters.where((p) => !p.runtime))
      ...registrations.where(
        (candidate) =>
            _normal(_type(candidate.type, candidate.owner.source)) ==
                _normal(_type(parameter.type, r.owner.source)) &&
            candidate.name == _instanceName(parameter.annotations, '') &&
            (candidate.scope == null || candidate.scope == r.scope) &&
            (r.environments.isEmpty ||
                candidate.environments.isEmpty ||
                r.environments.intersection(candidate.environments).isNotEmpty),
      ),
  ];

  List<_Registration> _sort() {
    for (var round = 0; round < registrations.length; round++) {
      var changed = false;
      for (final r in registrations) {
        if (!r.asynchronous && _dependencies(r).any((d) => d.exposedAsync)) {
          r.asynchronous = true;
          changed = true;
        }
      }
      if (!changed) break;
    }
    final sorted = <_Registration>[];
    final active = <_Registration>[];
    void visit(_Registration r) {
      if (sorted.contains(r)) return;
      if (active.contains(r)) {
        throw GenerationException(
          'Circular dependency: ${[...active.map((r) => r.type), r.type].join(' -> ')}',
        );
      }
      active.add(r);
      for (final dependency in _dependencies(r)) {
        visit(dependency);
      }
      active.removeLast();
      sorted.add(r);
    }

    final ordered = [...registrations]
      ..sort((a, b) {
        final priority = a.order.compareTo(b.order);
        return priority != 0
            ? priority
            : registrations.indexOf(a).compareTo(registrations.indexOf(b));
      });
    for (final registration in ordered) {
      visit(registration);
    }
    for (final r in sorted) {
      for (final other in sorted.where(
        (o) =>
            !identical(o, r) &&
            _normal(_type(o.type, o.owner.source)) ==
                _normal(_type(r.type, r.owner.source)) &&
            o.name == r.name &&
            o.scope == r.scope,
      )) {
        if ((r.environments.isEmpty ||
                other.environments.isEmpty ||
                r.environments.intersection(other.environments).isNotEmpty) &&
            !annotation.flag('allowMultipleRegistrations')) {
          throw GenerationException(
            'Duplicate registration for ${r.type}${r.name == null ? '' : ' (${r.name})'}.',
          );
        }
      }
      for (final p in r.parameters.where((p) => !p.runtime && !p.optional)) {
        final candidates = _dependencies(r).where(
          (d) =>
              _normal(_type(d.type, d.owner.source)) ==
                  _normal(_type(p.type, r.owner.source)) &&
              d.name == _instanceName(p.annotations, ''),
        );
        if (candidates.isEmpty &&
            (annotation.value('throwOnMissingDependencies') == null ||
                annotation.flag('throwOnMissingDependencies'))) {
          throw GenerationException(
            '${r.owner.name}.${p.name}: no registration for ${p.type}. Register it in a module, use @factoryParam, or set throwOnMissingDependencies: false for externally provided services.',
          );
        }
      }
    }
    return sorted;
  }

  String _expression(String expression, DartSource source) {
    final tokens = tokenize(expression);
    final result = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (!RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(token) ||
          {
            'const',
            'new',
            'true',
            'false',
            'null',
            'is',
            'as',
          }.contains(token) ||
          (i > 0 && tokens[i - 1] == '.') ||
          (i + 1 < tokens.length &&
              tokens[i + 1] == ':' &&
              (i == 0 || {'(', ',', '{'}.contains(tokens[i - 1])))) {
        result.add(token);
      } else if (i + 2 < tokens.length &&
          tokens[i + 1] == '.' &&
          source.imports.any((p) => p.prefix == token)) {
        result.add(_type('${tokens[i]}.${tokens[i + 2]}', source));
        i += 2;
      } else {
        if (token.startsWith('_')) {
          throw GenerationException(
            'An optional default references private $token in ${source.path}. Use a public constant or a concrete module provider.',
          );
        }
        result.add(_symbol(token, source));
      }
    }
    return result.join(' ');
  }

  String _arguments(_Registration r) {
    var runtimeIndex = 0;
    final result = <String>[];
    for (final parameter in r.parameters) {
      final t = _type(parameter.type, r.owner.source);
      String value;
      if (parameter.runtime) {
        value = '_p${++runtimeIndex}';
      } else {
        final name = _instanceName(parameter.annotations, '');
        final named = name == null ? '' : 'name: ${_quote(name)}';
        value =
            '${r.asynchronous ? 'await ' : ''}engine.${r.asynchronous ? 'resolveAsync' : 'resolve'}<$t>($named)';
        if (parameter.optional) {
          final fallback = _expression(
            parameter.defaultValue ?? 'null',
            r.owner.source,
          );
          value =
              'engine.isRegistered<$t>(${name == null ? '' : 'instanceName: ${_quote(name)}'}) ? $value : $fallback';
        }
      }
      result.add('${parameter.named ? '${parameter.name}: ' : ''}$value');
    }
    return result.join(', ');
  }

  String _factory(_Registration r) {
    final arguments = _arguments(r);
    String call;
    if (r.module) {
      final module = modules.putIfAbsent(
        r.owner,
        () => '_module${modules.length + 1}',
      );
      call = r.member.getter
          ? '$module.${r.member.name}'
          : '$module.${r.member.name}($arguments)';
    } else {
      final impl = _symbol(r.owner.name, r.owner.source);
      call =
          '$impl${r.member.name.isEmpty ? '' : '.${r.member.name}'}($arguments)';
    }
    final memberAsync = compact(r.member.type).startsWith('Future<');
    if (memberAsync) call = 'await $call';
    final hook = r.postConstruct;
    final callback = annotation.flag('usesConstructorCallback');
    if (hook == null && !callback) {
      return '(${r.runtime.map((p) => '_p${r.runtime.indexOf(p) + 1}').join(', ')}) ${r.asynchronous ? 'async ' : ''}=> $call';
    }
    final post = hook == null
        ? ''
        : '${compact(hook.type).startsWith('Future<') ? 'await ' : ''}instance.${hook.name}();';
    final wrapped = callback
        ? 'constructorCallback == null ? instance : constructorCallback<${_type(r.type, r.owner.source)}>(instance)'
        : 'instance';
    return '(${r.runtime.map((p) => '_p${r.runtime.indexOf(p) + 1}').join(', ')}) ${r.asynchronous ? 'async ' : ''}{ final instance = $call; $post return $wrapped; }';
  }

  String _register(_Registration r) {
    final type = _type(r.type, r.owner.source);
    final name = r.name == null ? '' : ', instanceName: ${_quote(r.name!)}';
    String dispose = '';
    if (r.dispose != null) {
      dispose = ', dispose: ${_type(r.dispose!, r.owner.source)}';
    } else if (r.disposeMethod != null) {
      dispose =
          ', dispose: (instance) => (instance as ${_symbol(r.owner.name, r.owner.source)}).${r.disposeMethod!.name}()';
    }
    final ready = r.signalsReady ? ', signalsReady: true' : '';
    final factory = _factory(r);
    String statement;
    if (r.preResolve) {
      if (r.lifetime == 'factory' || r.lifetime == 'cachedFactory') {
        final value = '_preResolved${registrations.indexOf(r)}';
        final method = r.lifetime == 'cachedFactory'
            ? 'registerCachedFactory'
            : 'registerFactory';
        statement =
            'final $value = await ($factory)(); engine.$method<$type>(() => $value$name);';
      } else {
        statement =
            'engine.registerSingleton<$type>(await ($factory)()$name$dispose$ready);';
      }
    } else if (r.runtime.isNotEmpty) {
      final p = r.runtime;
      final p1 = _type(p[0].type, r.owner.source);
      final p2 = p.length > 1 ? _type(p[1].type, r.owner.source) : 'dynamic';
      final wrapper = p.length == 1 ? '(_p1, _) => ($factory)(_p1)' : factory;
      statement =
          'engine.registerFactoryParam${r.asynchronous ? 'Async' : ''}<$type, $p1, $p2>($wrapper$name);';
    } else {
      final method = switch (r.lifetime) {
        'singleton' =>
          r.asynchronous
              ? 'registerSingletonAsync'
              : 'registerSingletonFactory',
        'lazySingleton' =>
          r.asynchronous
              ? 'registerLazySingletonAsync'
              : 'registerLazySingleton',
        'cachedFactory' =>
          r.asynchronous
              ? 'registerCachedFactoryAsync'
              : 'registerCachedFactory',
        _ => r.asynchronous ? 'registerFactoryAsync' : 'registerFactory',
      };
      statement =
          'engine.$method<$type>($factory$name${r.lifetime == 'factory' || r.lifetime == 'cachedFactory' ? '' : dispose}$ready);';
    }
    final condition = r.environments.map(_quote).join(', ');
    return 'if (filter.allows({$condition})) { $statement }';
  }

  List<_External> _external(String name) {
    final values = annotation.value(name);
    if (values == null || values.length < 2) return [];
    final result = <_External>[];
    for (final part in splitTokens(values.sublist(1, values.length - 1))) {
      final open = part.indexOf('(');
      if (open < 0) {
        throw GenerationException('Use ExternalModule(Type) in $name.');
      }
      final value = Annotation(
        'ExternalModule',
        part.sublist(open + 1, closing(part, open)),
      );
      result.add(
        _External(text(value.positional.first), value.stringValue('scope')),
      );
    }
    return result;
  }

  String build() {
    final sorted = _sort();
    final before = _external('externalPackageModulesBefore');
    final after = _external('externalPackageModulesAfter');
    final scopes = <String?>{
      null,
      ...sorted.map((r) => r.scope),
      ...before.map((r) => r.scope),
      ...after.map((r) => r.scope),
    };
    if (micro && scopes.length > 1) {
      throw GenerationException(
        'Micro modules must use one root scope. Attach a scope at the consuming ExternalModule declaration.',
      );
    }
    final sections = <String>[];
    final initName = annotation.stringValue('initializerName') ?? 'init';
    final extension =
        annotation.value('asExtension') == null ||
        annotation.flag('asExtension');
    final callback = annotation.flag('usesConstructorCallback')
        ? ', T Function<T>(T)? constructorCallback'
        : '';
    for (final scope in scopes) {
      final lines = <String>[];
      for (final m in before.where((m) => m.scope == scope)) {
        lines.add(
          'await ${_type(m.type, entry)}().register(engine, environment: environment, environmentFilter: filter);',
        );
      }
      for (final r in sorted.where((r) => r.scope == scope)) {
        lines.add(_register(r));
      }
      for (final m in after.where((m) => m.scope == scope)) {
        lines.add(
          'await ${_type(m.type, entry)}().register(engine, environment: environment, environmentFilter: filter);',
        );
      }
      final method = scope == null ? initName : 'init${_pascal(scope)}Scope';
      final usedModules = sorted
          .where((r) => r.scope == scope && r.module)
          .map((r) => r.owner)
          .toSet();
      final moduleDeclarations = modules.entries
          .where((m) => usedModules.contains(m.key))
          .map((m) => 'final ${m.value} = _DIEngine${m.value.substring(1)}();')
          .join('\n');
      final common =
          '''final filter = environmentFilter ?? _di.SimpleEnvironmentFilter(environment);
$moduleDeclarations
${scope == null && annotation.flag('allowMultipleRegistrations') ? 'engine.enableRegisteringMultipleInstancesOfOneType();' : ''}
${lines.join('\n')}
''';
      if (micro) {
        sections.add(
          '''class ${moduleName ?? _defaultModuleName()} extends _di.DIModule {
@override
Future<void> register(_di.DIEngine engine, {String? environment, _di.EnvironmentFilter? environmentFilter}) async {
$common
}
}''',
        );
      } else {
        final methodCode =
            '''Future<_di.DIEngine> $method(${extension ? '' : '_di.DIEngine engine, '}{String? environment, _di.EnvironmentFilter? environmentFilter$callback}) async {
${extension ? 'final engine = this;' : ''}
${scope == null ? '' : 'engine.pushNewScope(scopeName: ${_quote(scope)});\ntry {'}
$common
return engine;
${scope == null ? '' : '} catch (error, stack) { try { await engine.dropScope(${_quote(scope)}, waitForPending: true); } catch (cleanup, cleanupStack) { throw _di.ScopeRunException(error, stack, cleanup, cleanupStack); } rethrow; }'}
}''';
        sections.add(methodCode);
      }
    }
    if (!micro && annotation.flag('generateAccessors')) {
      final seen = <String>{};
      for (final r in sorted.where((r) => r.runtime.isEmpty)) {
        final getter =
            r.name ?? '${r.type[0].toLowerCase()}${r.type.substring(1)}';
        if (!RegExp(r'^[a-zA-Z_$][\w$]*$').hasMatch(getter) ||
            !seen.add(getter)) {
          continue;
        }
        sections.add(
          '${_type(r.type, r.owner.source)} ${extension ? 'get $getter' : '$getter(_di.DIEngine engine)'} => ${extension ? 'this' : 'engine'}.resolve<${_type(r.type, r.owner.source)}>(${r.name == null ? '' : 'name: ${_quote(r.name!)}'});',
        );
      }
    }
    final helpers = <String>[];
    for (final m in modules.keys) {
      final overrides = <String>[];
      for (final member in m.members.where(
        (m) => m.abstractMember && m.getter,
      )) {
        final type = _type(member.type, m.source);
        overrides.add('@override $type get ${member.name} => $type();');
      }
      helpers.add(
        'class _DIEngine${modules[m]!.substring(1)} extends ${_symbol(m.name, m.source)} { ${overrides.join('\n')} }',
      );
    }
    final body = !micro && extension
        ? 'extension DIEngine${_pascal(initName)}Generated on _di.DIEngine { ${sections.join('\n')} }'
        : sections.join('\n');
    return '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by di_engine's SDK-only generator.
// ignore_for_file: type=lint
import 'package:di_engine/di_engine.dart' as _di;
${imports.entries.map((e) => 'import ${_quote(e.key)} as ${e.value};').join('\n')}
$body
${helpers.join('\n')}
''';
  }

  String _defaultModuleName() {
    final pubspec = File(
      '${generator.root.path}/pubspec.yaml',
    ).readAsStringSync();
    final name =
        RegExp(
          r'^name:\s*(\S+)',
          multiLine: true,
        ).firstMatch(pubspec)?.group(1) ??
        'App';
    return '${_pascal(name)}PackageModule';
  }
}
