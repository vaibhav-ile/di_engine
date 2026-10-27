class DependencyNotRegisteredException implements Exception {
  final Type type;

  const DependencyNotRegisteredException(this.type);

  @override
  String toString() {
    return 'DependencyNotRegisteredException: '
        'No dependency registered for type $type.';
  }
}

class DependencyAlreadyRegisteredException implements Exception {
  final Type type;

  const DependencyAlreadyRegisteredException(this.type);

  @override
  String toString() {
    return 'DependencyAlreadyRegisteredException: '
        'A dependency is already registered for type $type.';
  }
}

/// Represents a failure that occurred while disposing a dependency.
class DependencyDisposalFailure {
  final Type type;
  final Object error;
  final StackTrace stackTrace;

  const DependencyDisposalFailure({
    required this.type,
    required this.error,
    required this.stackTrace,
  });

  @override
  String toString() {
    return 'DependencyDisposalFailure: '
        'Failed to dispose dependency of type $type. '
        'Error: $error';
  }
}

/// Thrown when one or more dependencies fail during disposal.
///
/// All registered dependencies are still given an opportunity to dispose
/// before this exception is thrown.
class DependencyDisposalException implements Exception {
  final List<DependencyDisposalFailure> failures;

  const DependencyDisposalException(this.failures);

  @override
  String toString() {
    final count = failures.length;
    final buffer = StringBuffer(
      'DependencyDisposalException: '
      '$count ${count == 1 ? 'dependency' : 'dependencies'} failed to dispose.',
    );

    for (final failure in failures) {
      buffer
        ..writeln()
        ..write('  - $failure');
    }

    return buffer.toString();
  }
}

/// A dependency tried to resolve itself through its constructor dependency graph.
class CircularDependencyException implements Exception {
  final List<Type> path;

  CircularDependencyException(Iterable<Type> path)
    : path = List.unmodifiable(path);

  @override
  String toString() => 'CircularDependencyException: ${path.join(' → ')}';
}
