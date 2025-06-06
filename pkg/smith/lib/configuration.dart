// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:convert';
import 'dart:io';

// READ ME! If you add a new field to this, make sure to add it to
// [_cloneHelper()], [parse()], [optionsEqual()], [hashCode], and [toString()].
// A good check is to comment out an existing field and see what breaks.
// Every error is a place where you will need to add code for your new field.

/// A set of options that affects how a Dart SDK test is run in a way that may
/// affect its outcome.
///
/// This includes options like "compiler" and "runtime" which fundamentally
/// decide how a test is executed. Options are tracked because a single test
/// may have different outcomes for different configurations. For example, it
/// may currently pass on the VM but not dart2js or vice versa.
///
/// Options that affect how a test can be run but don't affect its outcome are
/// *not* stored here. Things like how test results are displayed, where logs
/// are written, etc. live outside of this.
class Configuration {
  /// Expands a configuration name "[template]" all using [optionsJson] to a
  /// list of configurations.
  ///
  /// A template is a configuration name that contains zero or more
  /// parenthesized sections. Within the parentheses are a series of options
  /// separated by pipes. For example:
  ///
  ///     strong-fasta-(linux|mac|win)-(debug|release)
  ///
  /// Text outside of parenthesized groups is treated literally. Each
  /// parenthesized section expands to a configuration for each of the options
  /// separated by pipes. If a template contains multiple parenthesized
  /// sections, configurations are created for all combinations of them. The
  /// above template expands to:
  ///
  ///     strong-fasta-linux-debug
  ///     strong-fasta-linux-release
  ///     strong-fasta-mac-debug
  ///     strong-fasta-mac-release
  ///     strong-fasta-win-debug
  ///     strong-fasta-win-release
  ///
  /// After expansion, the resulting strings (and [optionsJson]) are passed to
  /// [parse()] to convert each one to a full configuration.
  static List<Configuration> expandTemplate(
      String template, Map<String, dynamic> optionsJson) {
    if (template.isEmpty) throw FormatException("Template must not be empty.");

    var sections = <List<String>>[];
    var start = 0;
    while (start < template.length) {
      var openParen = template.indexOf("(", start);

      if (openParen == -1) {
        // Add the last literal section.
        sections.add([template.substring(start, template.length)]);
        break;
      }

      var closeParen = template.indexOf(")", openParen);
      if (closeParen == -1) {
        throw FormatException('Missing ")" in name template "$template".');
      }

      // Add the literal part before the next "(".
      sections.add([template.substring(start, openParen)]);

      // Add the options within the parentheses.
      sections.add(template.substring(openParen + 1, closeParen).split("|"));

      // Continue past the ")".
      start = closeParen + 1;
    }

    var result = <Configuration>[];

    // Walk through every combination of every section.
    iterateSection(String prefix, int section) {
      // If we pinned all the sections, parse it.
      if (section >= sections.length) {
        try {
          result.add(Configuration.parse(prefix, optionsJson));
        } on FormatException catch (ex) {
          throw FormatException(
              'Could not parse expanded configuration "$prefix" from template '
              '"$template":\n${ex.message}');
        }
        return;
      }

      for (var i = 0; i < sections[section].length; i++) {
        iterateSection(prefix + sections[section][i], section + 1);
      }
    }

    iterateSection("", 0);

    return result;
  }

  /// Parse a single configuration with [name] with additional options defined
  /// in [optionsJson].
  ///
  /// The name should be a series of words separated by hyphens. Any word that
  /// matches the name of an [Architecture], [Compiler], [Mode], [Runtime], or
  /// [System] sets that option in the resulting configuration. Those options
  /// may also be specified in the JSON map.
  ///
  /// Additional Boolean and string options are defined in the map. The key
  /// names match the corresponding command-line option names, using kebab-case.
  static Configuration parse(String name, Map<String, dynamic> optionsJson) {
    if (name.isEmpty) throw FormatException("Name must not be empty.");

    // Infer option values from the words in the configuration name.
    var words = name.split("-").toSet();
    // "vm-aot" -> "dart_precompiled-aot"
    if (words.contains("aot")) {
      words.remove("vm");
      words.add("dart_precompiled");
    }
    var optionsCopy = Map.of(optionsJson);

    // Apply overrides from the global environment variable.
    final configurationOverridesJson =
        _platformEnvironment['TEST_CONFIGURATION_OVERRIDES'];
    if (configurationOverridesJson != null) {
      final optionsOverrides =
          jsonDecode(configurationOverridesJson) as Map<String, dynamic>;
      for (var e in optionsOverrides.entries) {
        optionsCopy[e.key] = e.value;
      }
    }

    T? enumOption<T extends NamedEnum>(
        String option, List<String> allowed, T Function(String) parse) {
      // Look up the value from the words in the name.
      T? fromName;
      for (var value in allowed) {
        // Don't treat "none" as matchable since it's ambiguous as to whether
        // it refers to runtime or sanitizer.
        if (value == "none") continue;

        if (words.contains(value)) {
          if (fromName != null) {
            throw FormatException(
                'Found multiple values for $option ("$fromName" and "$value"), '
                'in configuration name.');
          }
          fromName = parse(value);
        }
      }

      // Look up the value from the options.
      T? fromOption;
      if (optionsCopy.containsKey(option)) {
        fromOption = parse(optionsCopy[option] as String);
        optionsCopy.remove(option);
      }

      if (fromName != null && fromOption != null) {
        if (fromName == fromOption) {
          throw FormatException(
              'Redundant $option in configuration name "$fromName" and options.');
        } else {
          throw FormatException(
              'Found $option "$fromOption" in options and "$fromName" in '
              'configuration name.');
        }
      }

      return fromName ?? fromOption;
    }

    bool? boolOption(String option) {
      if (!optionsCopy.containsKey(option)) return null;

      var value = optionsCopy.remove(option);
      if (value == null) throw FormatException('Option "$option" was null.');
      if (value is! bool) {
        throw FormatException('Option "$option" had value "$value", which is '
            'not a bool.');
      }
      return value;
    }

    int? intOption(String option) {
      if (!optionsCopy.containsKey(option)) return null;

      var value = optionsCopy.remove(option);
      if (value == null) throw FormatException('Option "$option" was null.');
      if (value is! int) {
        throw FormatException('Option "$option" had value "$value", which is '
            'not an int.');
      }
      return value;
    }

    String? stringOption(String option) {
      if (!optionsCopy.containsKey(option)) return null;

      var value = optionsCopy.remove(option);
      if (value == null) throw FormatException('Option "$option" was null.');
      if (value is! String) {
        throw FormatException('Option "$option" had value "$value", which is '
            'not a string.');
      }
      return value;
    }

    List<String>? stringListOption(String option) {
      if (!optionsCopy.containsKey(option)) return null;

      var value = optionsCopy.remove(option);
      if (value == null) throw FormatException('Option "$option" was null.');
      if (value is! List) {
        throw FormatException('Option "$option" had value "$value", which is '
            'not a List.');
      }
      return List<String>.from(value);
    }

    var detectHost = boolOption('detect-host');
    if (detectHost != null && detectHost) {
      throw FormatException(
          'The `detect-host` option is explicitly forbidden in the '
          'test_matrix.json file.');
    }

    // Extract options from the name and map.
    var architecture =
        enumOption("architecture", Architecture.names, Architecture.find);
    var compiler = enumOption("compiler", Compiler.names, Compiler.find);
    var mode = enumOption("mode", Mode.names, Mode.find);
    var runtime = enumOption("runtime", Runtime.names, Runtime.find);
    var system = enumOption("system", System.names, System.find);
    var nnbdMode = enumOption("nnbd", NnbdMode.names, NnbdMode.find);
    var sanitizer = enumOption("sanitizer", Sanitizer.names, Sanitizer.find);

    // Fill in any missing values using defaults when possible.
    architecture ??= Architecture.host;
    system ??= System.host;
    nnbdMode ??= NnbdMode.strong;
    sanitizer ??= Sanitizer.none;

    // Infer runtime from executable if we don't know runtime and compiler.
    if (runtime == null && compiler == null && words.contains("custom")) {
      final executableName = Uri.file(Platform.executable)
          .pathSegments
          .lastWhere((e) => e.isNotEmpty);
      final executableNoExtension = executableName.split('.').first;
      if (executableNoExtension == 'dartaotruntime') {
        runtime = Runtime.dartPrecompiled;
      } else if (executableNoExtension == 'dart') {
        runtime = Runtime.vm;
      }
    }

    // Infer from compiler from runtime or vice versa.
    if (compiler == null) {
      if (runtime == null) {
        throw FormatException(
            'Must specify at least one of compiler or runtime in options or '
            'configuration name.');
      } else {
        compiler = runtime.defaultCompiler;
      }
    } else {
      if (runtime == null) {
        runtime = compiler.defaultRuntime;
      } else {
        // Do nothing, specified both.
      }
    }

    // Infer the mode from the compiler.
    mode ??= compiler.defaultMode;

    var configuration = Configuration(
        name, architecture, compiler, mode, runtime, system,
        nnbdMode: nnbdMode,
        sanitizer: sanitizer,
        builderTag: stringOption("builder-tag"),
        genKernelOptions: stringListOption("gen-kernel-options"),
        vmOptions: stringListOption("vm-options"),
        dart2jsOptions: stringListOption("dart2js-options"),
        dart2wasmOptions: stringListOption("dart2wasm-options"),
        ddcOptions: stringListOption("ddc-options"),
        experiments: stringListOption("enable-experiment"),
        timeout: intOption("timeout"),
        enableAsserts: boolOption("enable-asserts"),
        isChecked: boolOption("checked"),
        isCsp: boolOption("csp"),
        enableHostAsserts: boolOption("host-asserts"),
        isMinified: boolOption("minified"),
        useAnalyzerCfe: boolOption("use-cfe"),
        useAnalyzerFastaParser: boolOption("analyzer-use-fasta-parser"),
        useElf: boolOption("use-elf"),
        useHotReload: boolOption("hot-reload"),
        useHotReloadRollback: boolOption("hot-reload-rollback"),
        useSdk: boolOption("use-sdk"),
        useQemu: boolOption("use-qemu"));

    // Should have consumed the whole map.
    if (optionsCopy.isNotEmpty) {
      throw FormatException('Unknown option "${optionsCopy.keys.first}".');
    }

    return configuration;
  }

  final String name;

  final Architecture architecture;

  final Compiler compiler;

  final Mode mode;

  final Runtime runtime;

  final System system;

  /// Which NNBD mode to run the test files under.
  final NnbdMode nnbdMode;

  final Sanitizer sanitizer;

  final String builderTag;

  final List<String> genKernelOptions;

  final List<String> vmOptions;

  final List<String> dart2jsOptions;

  final List<String> dart2wasmOptions;

  final List<String> ddcOptions;

  /// The names of the experiments to enable while running tests.
  ///
  /// A test may *require* an experiment to always be enabled by containing a
  /// comment like:
  ///
  ///     // SharedOptions=--enable-experiment=extension-methods
  ///
  /// Enabling an experiment here in the configuration allows running the same
  /// test both with an experiment on and off.
  final List<String> experiments;

  final int timeout;

  final bool enableAsserts;

  // TODO(rnystrom): Remove this when Dart 1.0 is no longer supported.
  final bool isChecked;

  final bool isCsp;

  /// Enables asserts in the backend compilers.
  final bool enableHostAsserts;

  final bool isMinified;

  // TODO(whesse): Remove these when only fasta front end is in analyzer.
  final bool useAnalyzerCfe;
  final bool useAnalyzerFastaParser;

  final bool useElf;

  final bool useHotReload;
  final bool useHotReloadRollback;

  final bool useSdk;

  final bool useQemu;

  Configuration(this.name, this.architecture, this.compiler, this.mode,
      this.runtime, this.system,
      {NnbdMode? nnbdMode,
      Sanitizer? sanitizer,
      String? builderTag,
      List<String>? genKernelOptions,
      List<String>? vmOptions,
      List<String>? dart2jsOptions,
      List<String>? dart2wasmOptions,
      List<String>? ddcOptions,
      List<String>? experiments,
      int? timeout,
      bool? enableAsserts,
      bool? isChecked,
      bool? isCsp,
      bool? enableHostAsserts,
      bool? isMinified,
      bool? useAnalyzerCfe,
      bool? useAnalyzerFastaParser,
      bool? useElf,
      bool? useHotReload,
      bool? useHotReloadRollback,
      bool? useSdk,
      bool? useQemu})
      : nnbdMode = nnbdMode ?? NnbdMode.strong,
        sanitizer = sanitizer ?? Sanitizer.none,
        builderTag = builderTag ?? "",
        genKernelOptions = genKernelOptions ?? <String>[],
        vmOptions = vmOptions ?? <String>[],
        dart2jsOptions = dart2jsOptions ?? <String>[],
        dart2wasmOptions = dart2wasmOptions ?? <String>[],
        ddcOptions = ddcOptions ?? <String>[],
        experiments = experiments ?? <String>[],
        timeout = timeout ?? -1,
        enableAsserts = enableAsserts ?? false,
        isChecked = isChecked ?? false,
        isCsp = isCsp ?? false,
        enableHostAsserts = enableHostAsserts ?? false,
        isMinified = isMinified ?? false,
        useAnalyzerCfe = useAnalyzerCfe ?? false,
        useAnalyzerFastaParser = useAnalyzerFastaParser ?? false,
        useElf = useElf ?? false,
        useHotReload = useHotReload ?? false,
        useHotReloadRollback = useHotReloadRollback ?? false,
        useSdk = useSdk ?? false,
        useQemu = useQemu ?? false {
    if (name.contains(" ")) {
      throw ArgumentError(
          "Name of test configuration cannot contain spaces: $name");
    }
  }

  /// A helper constructor for cloning factories.
  ///
  /// NOTE: All parameters should be required to ensure that cloning factories
  /// are updated when new class fields are added.
  Configuration._cloneHelper(
    this.name,
    this.architecture,
    this.compiler,
    this.mode,
    this.runtime,
    this.system, {
    required this.nnbdMode,
    required this.sanitizer,
    required this.builderTag,
    required this.genKernelOptions,
    required this.vmOptions,
    required this.dart2jsOptions,
    required this.dart2wasmOptions,
    required this.ddcOptions,
    required this.experiments,
    required this.timeout,
    required this.enableAsserts,
    required this.isChecked,
    required this.isCsp,
    required this.enableHostAsserts,
    required this.isMinified,
    required this.useAnalyzerCfe,
    required this.useAnalyzerFastaParser,
    required this.useElf,
    required this.useHotReload,
    required this.useHotReloadRollback,
    required this.useSdk,
    required this.useQemu,
  });

  /// Creates a shallow clone of [source] with a new name and changes the system
  /// and architecture to match the local host.
  ///
  /// NOTE: This calls [_cloneHelper] instead of the default constructor to
  /// ensure it gets updated whenever new fields are added to the class.
  factory Configuration.detectHost(Configuration source) =>
      Configuration._cloneHelper(
        '${source.name}-detect-host-${_detectHostNumber++}',
        Architecture.host,
        source.compiler,
        source.mode,
        source.runtime,
        System.host,
        nnbdMode: source.nnbdMode,
        sanitizer: source.sanitizer,
        builderTag: source.builderTag,
        genKernelOptions: source.genKernelOptions,
        vmOptions: source.vmOptions,
        dart2jsOptions: source.dart2jsOptions,
        dart2wasmOptions: source.dart2wasmOptions,
        ddcOptions: source.ddcOptions,
        experiments: source.experiments,
        timeout: source.timeout,
        enableAsserts: source.enableAsserts,
        isChecked: source.isChecked,
        isCsp: source.isCsp,
        enableHostAsserts: source.enableHostAsserts,
        isMinified: source.isMinified,
        useAnalyzerCfe: source.useAnalyzerCfe,
        useAnalyzerFastaParser: source.useAnalyzerFastaParser,
        useElf: source.useElf,
        useHotReload: source.useHotReload,
        useHotReloadRollback: source.useHotReloadRollback,
        useSdk: source.useSdk,
        useQemu: source.useQemu,
      );

  /// Counter to provide a unique number in the name of each call to
  /// [detectHost].
  static var _detectHostNumber = 1;

  /// Returns `true` if this configuration's options all have the same values
  /// as [other].
  bool optionsEqual(Configuration other) =>
      architecture == other.architecture &&
      compiler == other.compiler &&
      mode == other.mode &&
      runtime == other.runtime &&
      system == other.system &&
      nnbdMode == other.nnbdMode &&
      sanitizer == other.sanitizer &&
      builderTag == other.builderTag &&
      _listsEqual(genKernelOptions, other.genKernelOptions) &&
      _listsEqual(vmOptions, other.vmOptions) &&
      _listsEqual(dart2jsOptions, other.dart2jsOptions) &&
      _listsEqual(dart2wasmOptions, other.dart2wasmOptions) &&
      _listsEqual(ddcOptions, other.ddcOptions) &&
      _listsEqual(experiments, other.experiments) &&
      timeout == other.timeout &&
      enableAsserts == other.enableAsserts &&
      isChecked == other.isChecked &&
      isCsp == other.isCsp &&
      enableHostAsserts == other.enableHostAsserts &&
      isMinified == other.isMinified &&
      useAnalyzerCfe == other.useAnalyzerCfe &&
      useAnalyzerFastaParser == other.useAnalyzerFastaParser &&
      useElf == other.useElf &&
      useHotReload == other.useHotReload &&
      useHotReloadRollback == other.useHotReloadRollback &&
      useSdk == other.useSdk &&
      useQemu == other.useQemu;

  /// Whether [a] and [b] contain the same strings, regardless of order.
  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;

    // Using sorted lists instead of sets in case there are duplicate strings
    // in the lists. ["a"] should not be considered equal to ["a", "a"].
    var aSorted = a.toList()..sort();
    var bSorted = b.toList()..sort();
    for (var i = 0; i < aSorted.length; i++) {
      if (aSorted[i] != bSorted[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is Configuration && name == other.name && optionsEqual(other);

  int _toBinary(List<bool> bits) =>
      bits.fold(0, (sum, bit) => (sum << 1) ^ (bit ? 1 : 0));

  @override
  int get hashCode =>
      name.hashCode ^
      architecture.hashCode ^
      compiler.hashCode ^
      mode.hashCode ^
      runtime.hashCode ^
      system.hashCode ^
      nnbdMode.hashCode ^
      builderTag.hashCode ^
      genKernelOptions.join(" & ").hashCode ^
      vmOptions.join(" & ").hashCode ^
      dart2jsOptions.join(" & ").hashCode ^
      dart2wasmOptions.join(" & ").hashCode ^
      ddcOptions.join(" & ").hashCode ^
      experiments.join(" & ").hashCode ^
      timeout.hashCode ^
      _toBinary([
        enableAsserts,
        isChecked,
        isCsp,
        enableHostAsserts,
        isMinified,
        useAnalyzerCfe,
        useAnalyzerFastaParser,
        useElf,
        useHotReload,
        useHotReloadRollback,
        useSdk,
        useQemu
      ]);

  @override
  String toString() {
    var buffer = StringBuffer();
    buffer.write(name);
    buffer.write("(");

    var fields = <String>[];
    fields.add("architecture: $architecture");
    fields.add("compiler: $compiler");
    fields.add("mode: $mode");
    fields.add("runtime: $runtime");
    fields.add("system: $system");

    if (nnbdMode != NnbdMode.strong) fields.add("nnbd: $nnbdMode");

    stringListField(String name, List<String> field) {
      if (field.isEmpty) return;
      fields.add("$name: [${field.join(", ")}]");
    }

    if (builderTag.isNotEmpty) fields.add("builder-tag: $builderTag");
    stringListField("gen-kernel-options", genKernelOptions);
    stringListField("vm-options", vmOptions);
    stringListField("dart2js-options", dart2jsOptions);
    stringListField("dart2wasm-options", dart2wasmOptions);
    stringListField("ddc-options", ddcOptions);
    stringListField("enable-experiment", experiments);
    if (timeout > 0) fields.add("timeout: $timeout");
    if (enableAsserts) fields.add("enable-asserts");
    if (isChecked) fields.add("checked");
    if (isCsp) fields.add("csp");
    if (enableHostAsserts) fields.add("host-asserts");
    if (isMinified) fields.add("minified");
    if (useAnalyzerCfe) fields.add("use-cfe");
    if (useAnalyzerFastaParser) fields.add("analyzer-use-fasta-parser");
    if (useHotReload) fields.add("hot-reload");
    if (useHotReloadRollback) fields.add("hot-reload-rollback");
    if (useSdk) fields.add("use-sdk");
    if (useQemu) fields.add("use-qemu");

    buffer.write(fields.join(", "));
    buffer.write(")");
    return buffer.toString();
  }

  String visualCompare(Configuration other) {
    var buffer = StringBuffer();
    buffer.writeln(name);
    buffer.writeln(other.name);

    var fields = <String>[];
    fields.add("architecture: $architecture ${other.architecture}");
    fields.add("compiler: $compiler ${other.compiler}");
    fields.add("mode: $mode ${other.mode}");
    fields.add("runtime: $runtime ${other.runtime}");
    fields.add("system: $system ${other.system}");

    stringField(String name, String value, String otherValue) {
      if (value.isEmpty && otherValue.isEmpty) return;
      var ours = value.isEmpty ? "(none)" : value;
      var theirs = otherValue.isEmpty ? "(none)" : otherValue;
      fields.add("$name: $ours $theirs");
    }

    stringListField(String name, List<String> value, List<String> otherValue) {
      if (value.isEmpty && otherValue.isEmpty) return;
      fields.add("$name: [${value.join(', ')}] [${otherValue.join(', ')}]");
    }

    boolField(String name, bool value, bool otherValue) {
      if (!value && !otherValue) return;
      fields.add("$name: $value $otherValue");
    }

    fields.add("nnbd: $nnbdMode ${other.nnbdMode}");
    fields.add("sanitizer: $sanitizer ${other.sanitizer}");
    stringField("builder-tag", builderTag, other.builderTag);
    stringListField(
        "gen-kernel-options", genKernelOptions, other.genKernelOptions);
    stringListField("vm-options", vmOptions, other.vmOptions);
    stringListField("dart2js-options", dart2jsOptions, other.dart2jsOptions);
    stringListField(
        "dart2wasm-options", dart2wasmOptions, other.dart2wasmOptions);
    stringListField("ddc-options", ddcOptions, other.ddcOptions);
    stringListField("experiments", experiments, other.experiments);
    fields.add("timeout: $timeout ${other.timeout}");
    boolField("enable-asserts", enableAsserts, other.enableAsserts);
    boolField("checked", isChecked, other.isChecked);
    boolField("csp", isCsp, other.isCsp);
    boolField("host-asserts", enableHostAsserts, other.enableHostAsserts);
    boolField("minified", isMinified, other.isMinified);
    boolField("use-cfe", useAnalyzerCfe, other.useAnalyzerCfe);
    boolField("analyzer-use-fasta-parser", useAnalyzerFastaParser,
        other.useAnalyzerFastaParser);
    boolField("hot-reload", useHotReload, other.useHotReload);
    boolField("hot-reload-rollback", useHotReloadRollback,
        other.useHotReloadRollback);
    boolField("use-sdk", useSdk, other.useSdk);
    boolField("use-qemu", useQemu, other.useQemu);

    buffer.write(fields.join("\n   "));
    buffer.write("\n");
    return buffer.toString();
  }
}

class Architecture extends NamedEnum {
  static const ia32 = Architecture._('ia32');
  static const x64 = Architecture._('x64');
  static const x64c = Architecture._('x64c');
  static const simx64 = Architecture._('simx64');
  static const simx64c = Architecture._('simx64c');
  static const arm = Architecture._('arm');
  // ignore: constant_identifier_names
  static const arm_x64 = Architecture._('arm_x64');
  static const arm64 = Architecture._('arm64');
  static const arm64c = Architecture._('arm64c');
  static const simarm = Architecture._('simarm');
  // ignore: constant_identifier_names
  static const simarm_x64 = Architecture._('simarm_x64');
  static const simarm64 = Architecture._('simarm64');
  // ignore: constant_identifier_names
  static const simarm64_arm64 = Architecture._('simarm64_arm64');
  static const simarm64c = Architecture._('simarm64c');
  static const riscv32 = Architecture._('riscv32');
  static const riscv64 = Architecture._('riscv64');
  static const simriscv32 = Architecture._('simriscv32');
  static const simriscv64 = Architecture._('simriscv64');

  static final List<String> names = _all.keys.toList();

  static final _all = Map<String, Architecture>.fromIterable([
    ia32,
    x64,
    x64c,
    simx64,
    simx64c,
    arm,
    arm_x64,
    arm64,
    arm64c,
    simarm,
    simarm_x64,
    simarm64,
    simarm64_arm64,
    simarm64c,
    riscv32,
    riscv64,
    simriscv32,
    simriscv64,
  ], key: (architecture) => (architecture as Architecture).name);

  static Architecture find(String name) {
    var architecture = _all[name];
    if (architecture != null) return architecture;

    throw ArgumentError('Unknown architecture "$name".');
  }

  const Architecture._(super.name);

  bool get isSimulator => _simulators.contains(this);
  static final _simulators = <Architecture>{
    simx64,
    simx64c,
    simarm,
    simarm_x64,
    simarm64,
    simarm64c,
    simriscv32,
    simriscv64,
  };

  static final Architecture host = _computeHost();
  static Architecture _computeHost() {
    if (!const bool.hasEnvironment('dart.library.ffi')){
      // We're inside a test which very likely uses the `isXConfiguration`
      // getters from  `package:expect/config.dart` which makes us
      // try to guess the [Configuration]`s architecture if it wasn't passed as
      // part of `const String.fromEnvironment("test_runner.configuration")`.
      //
      // A web app runs inside a browser doesn't have an architecture. Strictly
      // speaking we should *not* ask for "whats the current architecture" if
      // we are running on the web, as there's no answer.
      //
      // For now, fake it by returning x64 on the web.
      return Architecture.x64;
    }
    String? arch;
    if (Platform.isWindows) {
      arch = Platform.environment["PROCESSOR_ARCHITECTURE"];
    } else {
      arch = (Process.runSync("uname", ["-m"]).stdout as String).trim();
    }

    switch (arch) {
      case "i386":
      case "i686":
      case "ia32":
      case "x86":
      case "X86":
        return ia32;
      case "x64":
      case "x86-64":
      case "x86_64":
      case "amd64":
      case "AMD64":
        return x64;
      case "armv7l":
      case "ARM":
        return arm;
      case "aarch64":
      case "arm64":
      case "arm64e":
      case "ARM64":
        return arm64;
      case "riscv32":
        return riscv32;
      case "riscv64":
        return riscv64;
    }

    throw "Unknown host architecture: $arch";
  }
}

class Compiler extends NamedEnum {
  static const dart2js = Compiler._('dart2js');
  static const dart2analyzer = Compiler._('dart2analyzer');
  static const dart2wasm = Compiler._('dart2wasm');
  static const ddc = Compiler._('ddc');
  static const appJitk = Compiler._('app_jitk');
  static const dartk = Compiler._('dartk');
  static const dartkp = Compiler._('dartkp');
  static const specParser = Compiler._('spec_parser');
  static const fasta = Compiler._('fasta');
  static const dart2bytecode = Compiler._('dart2bytecode');

  static final List<String> names = _all.keys.toList();

  static final _all = Map<String, Compiler>.fromIterable([
    dart2js,
    dart2analyzer,
    dart2wasm,
    ddc,
    appJitk,
    dartk,
    dartkp,
    specParser,
    fasta,
    dart2bytecode,
  ], key: (compiler) => (compiler as Compiler).name);

  static Compiler find(String name) {
    var compiler = _all[name];
    if (compiler != null) return compiler;

    throw ArgumentError('Unknown compiler "$name".');
  }

  const Compiler._(super.name);

  /// Gets the runtimes this compiler can target.
  List<Runtime> get supportedRuntimes {
    switch (this) {
      case Compiler.dart2js:
        // Note: by adding 'none' as a configuration, if the user
        // runs test.py -c dart2js -r drt,none the dart2js_none and
        // dart2js_drt will be duplicating work. If later we don't need 'none'
        // with dart2js, we should remove it from here.
        return const [
          Runtime.d8,
          Runtime.jsshell,
          Runtime.none,
          Runtime.firefox,
          Runtime.chrome,
          Runtime.safari,
          Runtime.edge,
          Runtime.chromeOnAndroid,
        ];

      case Compiler.ddc:
        return const [
          Runtime.none,
          Runtime.d8,
          Runtime.chrome,
          Runtime.edge,
          Runtime.firefox,
          Runtime.safari,
        ];

      case Compiler.dart2wasm:
        return const [
          Runtime.none,
          Runtime.jsc,
          Runtime.jsshell,
          Runtime.d8,
          Runtime.chrome,
          Runtime.firefox,
          Runtime.safari,
        ];
      case Compiler.dart2analyzer:
        return const [Runtime.none];
      case Compiler.appJitk:
      case Compiler.dartk:
        return const [Runtime.vm];
      case Compiler.dartkp:
        return const [Runtime.dartPrecompiled];
      case Compiler.specParser:
        return const [Runtime.none];
      case Compiler.fasta:
        return const [Runtime.none];
      case Compiler.dart2bytecode:
        return const [Runtime.vm, Runtime.dartPrecompiled];
    }

    throw "unreachable";
  }

  /// The preferred runtime to use with this compiler if no other runtime is
  /// specified.
  Runtime get defaultRuntime {
    switch (this) {
      case Compiler.dart2js:
        return Runtime.d8;
      case Compiler.dart2wasm:
        return Runtime.d8;
      case Compiler.ddc:
        return Runtime.chrome;
      case Compiler.dart2analyzer:
        return Runtime.none;
      case Compiler.appJitk:
      case Compiler.dartk:
        return Runtime.vm;
      case Compiler.dartkp:
        return Runtime.dartPrecompiled;
      case Compiler.specParser:
      case Compiler.fasta:
        return Runtime.none;
      case Compiler.dart2bytecode:
        return Runtime.dartPrecompiled;
    }

    throw "unreachable";
  }

  Mode get defaultMode {
    switch (this) {
      case Compiler.dart2analyzer:
      case Compiler.dart2js:
      case Compiler.dart2wasm:
      case Compiler.ddc:
      case Compiler.fasta:
        return Mode.release;

      default:
        return Mode.debug;
    }
  }
}

class Mode extends NamedEnum {
  static const debug = Mode._('debug');
  static const product = Mode._('product');
  static const release = Mode._('release');

  static final List<String> names = _all.keys.toList();

  static final _all = Map<String, Mode>.fromIterable([debug, product, release],
      key: (mode) => (mode as Mode).name);

  static Mode find(String name) {
    var mode = _all[name];
    if (mode != null) return mode;

    throw ArgumentError('Unknown mode "$name".');
  }

  const Mode._(super.name);

  bool get isDebug => this == debug;
}

class Sanitizer extends NamedEnum {
  static const none = Sanitizer._('none');
  static const asan = Sanitizer._('asan');
  static const hwasan = Sanitizer._('hwasan');
  static const lsan = Sanitizer._('lsan');
  static const msan = Sanitizer._('msan');
  static const tsan = Sanitizer._('tsan');
  static const ubsan = Sanitizer._('ubsan');

  static final List<String> names = _all.keys.toList();

  static final _all = Map<String, Sanitizer>.fromIterable(
      [none, asan, hwasan, lsan, msan, tsan, ubsan],
      key: (mode) => (mode as Sanitizer).name);

  static Sanitizer find(String name) {
    var mode = _all[name];
    if (mode != null) return mode;

    throw ArgumentError('Unknown sanitizer "$name".');
  }

  const Sanitizer._(super.name);
}

class Runtime extends NamedEnum {
  static const vm = Runtime._('vm');
  static const flutter = Runtime._('flutter');
  static const dartPrecompiled = Runtime._('dart_precompiled');
  static const d8 = Runtime._('d8');
  static const jsc = Runtime._('jsc');
  static const jsshell = Runtime._('jsshell');
  static const firefox = Runtime._('firefox');
  static const chrome = Runtime._('chrome');
  static const safari = Runtime._('safari');
  static const edge = Runtime._('edge');
  static const chromeOnAndroid = Runtime._('chromeOnAndroid');
  static const none = Runtime._('none');

  static final List<String> names = _all.keys.toList();

  static final _all = Map<String, Runtime>.fromIterable([
    vm,
    flutter,
    dartPrecompiled,
    d8,
    jsc,
    jsshell,
    firefox,
    chrome,
    safari,
    edge,
    chromeOnAndroid,
    none
  ], key: (runtime) => (runtime as Runtime).name);

  static Runtime find(String name) {
    var runtime = _all[name];
    if (runtime != null) return runtime;

    throw ArgumentError('Unknown runtime "$name".');
  }

  const Runtime._(super.name);

  bool get isBrowser =>
      const [edge, safari, chrome, firefox, chromeOnAndroid].contains(this);

  bool get isSafari => name.startsWith("safari");

  /// Whether this runtime is a command-line JavaScript environment.
  bool get isJSCommandLine => const [d8, jsc, jsshell].contains(this);

  /// The preferred compiler to use with this runtime if no other compiler is
  /// specified.
  Compiler get defaultCompiler {
    switch (this) {
      case vm:
      case flutter:
        return Compiler.dartk;

      case dartPrecompiled:
        return Compiler.dartkp;

      case d8:
      case jsshell:
      case firefox:
      case chrome:
      case safari:
      case edge:
      case chromeOnAndroid:
        return Compiler.dart2js;

      case jsc:
        return Compiler.dart2wasm;

      case none:
        // If we aren't running it, we probably just want to analyze it.
        return Compiler.dart2analyzer;
    }

    throw "unreachable";
  }
}

class System extends NamedEnum {
  static const android = System._('android');
  static const fuchsia = System._('fuchsia');
  static const linux = System._('linux');
  static const mac = System._('mac');
  static const win = System._('win');

  static final List<String> names = _all.keys.toList();

  static final _all = Map<String, System>.fromIterable(
      [android, fuchsia, linux, mac, win],
      key: (system) => (system as System).name);

  /// Gets the system of the current machine.
  static System get host => find(Platform.operatingSystem);

  static System find(String name) {
    var system = _all[name];
    if (system != null) return system;

    // Also allow dart:io's names for the operating systems.
    switch (Platform.operatingSystem) {
      case "macos":
        return mac;
      case "windows":
        return win;
    }
    // TODO(rnystrom): What about ios?

    throw ArgumentError('Unknown operating system "$name".');
  }

  const System._(super.name);

  /// The root directory name for build outputs on this system.
  String get outputDirectory {
    switch (this) {
      case android:
      case fuchsia:
      case linux:
      case win:
        return 'out/';

      case mac:
        return 'xcodebuild/';
    }

    throw "unreachable";
  }
}

// TODO(rnystrom): NnbdMode.legacy can be removed now that opted out code is no
// longer supported. This entire enum and the notion of "NNBD modes" can be
// removed once it's no longer possible to run programs in unsound weak mode.
/// What level of non-nullability support should be applied to the test files.
class NnbdMode extends NamedEnum {
  /// "Opted out" legacy mode with no NNBD features allowed.
  static const legacy = NnbdMode._('legacy');

  /// Opted in to NNBD features, but only static checking and weak runtime
  /// checks.
  static const weak = NnbdMode._('weak');

  /// Opted in to NNBD features and with full sound runtime checks.
  static const strong = NnbdMode._('strong');

  static final List<String> names = _all.keys.toList();

  static final _all = {
    for (var mode in [legacy, weak, strong]) mode.name: mode
  };

  static NnbdMode find(String name) {
    var mode = _all[name];
    if (mode != null) return mode;

    throw ArgumentError('Unknown NNBD mode "$name".');
  }

  const NnbdMode._(super.name);
}

/// Base class for an enum-like class whose values are identified by name.
abstract class NamedEnum {
  final String name;

  const NamedEnum(this.name);

  @override
  String toString() => name;
}

final Map<String, String> _platformEnvironment = () {
  try {
    return Platform.environment;
  } catch (_) {
    // We might be running in the browser where Platform.environment just
    // throws.
    return const <String, String>{};
  }
}();
