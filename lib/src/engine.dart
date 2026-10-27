import 'dart:async';

import 'disposable.dart';
import 'exceptions.dart';
import 'registration_type.dart';

typedef _Key = (Type, String?);
typedef EngineDisposer<T> = FutureOr<void> Function(T instance);

/// Optional asynchronous lifecycle contract for container-owned objects.
abstract interface class AsyncDisposable {
  FutureOr<void> dispose();
}

class _Entry {
  final _Key key;
  final RegistrationType lifetime;
  final Object? Function(dynamic, dynamic)? create;
  final Future<Object?> Function(dynamic, dynamic)? createAsync;
  final EngineDisposer<Object?>? disposer;
  final bool signalsReady;
  final Completer<void> ready = Completer<void>();
  Object? instance;
  bool hasInstance;
  Future<Object?>? pending;

  _Entry(
    this.key,
    this.lifetime, {
    this.create,
    this.createAsync,
    this.disposer,
    this.instance,
    this.hasInstance = false,
    this.signalsReady = false,
  });

  bool get owned =>
      lifetime == RegistrationType.singleton ||
      lifetime == RegistrationType.lazySingleton;

  bool get retains => owned || lifetime == RegistrationType.cachedFactory;

  Future<void> release([EngineDisposer<Object?>? override]) async {
    if (!hasInstance || !owned) return;
    final value = instance;
    instance = null;
    hasInstance = false;
    final callback = override ?? disposer;
    if (callback != null) {
      await callback(value);
    } else if (value is AsyncDisposable) {
      await value.dispose();
    } else if (value is Disposable) {
      value.dispose();
    }
  }
}

class _Resolution {
  final _Entry entry;
  bool active = true;
  _Resolution(this.entry);
}

class _EngineScope {
  final String name;
  final Map<_Key, List<_Entry>> entries = {};
  final List<_Entry> order = [];
  _EngineScope(this.name);
}

/// An independent dependency injection engine. Uses only Dart SDK libraries.
///
/// Named registrations, scopes, runtime factory arguments, async initialization,
/// nullable values, cycle diagnostics, readiness, and aggregated cleanup share a
/// single registry. Async factories use Zone-local resolution paths so unrelated
/// concurrent requests do not produce false cycle errors.
class DIEngine {
  static final Object _pathKey = Object();
  static final Object _cleanupKey = Object();
  final List<_EngineScope> _scopes = [_EngineScope('baseScope')];
  bool _disposed = false;
  bool _cleaning = false;
  bool _multiple = false;
  int _creating = 0;
  Future<void>? _closing;
  Completer<void>? _idle;
  final Map<_Entry, Map<_Entry, int>> _waiting = {};

  DIEngine();
  DIEngine.asNewInstance();

  bool get isDisposed => _disposed;
  String get currentScopeName => _scopes.last.name;
  List<_Entry> get _path => [
    for (final frame
        in (Zone.current[_pathKey]
                as Map<DIEngine, List<_Resolution>>?)?[this] ??
            <_Resolution>[])
      if (frame.active) frame.entry,
  ];

  void _checkActive() {
    if (_disposed || _cleaning) {
      throw StateError('Engine is disposed or cleaning up.');
    }
  }

  void _checkMutable({bool structural = false}) {
    _checkActive();
    if (_path.isNotEmpty || (structural && _creating != 0)) {
      throw StateError('Cannot change dependency lifetimes during creation.');
    }
  }

  void _finishCreation() {
    _creating--;
    if (_creating == 0) {
      _idle?.complete();
      _idle = null;
    }
  }

  void _add(_Entry entry) {
    _checkMutable();
    final entries = _scopes.last.entries.putIfAbsent(entry.key, () => []);
    if (entries.isNotEmpty && !_multiple) {
      throw DependencyAlreadyRegisteredException(entry.key.$1);
    }
    entries.add(entry);
    _scopes.last.order.add(entry);
  }

  _Entry? _find(Type type, String? name) {
    for (final scope in _scopes.reversed) {
      final entries = scope.entries[(type, name)];
      if (entries != null && entries.isNotEmpty) return entries.last;
    }
    return null;
  }

  _Entry _require<T>(String? name) {
    _checkActive();
    return _find(T, name) ?? (throw DependencyNotRegisteredException(T));
  }

  void registerSingleton<T>(
    T instance, {
    String? instanceName,
    EngineDisposer<T>? dispose,
    bool signalsReady = false,
  }) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.singleton,
        instance: instance,
        hasInstance: true,
        signalsReady: signalsReady,
        disposer: dispose == null ? null : (value) => dispose(value as T),
      ),
    );
  }

  /// Creates an eager singleton inside the engine's guarded resolution context.
  void registerSingletonFactory<T>(
    T Function() factory, {
    String? instanceName,
    EngineDisposer<T>? dispose,
    bool signalsReady = false,
  }) {
    final entry = _Entry(
      (T, instanceName),
      RegistrationType.singleton,
      create: (_, _) => factory(),
      signalsReady: signalsReady,
      disposer: dispose == null ? null : (value) => dispose(value as T),
    );
    _add(entry);
    try {
      _sync(entry, null, null);
    } catch (_) {
      final scope = _scopes.last;
      scope.order.remove(entry);
      final entries = scope.entries[entry.key]!;
      entries.remove(entry);
      if (entries.isEmpty) scope.entries.remove(entry.key);
      rethrow;
    }
  }

  void registerLazySingleton<T>(
    T Function() factory, {
    String? instanceName,
    EngineDisposer<T>? dispose,
  }) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.lazySingleton,
        create: (_, _) => factory(),
        disposer: dispose == null ? null : (value) => dispose(value as T),
      ),
    );
  }

  void registerFactory<T>(T Function() factory, {String? instanceName}) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.factory,
        create: (_, _) => factory(),
      ),
    );
  }

  /// A strongly cached factory. Invalidate explicitly with [resetCachedFactory].
  /// Factory products are caller-owned, including cached products.
  void registerCachedFactory<T>(T Function() factory, {String? instanceName}) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.cachedFactory,
        create: (_, _) => factory(),
      ),
    );
  }

  void registerCachedFactoryAsync<T>(
    Future<T> Function() factory, {
    String? instanceName,
  }) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.cachedFactory,
        createAsync: (_, _) async => factory(),
      ),
    );
  }

  void registerFactoryParam<T, P1, P2>(
    T Function(P1, P2) factory, {
    String? instanceName,
  }) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.factory,
        create: (p1, p2) => factory(p1 as P1, p2 as P2),
      ),
    );
  }

  void registerFactoryAsync<T>(
    Future<T> Function() factory, {
    String? instanceName,
  }) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.factory,
        createAsync: (_, _) async => factory(),
      ),
    );
  }

  void registerFactoryParamAsync<T, P1, P2>(
    Future<T> Function(P1, P2) factory, {
    String? instanceName,
  }) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.factory,
        createAsync: (p1, p2) async => factory(p1 as P1, p2 as P2),
      ),
    );
  }

  void registerLazySingletonAsync<T>(
    Future<T> Function() factory, {
    String? instanceName,
    EngineDisposer<T>? dispose,
  }) {
    _add(
      _Entry(
        (T, instanceName),
        RegistrationType.lazySingleton,
        createAsync: (_, _) async => factory(),
        disposer: dispose == null ? null : (value) => dispose(value as T),
      ),
    );
  }

  void registerSingletonAsync<T>(
    Future<T> Function() factory, {
    String? instanceName,
    EngineDisposer<T>? dispose,
    bool signalsReady = false,
  }) {
    final entry = _Entry(
      (T, instanceName),
      RegistrationType.singleton,
      createAsync: (_, _) async => factory(),
      signalsReady: signalsReady,
      disposer: dispose == null ? null : (value) => dispose(value as T),
    );
    _add(entry);
    // Defer eager work until synchronous registration has finished.
    _creating++;
    entry.pending = Future<Object?>.microtask(() async {
      try {
        return await _constructAsync(entry, null, null);
      } finally {
        _finishCreation();
      }
    });
    _observeFailure(entry.pending!);
  }

  static void _observeFailure(Future<Object?> pending) {
    // Keep eager failures observable through resolveAsync/allReady, without an
    // unhandled-zone error before the application has a chance to await them.
    pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  R _inPath<R>(_Entry entry, R Function() body, {bool asynchronous = false}) {
    final path = _path;
    if (path.contains(entry)) {
      throw CircularDependencyException([
        ...path.map((e) => e.key.$1),
        entry.key.$1,
      ]);
    }
    final inherited =
        Zone.current[_pathKey] as Map<DIEngine, List<_Resolution>>?;
    final frame = _Resolution(entry);
    return runZoned(
      () {
        try {
          final result = body();
          if (asynchronous && result is Future) {
            result.then<void>(
              (_) {
                frame.active = false;
              },
              onError: (Object _, StackTrace _) {
                frame.active = false;
              },
            );
          } else {
            frame.active = false;
          }
          return result;
        } catch (_) {
          frame.active = false;
          rethrow;
        }
      },
      zoneValues: {
        _pathKey: {
          ...?inherited,
          this: [...?inherited?[this], frame],
        },
      },
    );
  }

  List<_Entry>? _waitPath(_Entry current, _Entry target, Set<_Entry> visited) {
    if (identical(current, target)) return [current];
    if (!visited.add(current)) return null;
    for (final next in _waiting[current]?.keys ?? <_Entry>[]) {
      final path = _waitPath(next, target, visited);
      if (path != null) return [current, ...path];
    }
    return null;
  }

  Object? _sync(_Entry entry, dynamic p1, dynamic p2) {
    if (entry.hasInstance) return entry.instance;
    if (entry.createAsync != null) {
      throw StateError('Use resolveAsync for ${entry.key.$1}.');
    }
    return _inPath(entry, () {
      _creating++;
      try {
        final value = entry.create!(p1, p2);
        if (entry.retains) {
          entry.instance = value;
          entry.hasInstance = true;
        }
        return value;
      } finally {
        _finishCreation();
      }
    });
  }

  Future<Object?> _constructAsync(_Entry entry, dynamic p1, dynamic p2) =>
      _inPath(entry, () async {
        _creating++;
        try {
          final value = await entry.createAsync!(p1, p2);
          if (entry.retains) {
            entry.instance = value;
            entry.hasInstance = true;
          }
          return value;
        } finally {
          _finishCreation();
        }
      }, asynchronous: true);

  Future<Object?> _async(_Entry entry, dynamic p1, dynamic p2) {
    final parent = _path.where((entry) => entry.retains).lastOrNull;
    if (parent == null ||
        !entry.retains ||
        entry.hasInstance ||
        _path.contains(entry)) {
      return _asyncValue(entry, p1, p2);
    }
    // Zone paths catch recursive construction. The wait graph also catches
    // cycles between factories started by independent concurrent callers.
    final cycle = _waitPath(entry, parent, {});
    if (cycle != null) {
      throw CircularDependencyException([
        parent.key.$1,
        ...cycle.map((e) => e.key.$1),
      ]);
    }
    final dependencies = _waiting.putIfAbsent(parent, () => {});
    dependencies[entry] = (dependencies[entry] ?? 0) + 1;
    void detach() {
      final count = dependencies[entry]!;
      if (count == 1) {
        dependencies.remove(entry);
      } else {
        dependencies[entry] = count - 1;
      }
      if (dependencies.isEmpty) _waiting.remove(parent);
    }

    try {
      return _asyncValue(entry, p1, p2).whenComplete(detach);
    } catch (_) {
      detach();
      rethrow;
    }
  }

  Future<Object?> _asyncValue(_Entry entry, dynamic p1, dynamic p2) {
    if (entry.hasInstance) return Future.value(entry.instance);
    // Check before joining an in-flight creation, otherwise A -> B -> A hangs.
    if (_path.contains(entry)) return _inPath(entry, () => Future.value(null));
    if (entry.createAsync == null) {
      return Future.sync(() => _sync(entry, p1, p2));
    }
    if (!entry.retains) {
      return _constructAsync(entry, p1, p2);
    }
    if (entry.pending != null) return entry.pending!;
    final pending = _constructAsync(entry, p1, p2);
    entry.pending = pending;
    // A failed lazy creation can be retried. Eager failures remain available to
    // allReady; unregister/re-register an eager service to explicitly retry it.
    pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (entry.lifetime != RegistrationType.singleton) entry.pending = null;
      },
    );
    return pending;
  }

  T resolve<T>({String? name, dynamic param1, dynamic param2}) =>
      _sync(_require<T>(name), param1, param2) as T;
  Future<T> resolveAsync<T>({
    String? name,
    dynamic param1,
    dynamic param2,
  }) async => await _async(_require<T>(name), param1, param2) as T;
  T? tryResolve<T>({String? name, dynamic param1, dynamic param2}) {
    _checkActive();
    return isRegistered<T>(instanceName: name)
        ? resolve<T>(name: name, param1: param1, param2: param2)
        : null;
  }

  T get<T>({String? instanceName, dynamic param1, dynamic param2}) =>
      resolve<T>(name: instanceName, param1: param1, param2: param2);
  T call<T>({String? instanceName, dynamic param1, dynamic param2}) =>
      get<T>(instanceName: instanceName, param1: param1, param2: param2);
  Future<T> getAsync<T>({
    String? instanceName,
    dynamic param1,
    dynamic param2,
  }) => resolveAsync<T>(name: instanceName, param1: param1, param2: param2);

  bool isRegistered<T>({String? instanceName}) =>
      _find(T, instanceName) != null;
  RegistrationType? getRegistrationType<T>({String? name}) =>
      _find(T, name)?.lifetime;
  void enableRegisteringMultipleInstancesOfOneType() {
    _checkMutable();
    _multiple = true;
  }

  Iterable<_Entry> _visible(Type type, bool allScopes) sync* {
    final seen = <_Key>{};
    for (final scope in _scopes.reversed) {
      for (final item in scope.entries.entries) {
        if (item.key.$1 == type && (allScopes || seen.add(item.key))) {
          yield* item.value;
        }
      }
    }
  }

  List<T> getAll<T>({
    bool fromAllScopes = false,
    dynamic param1,
    dynamic param2,
  }) {
    _checkActive();
    return [
      for (final entry in _visible(T, fromAllScopes))
        _sync(entry, param1, param2) as T,
    ];
  }

  Future<List<T>> getAllAsync<T>({
    bool fromAllScopes = false,
    dynamic param1,
    dynamic param2,
  }) async {
    _checkActive();
    return [
      for (final entry in _visible(T, fromAllScopes))
        await _async(entry, param1, param2) as T,
    ];
  }

  void resetCachedFactory<T>({String? name}) {
    _checkMutable(structural: true);
    final entry = _require<T>(name);
    if (entry.lifetime != RegistrationType.cachedFactory) {
      throw StateError('$T is not a cached factory.');
    }
    entry.instance = null;
    entry.hasInstance = false;
    entry.pending = null;
  }

  void signalReady(Object? instance) {
    _checkActive();
    for (final scope in _scopes) {
      for (final entry in scope.order) {
        if (entry.signalsReady &&
            entry.hasInstance &&
            identical(entry.instance, instance)) {
          if (!entry.ready.isCompleted) entry.ready.complete();
          return;
        }
      }
    }
    throw StateError(
      'No service awaiting a readiness signal matches this instance.',
    );
  }

  bool allReadySync() => _scopes.every(
    (scope) => scope.order.every(
      (e) =>
          (e.lifetime != RegistrationType.singleton || e.hasInstance) &&
          (!e.signalsReady || e.ready.isCompleted),
    ),
  );

  Future<void> allReady({Duration? timeout}) {
    _checkActive();
    final work = <Future<void>>[];
    for (final scope in _scopes) {
      for (final entry in scope.order) {
        if (entry.lifetime == RegistrationType.singleton &&
            entry.pending != null) {
          work.add(entry.pending!.then((_) {}));
        }
        if (entry.signalsReady) work.add(entry.ready.future);
      }
    }
    final result = Future.wait(work, eagerError: true).then<void>((_) {});
    return timeout == null ? result : result.timeout(timeout);
  }

  bool hasScope(String name) => _scopes.any((scope) => scope.name == name);
  void pushNewScope({
    required String scopeName,
    void Function(DIEngine)? init,
  }) {
    _checkMutable(structural: true);
    if (hasScope(scopeName)) {
      throw StateError('Scope "$scopeName" already exists.');
    }
    _scopes.add(_EngineScope(scopeName));
    init?.call(this);
  }

  Future<void> unregister<T>({
    String? instanceName,
    EngineDisposer<T>? disposingFunction,
  }) async {
    _checkMutable(structural: true);
    final entry = _find(T, instanceName);
    if (entry == null) return;
    for (final scope in _scopes) {
      if (!scope.order.remove(entry)) continue;
      final entries = scope.entries[entry.key]!;
      entries.remove(entry);
      if (entries.isEmpty) scope.entries.remove(entry.key);
      break;
    }
    _cleaning = true;
    try {
      await _release(
        [entry],
        override: disposingFunction == null
            ? null
            : (value) => disposingFunction(value as T),
      );
    } finally {
      _cleaning = false;
    }
  }

  Future<void> _release(
    Iterable<_Entry> entries, {
    EngineDisposer<Object?>? override,
  }) async {
    final failures = <DependencyDisposalFailure>[];
    for (final entry in entries) {
      try {
        final ancestors = Zone.current[_cleanupKey] as Set<DIEngine>?;
        await runZoned(
          () => entry.release(override),
          zoneValues: {
            _cleanupKey: {...?ancestors, this},
          },
        );
      } catch (error, stackTrace) {
        failures.add(
          DependencyDisposalFailure(
            type: entry.key.$1,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
    if (failures.isNotEmpty) {
      throw DependencyDisposalException(List.unmodifiable(failures));
    }
  }

  /// Removes a scope and releases its owned services. Managed scopes use
  /// [waitForPending] to let in-flight creation finish before releasing resources.
  Future<void> dropScope(String name, {bool waitForPending = false}) async {
    if (waitForPending) {
      _checkActive();
      if (_path.isNotEmpty) {
        throw StateError('Cannot await scope cleanup from inside a factory.');
      }
      while (_creating != 0) {
        await (_idle ??= Completer<void>()).future;
        _checkActive();
      }
    }
    _checkMutable(structural: true);
    final scope = _scopes.firstWhere(
      (s) => s.name == name,
      orElse: () => throw StateError('Unknown scope "$name".'),
    );
    if (identical(scope, _scopes.first)) {
      throw StateError('Cannot drop the base scope.');
    }
    _cleaning = true;
    try {
      await _release(scope.order.reversed);
    } finally {
      _scopes.remove(scope);
      _cleaning = false;
    }
  }

  Future<void> popScope() async {
    if (_scopes.length == 1) throw StateError('Cannot pop the base scope.');
    await dropScope(_scopes.last.name);
  }

  Future<void> reset() => _reset(reactivate: true);
  Future<void> dispose() {
    if (_disposed) return Future.value();
    if (_cleaning) {
      // Reentrant calls made by a disposer are no-ops, but independent callers
      // must join the close operation rather than observe premature completion.
      if ((Zone.current[_cleanupKey] as Set<DIEngine>?)?.contains(this) ??
          false) {
        return Future.value();
      }
      return _closing ??
          Future.error(StateError('Another cleanup is in progress.'));
    }
    return _closing = _reset(reactivate: false);
  }

  Future<void> _reset({required bool reactivate}) async {
    if (_cleaning || _creating != 0 || _path.isNotEmpty) {
      throw StateError('Cannot reset during creation or cleanup.');
    }
    _cleaning = true;
    try {
      await _release([
        for (final scope in _scopes.reversed) ...scope.order.reversed,
      ]);
    } finally {
      _scopes
        ..clear()
        ..add(_EngineScope('baseScope'));
      _disposed = !reactivate;
      _cleaning = false;
      _multiple = false;
      _waiting.clear();
      if (reactivate) _closing = null;
    }
  }

  Future<T> runInScope<T>(
    String name,
    FutureOr<T> Function(DIEngine) body, {
    void Function(DIEngine)? configure,
  }) async {
    pushNewScope(scopeName: name);
    Object? bodyError;
    StackTrace? bodyStack;
    try {
      configure?.call(this);
      return await body(this);
    } catch (error, stackTrace) {
      bodyError = error;
      bodyStack = stackTrace;
      rethrow;
    } finally {
      try {
        await dropScope(name, waitForPending: true);
      } catch (error, stackTrace) {
        if (bodyError != null) {
          Error.throwWithStackTrace(
            ScopeRunException(bodyError, bodyStack!, error, stackTrace),
            bodyStack,
          );
        }
        rethrow;
      }
    }
  }
}

class ScopeRunException implements Exception {
  final Object bodyError;
  final StackTrace bodyStackTrace;
  final Object cleanupError;
  final StackTrace cleanupStackTrace;
  const ScopeRunException(
    this.bodyError,
    this.bodyStackTrace,
    this.cleanupError,
    this.cleanupStackTrace,
  );
  @override
  String toString() =>
      'ScopeRunException: operation failed ($bodyError); cleanup failed ($cleanupError).';
}
