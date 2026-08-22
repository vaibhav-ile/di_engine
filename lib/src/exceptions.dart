class DependencyNotRegisteredException implements Exception {
  final Type type;

  DependencyNotRegisteredException(this.type);

  @override
  String toString() {
    return 'DependencyNotRegisteredException: '
        'No dependency registered for type $type.';
  }
}

class DependencyAlreadyRegisteredException implements Exception {
  final Type type;

  DependencyAlreadyRegisteredException(this.type);

  @override
  String toString() {
    return 'DependencyAlreadyRegisteredException: '
        'A dependency is already registered for type $type.';
  }
}

class InvalidDependencyException implements Exception {
  final String message;

  InvalidDependencyException(this.message);

  @override
  String toString() {
    return 'InvalidDependencyException: $message';
  }
}
