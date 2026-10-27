import 'dart:io';

/// A small lexical reader for declaration signatures. Method bodies and strings
/// are balanced/skipped; source text is never executed by the generator.
List<String> tokenize(String source) {
  final result = <String>[];
  var i = 0;
  bool word(int c) =>
      c >= 128 ||
      c >= 65 && c <= 90 ||
      c >= 97 && c <= 122 ||
      c >= 48 && c <= 57 ||
      c == 95 ||
      c == 36;
  while (i < source.length) {
    final c = source[i];
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i + 2);
      i = end < 0 ? source.length : end + 1;
      continue;
    }
    if (source.startsWith('/*', i)) {
      i += 2;
      var depth = 1;
      while (i < source.length && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      if (depth != 0) {
        throw const FormatException('Unterminated block comment.');
      }
      continue;
    }
    final raw =
        (c == 'r' || c == 'R') &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"');
    if (c == "'" || c == '"' || raw) {
      final start = i;
      if (raw) i++;
      final quote = source[i];
      final delimiter = source.startsWith(quote * 3, i) ? quote * 3 : quote;
      i += delimiter.length;
      var ended = false;
      while (i < source.length) {
        if (!raw && source[i] == '\\') {
          i += 2;
          continue;
        }
        if (source.startsWith(delimiter, i)) {
          i += delimiter.length;
          ended = true;
          break;
        }
        i++;
      }
      if (!ended) throw const FormatException('Unterminated string literal.');
      result.add(source.substring(start, i));
      continue;
    }
    if (word(source.codeUnitAt(i))) {
      final start = i++;
      while (i < source.length && word(source.codeUnitAt(i))) {
        i++;
      }
      result.add(source.substring(start, i));
      continue;
    }
    if (source.startsWith('=>', i) ||
        source.startsWith('??', i) ||
        source.startsWith('?.', i)) {
      result.add(source.substring(i, i + 2));
      i += 2;
    } else {
      result.add(c);
      i++;
    }
  }
  return result;
}

const _pairs = {'(': ')', '[': ']', '{': '}', '<': '>'};
int closing(List<String> tokens, int start) {
  final open = tokens[start];
  final end = _pairs[open];
  var depth = 1;
  for (var i = start + 1; i < tokens.length; i++) {
    if (tokens[i] == open) {
      depth++;
    } else if (tokens[i] == end) {
      depth--;
      if (depth == 0) return i;
    }
  }
  throw FormatException(
    'Unbalanced $open near ${tokens.skip(start).take(12).join(' ')}',
  );
}

List<List<String>> splitTokens(List<String> tokens, [String separator = ',']) {
  final result = <List<String>>[];
  var start = 0;
  final stack = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (stack.isEmpty && token == separator) {
      result.add(tokens.sublist(start, i));
      start = i + 1;
    } else if (_pairs.containsKey(token)) {
      stack.add(_pairs[token]!);
    } else if (stack.isNotEmpty && stack.last == token) {
      stack.removeLast();
    }
  }
  if (start < tokens.length) result.add(tokens.sublist(start));
  return result;
}

String text(List<String> tokens) => tokens.join(' ');
String compact(String value) => value.replaceAll(RegExp(r'\s+'), '');
String literal(String value) {
  var s = value.trim();
  final raw =
      s.length > 1 &&
      (s[0] == 'r' || s[0] == 'R') &&
      (s[1] == "'" || s[1] == '"');
  if (raw) s = s.substring(1);
  if (s.length >= 2 && (s.startsWith("'") || s.startsWith('"'))) {
    final width = s.startsWith(s[0] * 3) ? 3 : 1;
    if (raw) return s.substring(width, s.length - width);
    return _decodeString(s.substring(width, s.length - width));
  }
  return s.split('.').last.trim();
}

String _decodeString(String content) {
  final result = StringBuffer();
  const escapes = {
    'n': '\n',
    'r': '\r',
    't': '\t',
    'b': '\b',
    'f': '\f',
    'v': '\v',
    "'": "'",
    '"': '"',
    r'\': r'\',
    r'$': r'$',
  };
  for (var i = 0; i < content.length; i++) {
    final char = content[i];
    if (char == r'$') {
      throw const FormatException(
        'Annotation string interpolation is unsupported; use a literal string.',
      );
    }
    if (char != r'\') {
      result.write(char);
      continue;
    }
    if (++i == content.length) {
      throw const FormatException('Incomplete string escape.');
    }
    final escape = content[i];
    if (escapes.containsKey(escape)) {
      result.write(escapes[escape]);
      continue;
    }
    if (escape != 'u' && escape != 'x') {
      throw FormatException('Unsupported string escape: \\$escape');
    }
    final start = i + 1;
    late int end;
    late String hex;
    if (escape == 'u' && start < content.length && content[start] == '{') {
      end = content.indexOf('}', start + 1);
      if (end < 0) throw const FormatException('Incomplete Unicode escape.');
      hex = content.substring(start + 1, end);
      i = end;
    } else {
      end = start + (escape == 'u' ? 4 : 2);
      if (end > content.length) {
        throw const FormatException('Incomplete character escape.');
      }
      hex = content.substring(start, end);
      i = end - 1;
    }
    final point = int.tryParse(hex, radix: 16);
    if (point == null || point < 0 || point > 0x10ffff) {
      throw FormatException('Invalid character escape: $hex');
    }
    result.writeCharCode(point);
  }
  return result.toString();
}

class Annotation {
  final String name;
  final List<String> arguments;
  Annotation(this.name, this.arguments);
  String get base {
    final parts = name.split('.');
    if ({'from', 'auto', 'microPackage'}.contains(parts.last) &&
        parts.length > 1) {
      parts.removeLast();
    }
    return parts.last;
  }

  List<List<String>> get positional =>
      splitTokens(arguments).where((p) => p.length < 2 || p[1] != ':').toList();
  List<String>? value(String name) {
    for (final part in splitTokens(arguments)) {
      if (part.length >= 2 && part[0] == name && part[1] == ':') {
        return part.sublist(2);
      }
    }
    return null;
  }

  String? stringValue(String name) {
    final v = value(name);
    return v == null ? null : literal(text(v));
  }

  bool flag(String name) => text(value(name) ?? []) == 'true';
  List<String> strings(String name) {
    final values = value(name);
    if (values == null || values.length < 2) return [];
    return [
      for (final part in splitTokens(values.sublist(1, values.length - 1)))
        literal(text(part)),
    ];
  }
}

class Cursor {
  final List<String> tokens;
  int i = 0;
  Cursor(this.tokens);
  bool get done => i >= tokens.length;
  String get current => tokens[i];
  List<Annotation> annotations() {
    final result = <Annotation>[];
    while (!done && current == '@') {
      i++;
      final name = <String>[tokens[i++]];
      while (!done && current == '.') {
        name
          ..add(tokens[i++])
          ..add(tokens[i++]);
      }
      var args = <String>[];
      if (!done && current == '(') {
        final end = closing(tokens, i);
        args = tokens.sublist(i + 1, end);
        i = end + 1;
      }
      result.add(Annotation(name.join(), args));
    }
    return result;
  }
}

class ImportSpec {
  final String uri;
  final String? prefix;
  final Set<String> show;
  final Set<String> hide;
  ImportSpec(this.uri, this.prefix, this.show, this.hide);
  bool exposes(String name) =>
      !hide.contains(name) && (show.isEmpty || show.contains(name));
}

class Parameter {
  String type;
  final String name;
  final bool named;
  final bool optional;
  final String? defaultValue;
  final List<Annotation> annotations;
  Parameter(
    this.type,
    this.name,
    this.named,
    this.optional,
    this.defaultValue,
    this.annotations,
  );
  bool get runtime => annotations.any(
    (a) => a.base == 'factoryParam' || a.base == 'FactoryParam',
  );
}

class Member {
  final String name;
  final String type;
  final List<Parameter> parameters;
  final List<Annotation> annotations;
  final bool constructor;
  final bool getter;
  final bool isStatic;
  final bool abstractMember;
  Member(
    this.name,
    this.type,
    this.parameters,
    this.annotations, {
    this.constructor = false,
    this.getter = false,
    this.isStatic = false,
    this.abstractMember = false,
  });
}

class ClassDeclaration {
  final String name;
  final String? parent;
  final bool abstractClass;
  final bool generic;
  final List<Annotation> annotations;
  final Map<String, String> fields;
  final List<Member> members;
  final DartSource source;
  ClassDeclaration(
    this.name,
    this.parent,
    this.abstractClass,
    this.generic,
    this.annotations,
    this.fields,
    this.members,
    this.source,
  );
}

class DartSource {
  final String path;
  final List<ImportSpec> imports = [];
  final List<String> exports = [];
  final List<String> parts = [];
  final Set<String> symbols = {};
  final List<ClassDeclaration> classes = [];
  Annotation? initializer;
  DartSource(this.path);

  factory DartSource.read(String path, {bool signatures = true}) {
    final source = DartSource(path);
    final c = Cursor(tokenize(File(path).readAsStringSync()));
    while (!c.done) {
      final annotations = c.annotations();
      if (c.done) break;
      if (c.current == 'part' &&
          c.i + 1 < c.tokens.length &&
          c.tokens[c.i + 1] != 'of') {
        source.parts.add(literal(c.tokens[c.i + 1]));
        while (!c.done && c.current != ';') {
          c.i++;
        }
        if (!c.done) c.i++;
        continue;
      }
      if (c.current == 'import' || c.current == 'export') {
        final export = c.current == 'export';
        c.i++;
        final uri = literal(c.tokens[c.i++]);
        final rest = <String>[];
        while (!c.done && c.current != ';') {
          rest.add(c.tokens[c.i++]);
        }
        if (!c.done) c.i++;
        String? prefix;
        final show = <String>{};
        final hide = <String>{};
        Set<String>? mode;
        for (var i = 0; i < rest.length; i++) {
          if (rest[i] == 'as' && i + 1 < rest.length) {
            prefix = rest[++i];
          } else if (rest[i] == 'show') {
            mode = show;
          } else if (rest[i] == 'hide') {
            mode = hide;
          } else if (rest[i] != ',') {
            mode?.add(rest[i]);
          }
        }
        if (export) {
          source.exports.add(uri);
        } else {
          source.imports.add(ImportSpec(uri, prefix, show, hide));
        }
        continue;
      }
      for (final a in annotations) {
        if (a.base == 'InjectableInit' ||
            a.base == 'injectableInit' ||
            a.base == 'microPackageInit') {
          source.initializer = a;
        }
      }
      final start = c.i;
      var classIndex = -1;
      for (var j = c.i; j < c.tokens.length; j++) {
        if (c.tokens[j] == 'class') {
          classIndex = j;
          break;
        }
        if (['{', ';', '=>', '('].contains(c.tokens[j])) break;
      }
      if (classIndex >= 0) {
        final name = c.tokens[classIndex + 1];
        source.symbols.add(name);
        var open = classIndex + 2;
        while (open < c.tokens.length && c.tokens[open] != '{') {
          open++;
        }
        if (open == c.tokens.length) {
          throw FormatException('$path: missing class body for $name');
        }
        final header = c.tokens.sublist(classIndex + 2, open);
        final parentIndex = header.indexOf('extends');
        final parent = parentIndex < 0 ? null : header[parentIndex + 1];
        final end = closing(c.tokens, open);
        final fields = <String, String>{};
        final members = signatures
            ? _members(name, c.tokens.sublist(open + 1, end), fields)
            : <Member>[];
        source.classes.add(
          ClassDeclaration(
            name,
            parent,
            c.tokens.sublist(start, classIndex).contains('abstract'),
            header.isNotEmpty && header.first == '<',
            annotations,
            fields,
            members,
            source,
          ),
        );
        c.i = end + 1;
        continue;
      }
      if ((c.current == 'typedef' ||
              c.current == 'enum' ||
              c.current == 'mixin') &&
          c.i + 1 < c.tokens.length) {
        source.symbols.add(c.tokens[c.i + 1]);
      }
      // Skip a top-level declaration without examining its executable body.
      while (!c.done && c.current != ';' && c.current != '{') {
        if (c.current == '(' || c.current == '[') {
          c.i = closing(c.tokens, c.i) + 1;
        } else {
          c.i++;
        }
      }
      if (!c.done && c.current == '{') c.i = closing(c.tokens, c.i);
      if (!c.done) c.i++;
    }
    return source;
  }
}

List<Member> _members(
  String className,
  List<String> tokens,
  Map<String, String> fields,
) {
  final members = <Member>[];
  final pendingFormals = <Parameter>[];
  final c = Cursor(tokens);
  while (!c.done) {
    final annotations = c.annotations();
    if (c.done) break;
    final start = c.i;
    int? signatureEnd;
    var first = start;
    while (first < tokens.length &&
        {
          'static',
          'late',
          'final',
          'const',
          'external',
          'factory',
          'covariant',
        }.contains(tokens[first])) {
      first++;
    }
    final constructorHeader =
        first + 1 < tokens.length &&
        tokens[first] == className &&
        {'(', '.'}.contains(tokens[first + 1]);
    final stack = <String>[];
    while (!c.done) {
      final t = c.current;
      if (stack.isEmpty && t == ':' && constructorHeader) {
        signatureEnd = c.i;
        while (!c.done && c.current != '{' && c.current != ';') {
          if (c.current == '(' || c.current == '[') {
            c.i = closing(tokens, c.i) + 1;
          } else {
            c.i++;
          }
        }
        break;
      }
      if (stack.isEmpty && t == '=' && !constructorHeader) {
        signatureEnd = c.i;
        c.i++;
        while (!c.done && c.current != ';') {
          if ({'(', '[', '{'}.contains(c.current)) {
            c.i = closing(tokens, c.i) + 1;
          } else {
            c.i++;
          }
        }
        break;
      }
      if (stack.isEmpty && (t == ';' || t == '=>' || t == '{')) break;
      if (_pairs.containsKey(t)) {
        stack.add(_pairs[t]!);
      } else if (stack.isNotEmpty && stack.last == t) {
        stack.removeLast();
      }
      c.i++;
    }
    final header = tokens.sublist(start, signatureEnd ?? c.i);
    final abstractMember = !c.done && c.current == ';';
    if (!c.done && c.current == '{') {
      c.i = closing(tokens, c.i) + 1;
    } else {
      while (!c.done && c.current != ';') {
        if (_pairs.containsKey(c.current)) {
          c.i = closing(tokens, c.i) + 1;
        } else {
          c.i++;
        }
      }
      if (!c.done) c.i++;
    }
    if (header.isEmpty) continue;
    final modifiers = {
      'static',
      'external',
      'abstract',
      'late',
      'final',
      'const',
      'factory',
      'covariant',
    };
    final h = [...header];
    final isStatic = h.contains('static');
    while (h.isNotEmpty && modifiers.contains(h.first)) {
      h.removeAt(0);
    }
    if (h.isEmpty) continue;
    var paramStart = -1;
    for (var j = 0; j < h.length; j++) {
      if (h[j] == '=') break;
      if (h[j] == '(') {
        final end = closing(h, j);
        if (j > 0 && RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(h[j - 1])) {
          paramStart = j;
          break;
        }
        j = end;
      }
      if (h[j] == '<' || h[j] == '[' || h[j] == '{') j = closing(h, j);
    }
    if (paramStart >= 0) {
      final end = closing(h, paramStart);
      final constructor = h.first == className;
      final name = constructor
          ? (paramStart > 1 && h[1] == '.' ? h[2] : '')
          : h[paramStart - 1];
      final type = constructor ? className : text(h.sublist(0, paramStart - 1));
      final params = _parameters(h.sublist(paramStart + 1, end));
      for (final p in params) {
        if (p.type.isEmpty) pendingFormals.add(p);
      }
      members.add(
        Member(
          name,
          type,
          params,
          annotations,
          constructor: constructor,
          isStatic: isStatic,
          abstractMember: abstractMember,
        ),
      );
    } else if (h.contains('get')) {
      final getIndex = h.indexOf('get');
      members.add(
        Member(
          h[getIndex + 1],
          text(h.sublist(0, getIndex)),
          [],
          annotations,
          getter: true,
          isStatic: isStatic,
          abstractMember: abstractMember,
        ),
      );
    } else {
      final equal = h.indexOf('=');
      final left = equal < 0 ? h : h.sublist(0, equal);
      if (left.length < 2 || left.first == 'set') continue;
      final name = left.last;
      final type = text(left.sublist(0, left.length - 1));
      fields[name] = type;
      if (!name.startsWith('_')) {
        members.add(
          Member(name, type, [], annotations, getter: true, isStatic: isStatic),
        );
      }
    }
  }
  for (final param in pendingFormals) {
    param.type = fields[param.name] ?? '';
  }
  return members;
}

List<Parameter> _parameters(List<String> tokens) {
  final result = <Parameter>[];
  var named = false;
  var optional = false;
  final stack = <String>[];
  var buffer = <String>[];
  void flush() {
    if (buffer.isEmpty) return;
    final c = Cursor(buffer);
    final annotations = c.annotations();
    var required = false;
    while (!c.done && ['required', 'covariant', 'final'].contains(c.current)) {
      required |= c.current == 'required';
      c.i++;
    }
    final values = buffer.sublist(c.i);
    final equal = values.indexOf('=');
    final defaultValue = equal < 0 ? null : text(values.sublist(equal + 1));
    final left = equal < 0 ? values : values.sublist(0, equal);
    if (left.isEmpty) throw const FormatException('Missing parameter name.');
    final formal = left.indexWhere((t) => t == 'this' || t == 'super');
    final type = formal >= 0
        ? text(left.sublist(0, formal))
        : text(left.sublist(0, left.length - 1));
    result.add(
      Parameter(
        type,
        left.last,
        named,
        optional && !required,
        defaultValue,
        annotations,
      ),
    );
    buffer = [];
  }

  for (final token in tokens) {
    if (stack.isEmpty && (token == '{' || token == '[') && buffer.isEmpty) {
      named = token == '{';
      optional = true;
      continue;
    }
    if (stack.isEmpty && (token == '}' || token == ']')) {
      flush();
      named = false;
      optional = false;
      continue;
    }
    if (stack.isEmpty && token == ',') {
      flush();
      continue;
    }
    if (_pairs.containsKey(token)) {
      stack.add(_pairs[token]!);
    } else if (stack.isNotEmpty && stack.last == token) {
      stack.removeLast();
    }
    buffer.add(token);
  }
  flush();
  return result;
}
