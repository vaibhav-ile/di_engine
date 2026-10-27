# Changelog

All notable changes to this project will be documented in this file.

## 2.0.0

### Added

- Native `DIEngine` with named registrations, scopes, runtime factory arguments, async singletons/factories, nullable instances, readiness signals, multiple implementations, and cached factories.
- Native constructor annotations and an SDK-only `dart run di_engine:generate` command with explicit targets, discovery, watch, and freshness checks.
- Constructor injection, interface/environment bindings, module providers, named/static creators, startup pre-resolution, lifecycle hooks, dependency ordering, generated scope initializers, and native external module composition.
- Optional generated constructor callbacks/accessors and function-based initializer output.
- Temporary scope helpers preserving operation and cleanup failures, typed record arguments, and explicit cache invalidation.
- Generation/runtime cycle diagnostics, concurrent lazy async creation deduplication, retryable lazy failures, and reverse-order aggregated async cleanup.
- Runnable examples, native generator/runtime regression tests, CI, and an offline consumer independence check.

### Changed

- Consolidated all public runtime and annotation exports into `di_engine.dart`; removed the redundant `injectable.dart` entry point.

- Runtime, annotations, and generator are fully implemented in this package using only Dart SDK libraries. No third-party runtime or generation dependencies are required.
- Removed the GetIt/injectable integration introduced during development of this release. Its generated artifacts must be regenerated using the native CLI; external adapters are not retained.
- Removed the Flutter SDK requirement. Dart 3.12 or newer is required.
- Preserved the original synchronous `DIContainer` API and exported `RegistrationType` publicly.

### Fixed

- Detect async dependency cycles across independently started services, including chains through transient factories.
- Make concurrent disposal callers await the same cleanup and reject resolution after disposal consistently.
- Release completed resolution contexts so deferred callbacks do not inherit stale creation guards.
- Correct prefixed `Named.from` bindings, enum/constant constructor defaults, and escaped annotation string values.
- Resolve imported symbols without parsing unrelated SDK members; skip field and constructor initializer expressions when reading signatures.
- Instantiate provider modules only in the generated scopes that use them.
- Wait for pending creation during managed-scope cleanup and generated startup rollback so owned resources are released after failures.
- Stage generator formatter inputs under `.dart_tool` to avoid transient analyzer warnings during watch mode.

- Prevented reentrant disposal from invoking manual-container disposers twice.
- Rejected lifetime mutation during creation/cleanup, including queued eager async creation.
- Shared manual cleanup logic and preserved aggregated failure reporting.

### Migration notes

- `DIEngine` is a native class with its own single registry, not a GetIt alias.
- Await generated initialization and engine cleanup. Use native `Disposable`, `AsyncDisposable`, or disposal callbacks.
- Cached factories use strong, explicit caching and are caller-owned. Invalidate with `resetCachedFactory`.
- The SDK-only generator has documented source-language limits; run Dart/Flutter analysis after generation.
- `DIContainer` keeps its original separate registry and synchronous cleanup behavior.

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
