# Changelog

All notable changes to this project will be documented in this file.

## 1.1.0

### Added

- Added `DIContainer.isDisposed` to inspect container lifecycle state.
- Added `DIContainer.getRegistrationType<T>()` to inspect how a dependency is registered.
- Added disposal failure reporting through `DependencyDisposalException`.
- Added detailed `DependencyDisposalFailure` information including dependency type, error, and stack trace.
- Added deterministic reverse-order dependency disposal.
- Added support for nullable singleton and lazy singleton instances.

### Changed

- Improved dependency registration lifecycle handling.
- Singleton registrations are eagerly created and owned by the container.
- Lazy singleton registrations are created only when first resolved and owned by the container after creation.
- Factory registrations now create a new instance for every resolution and are not disposed by the container.
- Removed disposal callbacks from factory registrations because factory instances are not container-owned.
- Explicit disposal callbacks take precedence over `Disposable.dispose()`.
- Container disposal now attempts to dispose all owned dependencies even if one dependency fails.
- `reset()` now clears registrations, disposes owned dependencies, and reactivates the container.
- `unregister<T>()` now disposes the owned dependency before removing it.
- Container disposal is idempotent.
- Lazy singleton disposal never creates an instance that was never resolved.

### Fixed

- Corrected lifecycle handling for nullable dependency instances.
- Improved disposal behavior when a dependency's dispose operation throws.
- Improved consistency of registration state after disposal and reset.

### Compatibility

- Supports both Dart and Flutter applications.

### Breaking change

- Factory registrations no longer accept disposal callbacks because factory-created instances are not owned by the container.

## 1.0.0

### Added

- Initial release of `di_engine`.
- Singleton registration.
- Lazy singleton registration.
- Factory registration.
- Dependency resolution.
- Dependency registration checks.
- Dependency unregistration.
- Container-wide disposal.
- `Disposable` interface support.
