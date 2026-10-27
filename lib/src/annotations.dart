import 'dart:async';

import 'engine.dart';

/// Marks a class for constructor injection. Unnamed factories are the default.
class Injectable {
  final Type? as;
  final List<String> env;
  final String? scope;
  final int order;
  final bool cache;
  const Injectable({
    this.as,
    this.env = const [],
    this.scope,
    this.order = 0,
    this.cache = false,
  });
}

class Singleton extends Injectable {
  final Function? dispose;
  final bool signalsReady;
  const Singleton({
    super.as,
    super.env,
    super.scope,
    super.order,
    this.dispose,
    this.signalsReady = false,
  });
}

class LazySingleton extends Injectable {
  final Function? dispose;
  const LazySingleton({
    super.as,
    super.env,
    super.scope,
    super.order,
    this.dispose,
  });
}

const injectable = Injectable();
const singleton = Singleton();
const lazySingleton = LazySingleton();

class Named {
  final String? name;
  final Type? type;
  const Named(this.name) : type = null;
  const Named.from(this.type) : name = null;
  const Named.auto() : name = null, type = null;
}

const named = Named.auto();

class Environment {
  static const dev = 'dev';
  static const prod = 'prod';
  static const test = 'test';
  final String name;
  const Environment(this.name);
}

const dev = Environment(Environment.dev);
const prod = Environment(Environment.prod);
const test = Environment(Environment.test);

abstract class EnvironmentFilter {
  const EnvironmentFilter();
  bool allows(Set<String> environments);
}

class SimpleEnvironmentFilter extends EnvironmentFilter {
  final String? environment;
  const SimpleEnvironmentFilter(this.environment);
  @override
  bool allows(Set<String> environments) =>
      environments.isEmpty || environments.contains(environment);
}

class NoEnvOrContainsAny extends EnvironmentFilter {
  final Set<String> environments;
  const NoEnvOrContainsAny(this.environments);
  @override
  bool allows(Set<String> keys) =>
      keys.isEmpty || keys.any(environments.contains);
}

class NoEnvOrContainsAll extends EnvironmentFilter {
  final Set<String> environments;
  const NoEnvOrContainsAll(this.environments);
  @override
  bool allows(Set<String> keys) =>
      keys.isEmpty || keys.containsAll(environments);
}

class Scope {
  final String name;
  const Scope(this.name);
}

class Order {
  final int value;
  const Order(this.value);
}

class FactoryParam {
  const FactoryParam();
}

const factoryParam = FactoryParam();

class Module {
  const Module();
}

const module = Module();

class DisposeMethod {
  const DisposeMethod();
}

const disposeMethod = DisposeMethod();

class PreResolve {
  const PreResolve();
}

const preResolve = PreResolve();

class FactoryMethod {
  final bool preResolve;
  const FactoryMethod({this.preResolve = false});
}

const factoryMethod = FactoryMethod();

class PostConstruct {
  final bool preResolve;
  const PostConstruct({this.preResolve = false});
}

const postConstruct = PostConstruct();

class ExternalModule {
  final Type module;
  final String? scope;
  const ExternalModule(this.module, {this.scope});
}

/// Module contract shared by generated and hand-written dependency modules.
abstract class DIModule {
  const DIModule();
  FutureOr<void> register(
    DIEngine engine, {
    String? environment,
    EnvironmentFilter? environmentFilter,
  });
}

class InjectableInit {
  final String initializerName;
  final List<String> generateForDir;
  final bool preferRelativeImports;
  final bool asExtension;
  final bool microPackage;
  final List<ExternalModule> externalPackageModulesBefore;
  final List<ExternalModule> externalPackageModulesAfter;
  final bool throwOnMissingDependencies;
  final bool generateAccessors;
  final bool usesConstructorCallback;
  final bool allowMultipleRegistrations;
  const InjectableInit({
    this.initializerName = 'init',
    this.generateForDir = const ['lib'],
    this.preferRelativeImports = true,
    this.asExtension = true,
    this.externalPackageModulesBefore = const [],
    this.externalPackageModulesAfter = const [],
    this.throwOnMissingDependencies = true,
    this.generateAccessors = false,
    this.usesConstructorCallback = false,
    this.allowMultipleRegistrations = false,
  }) : microPackage = false;
  const InjectableInit.microPackage({
    this.generateForDir = const ['lib'],
    this.preferRelativeImports = true,
    this.throwOnMissingDependencies = true,
  }) : initializerName = 'init',
       asExtension = false,
       microPackage = true,
       externalPackageModulesBefore = const [],
       externalPackageModulesAfter = const [],
       generateAccessors = false,
       usesConstructorCallback = false,
       allowMultipleRegistrations = false;
}

const injectableInit = InjectableInit();
const microPackageInit = InjectableInit.microPackage();
