// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library;

import 'dart:async' show Future;
import 'dart:convert' show jsonEncode;
import 'dart:typed_data';

import 'package:compiler/src/universe/use.dart' show StaticUse;
// ignore: implementation_imports
import 'package:front_end/src/api_unstable/dart2js.dart' as fe;
import 'package:kernel/ast.dart' as ir;

import '../compiler_api.dart' as api;
import 'common.dart';
import 'common/codegen.dart';
import 'common/elements.dart' show ElementEnvironment;
import 'common/metrics.dart' show Metric;
import 'common/names.dart' show Selectors;
import 'common/tasks.dart'
    show CompilerTask, GenericTask, GenericTaskWithMetrics, Measurer;
import 'common/work.dart' show WorkItem;
import 'deferred_load/deferred_load.dart' show DeferredLoadTask;
import 'deferred_load/output_unit.dart' show OutputUnitData;
import 'deferred_load/program_split_constraints/nodes.dart'
    as psc
    show ConstraintData;
import 'deferred_load/program_split_constraints/parser.dart' as psc show Parser;
import 'diagnostics/diagnostic_listener.dart';
import 'diagnostics/messages.dart' show Message;
import 'dump_info.dart'
    show
        DumpInfoJsAstRegistry,
        DumpInfoProgramData,
        DumpInfoStateData,
        DumpInfoTask;
import 'elements/entities.dart';
import 'enqueue.dart' show Enqueuer;
import 'environment.dart';
import 'inferrer/abstract_value_domain.dart';
import 'inferrer/abstract_value_strategy.dart';
import 'inferrer/computable.dart' show ComputableAbstractValueStrategy;
import 'inferrer/trivial.dart' show TrivialAbstractValueStrategy;
import 'inferrer/typemasks/masks.dart' show TypeMaskStrategy;
import 'inferrer/types.dart'
    show GlobalTypeInferenceResults, GlobalTypeInferenceTask;
import 'io/source_information.dart';
import 'js_backend/codegen_inputs.dart' show CodegenInputs;
import 'js_backend/enqueuer.dart';
import 'js_backend/inferred_data.dart';
import 'js_model/js_strategy.dart';
import 'js_model/js_world.dart';
import 'js_model/locals.dart';
import 'kernel/front_end_adapter.dart' show CompilerFileSystem;
import 'kernel/kernel_strategy.dart';
import 'kernel/kernel_world.dart';
import 'null_compiler_output.dart' show NullCompilerOutput;
import 'options.dart' show CompilerOptions, CompilerStage;
import 'phase/load_kernel.dart' as load_kernel;
import 'resolution/enqueuer.dart';
import 'serialization/serialization.dart';
import 'serialization/task.dart';
import 'serialization/strategies.dart';
import 'source_file_provider.dart';
import 'universe/selector.dart' show Selector;
import 'universe/codegen_world_builder.dart';
import 'universe/resolution_world_builder.dart';
import 'universe/world_impact.dart' show WorldImpact, WorldImpactBuilderImpl;

enum _ResolutionStatus { resolving, doneResolving, compiling }

/// Implementation of the compiler using a [api.CompilerInput] for supplying
/// the sources.
class Compiler {
  final Measurer measurer;
  final api.CompilerInput provider;
  final api.CompilerDiagnostics handler;

  late final KernelFrontendStrategy frontendStrategy;
  late final JsBackendStrategy backendStrategy;
  late final DiagnosticReporter _reporter;
  late final Map<Entity, WorldImpact> _impactCache;
  late final GenericTask userHandlerTask;
  late final GenericTask userProviderTask;

  /// Options provided from command-line arguments.
  final CompilerOptions options;

  // These internal flags are used to stop compilation after a specific phase.
  // Used only for debugging and testing purposes only.
  bool stopAfterClosedWorldForTesting = false;
  bool stopAfterGlobalTypeInferenceForTesting = false;

  /// Output provider from user of Compiler API.
  late final api.CompilerOutput _outputProvider;

  api.CompilerOutput get outputProvider => _outputProvider;

  late ir.Component componentForTesting;
  late JClosedWorld? backendClosedWorldForTesting;
  late ResolutionEnqueuer resolutionEnqueuerForTesting;
  late CodegenEnqueuer codegenEnqueuerForTesting;
  late DumpInfoStateData dumpInfoStateForTesting;

  ir.Component? untrimmedComponentForDumpInfo;

  DiagnosticReporter get reporter => _reporter;
  Map<Entity, WorldImpact> get impactCache => _impactCache;

  late final Environment environment;
  final DataReadMetrics dataReadMetrics = DataReadMetrics();

  late final List<CompilerTask> tasks;
  late final GenericTask loadKernelTask;
  fe.InitializedCompilerState? initializedCompilerState;
  bool forceSerializationForTesting = false;
  late final GlobalTypeInferenceTask globalInference;
  late final CodegenWorldBuilder _codegenWorldBuilder;

  late AbstractValueStrategy abstractValueStrategy;

  late final GenericTask selfTask;

  late final GenericTask enqueueTask;
  late final DeferredLoadTask deferredLoadTask;
  late final DumpInfoTask dumpInfoTask;
  final DumpInfoJsAstRegistry dumpInfoRegistry;
  late final SerializationTask serializationTask;

  Progress progress = const Progress();

  _ResolutionStatus? _resolutionStatus;

  CompilerStage get stage => options.stage;

  bool compilationFailed = false;

  psc.ConstraintData? programSplitConstraintsData;

  // Callback function used for testing resolution enqueuing.
  void Function()? onResolutionQueueEmptyForTesting;

  // Callback function used for testing codegen enqueuing.
  void Function()? onCodegenQueueEmptyForTesting;

  Compiler(
    this.provider,
    api.CompilerOutput outputProvider,
    this.handler,
    this.options,
  )
    // NOTE: allocating measurer is done upfront to ensure the wallclock is
    // started before other computations.
    : measurer = Measurer(enableTaskMeasurements: options.verbose),
      dumpInfoRegistry = DumpInfoJsAstRegistry(options) {
    options.deriveOptions();
    options.validate();
    environment = Environment(options.environment);

    abstractValueStrategy =
        options.useTrivialAbstractValueDomain
            ? const TrivialAbstractValueStrategy()
            : const TypeMaskStrategy();
    if (options.debugGlobalInference) {
      abstractValueStrategy = ComputableAbstractValueStrategy(
        abstractValueStrategy,
      );
    }

    CompilerTask kernelFrontEndTask;
    selfTask = GenericTaskWithMetrics('self', measurer, dataReadMetrics);
    _outputProvider = _CompilerOutput(this, outputProvider);
    _reporter = DiagnosticReporter(this);
    kernelFrontEndTask = GenericTask('Front end', measurer);
    frontendStrategy = KernelFrontendStrategy(
      kernelFrontEndTask,
      options,
      reporter,
    );
    backendStrategy = createBackendStrategy();
    _impactCache = <Entity, WorldImpact>{};

    if (options.showInternalProgress) {
      progress = InteractiveProgress();
    }

    tasks = [
      // [enqueueTask] is created earlier because it contains the resolution
      // world objects needed by other tasks.
      enqueueTask = GenericTask('Enqueue', measurer),
      loadKernelTask = GenericTask('kernel loader', measurer),
      kernelFrontEndTask,
      globalInference = GlobalTypeInferenceTask(this),
      deferredLoadTask = frontendStrategy.createDeferredLoadTask(this),
      dumpInfoTask = DumpInfoTask(options, measurer, _outputProvider, reporter),
      selfTask,
      serializationTask = SerializationTask(
        options,
        reporter,
        provider,
        outputProvider,
        measurer,
      ),
      ...backendStrategy.tasks,
      userHandlerTask = GenericTask('Diagnostic handler', measurer),
      userProviderTask = GenericTask('Input provider', measurer),
    ];

    initializedCompilerState = options.kernelInitializedCompilerState;
  }

  /// Creates the backend strategy.
  ///
  /// Override this to mock the backend strategy for testing.
  JsBackendStrategy createBackendStrategy() {
    return JsBackendStrategy(this);
  }

  ResolutionWorldBuilder? resolutionWorldBuilderForTesting;

  KClosedWorld? get frontendClosedWorldForTesting =>
      resolutionWorldBuilderForTesting?.closedWorldForTesting;

  CodegenWorldBuilder get codegenWorldBuilder => _codegenWorldBuilder;

  CodegenWorld? codegenWorldForTesting;

  bool get disableTypeInference =>
      options.disableTypeInference || compilationFailed;

  // Compiles the dart program as specified in [options].
  //
  // The resulting future will complete with true if the compilation
  // succeeded.
  Future<bool> run() => selfTask.measureSubtask("run", () async {
    measurer.startWallClock();
    var setupDuration = measurer.elapsedWallClock;
    try {
      await runInternal();
    } catch (error, stackTrace) {
      await _reporter.onError(options.compilationTarget, error, stackTrace);
    } finally {
      measurer.stopWallClock();
    }
    dataReadMetrics.addDataRead(provider);
    if (options.verbose) {
      var timings = StringBuffer();
      computeTimings(setupDuration, timings);
      logVerbose('$timings');
    }
    if (options.reportPrimaryMetrics || options.reportSecondaryMetrics) {
      var metrics = StringBuffer();
      collectMetrics(metrics);
      logInfo('$metrics');
    }
    return !compilationFailed;
  });

  /// Dumps a list of unused [ir.Library]'s in the [KernelResult]. This *must*
  /// be called before [setMainAndTrimComponent], because that method will
  /// discard the unused [ir.Library]s.
  void dumpUnusedLibraries(ir.Component component, Set<Uri> libraries) {
    bool isUnused(ir.Library l) => !libraries.contains(l.importUri);
    String libraryString(ir.Library library) {
      return '${library.importUri}(${library.fileUri})';
    }

    var unusedLibraries =
        component.libraries.where(isUnused).map(libraryString).toList();
    unusedLibraries.sort();
    var jsonLibraries = jsonEncode(unusedLibraries);
    outputProvider.createOutputSink(
        options.outputUri!.pathSegments.last,
        'unused.json',
        api.OutputType.dumpUnusedLibraries,
      )
      ..add(jsonLibraries)
      ..close();
    reporter.reportInfo(
      reporter.createMessage(noLocationSpannable, MessageKind.generic, {
        'text':
            "${unusedLibraries.length} unused libraries out of "
            "${component.libraries.length}. Dumping to JSON.",
      }),
    );
  }

  /// Trims a component down to only the provided library uris.
  ir.Component trimComponent(
    ir.Component component,
    Set<Uri> librariesToInclude,
  ) {
    var irLibraryMap = <Uri, ir.Library>{};
    var irLibraries = <ir.Library>[];
    for (var library in component.libraries) {
      irLibraryMap[library.importUri] = library;
    }
    for (var library in librariesToInclude) {
      irLibraries.add(irLibraryMap[library]!);
    }
    var mainMethod = component.mainMethodName;
    final trimmedComponent = ir.Component(
      libraries: irLibraries,
      uriToSource: component.uriToSource,
      nameRoot: component.root,
    );
    trimmedComponent.setMainMethodAndMode(mainMethod, true);
    return trimmedComponent;
  }

  Future<void> runInternal() async {
    clearState();
    var compilationTarget = options.compilationTarget;
    reporter.log('Compiling $compilationTarget (${options.buildId})');

    if (options.readProgramSplit != null) {
      var constraintUri = options.readProgramSplit;
      var constraintParser = psc.Parser();
      var programSplitJson =
          await CompilerFileSystem(
            provider,
          ).entityForUri(constraintUri!).readAsString();
      programSplitConstraintsData = constraintParser.read(programSplitJson);
    }

    await selfTask.measureSubtask("compileFromKernel", () async {
      await runSequentialPhases();
    });
  }

  /// Clear the internal compiler state to prevent memory leaks when invoking
  /// the compiler multiple times (e.g. in batch mode).
  // TODO(ahe): implement a better mechanism where we can store
  // such caches in the compiler and get access to them through a
  // suitably maintained static reference to the current compiler.
  void clearState() {
    Selector.canonicalizedValues.clear();
    StaticUse.clearCache();

    // The selector objects held in static fields must remain canonical.
    for (Selector selector in Selectors.all) {
      Selector.canonicalizedValues
          .putIfAbsent(selector.hashCode, () => <Selector>[])
          .add(selector);
    }
  }

  JClosedWorld? computeClosedWorld(
    ir.Component component,
    Uri rootLibraryUri,
    List<Uri> libraries,
  ) {
    frontendStrategy.registerLoadedLibraries(component, libraries);
    ResolutionEnqueuer resolutionEnqueuer = frontendStrategy
        .createResolutionEnqueuer(enqueueTask, this)
      ..onEmptyForTesting = onResolutionQueueEmptyForTesting;
    if (retainDataForTesting) {
      resolutionEnqueuerForTesting = resolutionEnqueuer;
      resolutionWorldBuilderForTesting = resolutionEnqueuer.worldBuilder;
    }
    frontendStrategy.onResolutionStart();
    for (LibraryEntity library
        in frontendStrategy.elementEnvironment.libraries) {
      frontendStrategy.elementEnvironment.forEachClass(library, (
        ClassEntity cls,
      ) {
        // Register all classes eagerly to optimize closed world computation in
        // `ClassWorldBuilder.isInheritedInSubtypeOf`.
        resolutionEnqueuer.worldBuilder.registerClass(cls);
      });
    }
    WorldImpactBuilderImpl mainImpact = WorldImpactBuilderImpl();
    final mainFunction = frontendStrategy.computeMain(mainImpact);

    // In order to see if a library is deferred, we must compute the
    // compile-time constants that are metadata.  This means adding
    // something to the resolution queue.  So we cannot wait with
    // this until after the resolution queue is processed.
    deferredLoadTask.beforeResolution(rootLibraryUri, libraries);

    _resolutionStatus = _ResolutionStatus.resolving;
    resolutionEnqueuer.applyImpact(mainImpact);
    if (options.showInternalProgress) reporter.log('Computing closed world');

    processQueue(
      frontendStrategy.elementEnvironment,
      resolutionEnqueuer,
      mainFunction,
      onProgress: showResolutionProgress,
    );
    resolutionEnqueuer.logSummary(reporter.log);

    _reporter.reportSuppressedMessagesSummary();

    if (compilationFailed) {
      return null;
    }

    checkQueue(resolutionEnqueuer);

    JClosedWorld? closedWorld = closeResolution(
      mainFunction!,
      resolutionEnqueuer.worldBuilder,
    );
    return closedWorld;
  }

  Future<load_kernel.Output?> loadKernel() async {
    final input = load_kernel.Input(
      options,
      provider,
      reporter,
      initializedCompilerState,
      forceSerializationForTesting,
    );
    load_kernel.Output? output = await loadKernelTask.measure(
      () async => load_kernel.run(input),
    );
    reporter.log("Kernel load complete");
    return output;
  }

  Future<load_kernel.Output?> produceKernel() async {
    if (!stage.shouldReadClosedWorld) {
      load_kernel.Output? output = await loadKernel();
      if (output == null) return null;
      if (compilationFailed) {
        // Some tests still use the component, even if the CFE failed.
        frontendStrategy.registerComponent(output.component);
        return null;
      }
      ir.Component component = output.component;
      if (retainDataForTesting) {
        componentForTesting = component;
      }
      if (options.features.newDumpInfo.isEnabled && stage.emitsDumpInfo) {
        untrimmedComponentForDumpInfo = component;
      }
      if (stage.shouldOnlyComputeDill) {
        Set<Uri> includedLibraries = output.libraries!.toSet();
        if (options.shouldLoadFromDill) {
          if (options.dumpUnusedLibraries) {
            dumpUnusedLibraries(component, includedLibraries);
          }
          if (options.entryUri != null) {
            component = trimComponent(component, includedLibraries);
          }
        }
        serializationTask.serializeComponent(
          component,
          includeSourceBytes: false,
        );
      }
      return output.withNewComponent(component);
    } else {
      ir.Component component =
          await serializationTask.deserializeComponentAndUpdateOptions();
      if (retainDataForTesting) {
        componentForTesting = component;
      }
      return load_kernel.Output(component, null, null, null);
    }
  }

  bool shouldStopAfterLoadKernel(load_kernel.Output? output) =>
      output == null || compilationFailed || stage.shouldOnlyComputeDill;

  GlobalTypeInferenceResults performGlobalTypeInference(
    JClosedWorld closedWorld,
  ) {
    FunctionEntity mainFunction = closedWorld.elementEnvironment.mainFunction!;
    reporter.log('Performing global type inference');
    GlobalLocalsMap globalLocalsMap = GlobalLocalsMap(
      closedWorld.closureDataLookup.getEnclosingMember,
    );
    InferredDataBuilder inferredDataBuilder = InferredDataBuilderImpl(
      closedWorld.annotationsData,
    );
    return globalInference.runGlobalTypeInference(
      mainFunction,
      closedWorld,
      globalLocalsMap,
      inferredDataBuilder,
    );
  }

  int runCodegenEnqueuer(
    CodegenResults codegenResults,
    InferredData inferredData,
    SourceLookup sourceLookup,
    JClosedWorld closedWorld,
  ) {
    CodegenInputs codegenInputs = codegenResults.codegenInputs;
    CodegenEnqueuer codegenEnqueuer = backendStrategy.createCodegenEnqueuer(
      enqueueTask,
      closedWorld,
      inferredData,
      codegenInputs,
      codegenResults,
      sourceLookup,
    )..onEmptyForTesting = onCodegenQueueEmptyForTesting;
    if (retainDataForTesting) {
      codegenEnqueuerForTesting = codegenEnqueuer;
    }
    _codegenWorldBuilder = codegenEnqueuer.worldBuilder;

    reporter.log('Compiling methods');
    FunctionEntity mainFunction = closedWorld.elementEnvironment.mainFunction!;
    processQueue(
      closedWorld.elementEnvironment,
      codegenEnqueuer,
      mainFunction,
      onProgress: showCodegenProgress,
    );
    codegenEnqueuer.logSummary(reporter.log);
    CodegenWorld codegenWorld = codegenWorldBuilder.close();
    if (retainDataForTesting) {
      codegenWorldForTesting = codegenWorld;
    }
    reporter.log('Emitting JavaScript');
    int programSize = backendStrategy.assembleProgram(
      closedWorld,
      inferredData,
      codegenInputs,
      codegenWorld,
    );

    backendStrategy.onCodegenEnd(codegenInputs);

    checkQueue(codegenEnqueuer);
    return programSize;
  }

  JClosedWorld closedWorldTestMode(JClosedWorld closedWorld) {
    SerializationIndices indices = SerializationIndices(testMode: true);
    final strategy = const BytesInMemorySerializationStrategy(
      useDataKinds: true,
    );
    // TODO(natebiggs): Add when kernel offsets are consistent across
    //   serialization layer.
    // List<int> irData = strategy
    //     .serializeComponent(closedWorld.elementMap.programEnv.mainComponent);
    // final component = strategy.deserializeComponent(irData);
    List<int> closedWorldData = strategy.serializeClosedWorld(
      closedWorld,
      options,
      indices,
    );
    final component = closedWorld.elementMap.programEnv.mainComponent;
    return strategy.deserializeClosedWorld(
      options,
      reporter,
      abstractValueStrategy,
      component,
      closedWorldData,
      indices,
    );
  }

  GlobalTypeInferenceResults globalTypeInferenceResultsTestMode(
    GlobalTypeInferenceResults results,
  ) {
    SerializationIndices indices = SerializationIndices(testMode: true);
    final strategy = const BytesInMemorySerializationStrategy(
      useDataKinds: true,
    );
    final closedWorld = results.closedWorld;
    final component = closedWorld.elementMap.programEnv.mainComponent;
    List<int> globalTypeInferenceResultsData = strategy
        .serializeGlobalTypeInferenceResults(results, options, indices);
    return strategy.deserializeGlobalTypeInferenceResults(
      options,
      reporter,
      environment,
      abstractValueStrategy,
      component,
      closedWorld,
      globalTypeInferenceResultsData,
      indices,
    );
  }

  Future<JClosedWorld?> produceClosedWorld(
    load_kernel.Output output,
    SerializationIndices indices,
  ) async {
    ir.Component component = output.component;
    JClosedWorld? closedWorld;
    if (!stage.shouldReadClosedWorld) {
      Uri rootLibraryUri = output.rootLibraryUri!;
      List<Uri> libraries = output.libraries!;
      closedWorld = computeClosedWorld(component, rootLibraryUri, libraries);
      if (stage.shouldWriteClosedWorld && closedWorld != null) {
        serializationTask.serializeClosedWorld(closedWorld, indices);
        if (options.producesModifiedDill) {
          serializationTask.serializeComponent(
            component,
            includeSourceBytes: false,
          );
        }
      } else if (options.testMode && closedWorld != null) {
        closedWorld = closedWorldTestMode(closedWorld);
        backendStrategy.registerJClosedWorld(closedWorld);
      }
    } else {
      closedWorld = await serializationTask.deserializeClosedWorld(
        abstractValueStrategy,
        component,
        useDeferredSourceReads,
        indices,
      );
    }
    if (retainDataForTesting) {
      backendClosedWorldForTesting = closedWorld;
    }
    return closedWorld;
  }

  bool shouldStopAfterClosedWorld(JClosedWorld? closedWorld) =>
      closedWorld == null ||
      stage.shouldWriteClosedWorld ||
      stage.emitsDeferredLoadIds ||
      stopAfterClosedWorldForTesting;

  Future<GlobalTypeInferenceResults> produceGlobalTypeInferenceResults(
    JClosedWorld closedWorld,
    ir.Component component,
    SerializationIndices indices,
  ) async {
    GlobalTypeInferenceResults globalTypeInferenceResults;
    if (!stage.shouldReadGlobalInference) {
      globalTypeInferenceResults = performGlobalTypeInference(closedWorld);
      if (stage.shouldWriteGlobalInference) {
        serializationTask.serializeGlobalTypeInference(
          globalTypeInferenceResults,
          indices,
        );
      } else if (options.testMode) {
        globalTypeInferenceResults = globalTypeInferenceResultsTestMode(
          globalTypeInferenceResults,
        );
      }
    } else {
      globalTypeInferenceResults = await serializationTask
          .deserializeGlobalTypeInferenceResults(
            environment,
            abstractValueStrategy,
            closedWorld.elementMap.programEnv.mainComponent,
            closedWorld,
            useDeferredSourceReads,
            indices,
          );
    }
    return globalTypeInferenceResults;
  }

  bool get shouldStopAfterGlobalTypeInference =>
      stage.shouldWriteGlobalInference ||
      stopAfterGlobalTypeInferenceForTesting;

  CodegenInputs initializeCodegen(
    GlobalTypeInferenceResults globalTypeInferenceResults,
  ) {
    backendStrategy.registerJClosedWorld(
      globalTypeInferenceResults.closedWorld,
    );
    _resolutionStatus = _ResolutionStatus.compiling;
    return backendStrategy.onCodegenStart(globalTypeInferenceResults);
  }

  Future<CodegenResults> produceCodegenResults(
    GlobalTypeInferenceResults globalTypeInferenceResults,
    SourceLookup sourceLookup,
    SerializationIndices indices,
  ) async {
    CodegenInputs codegenInputs = initializeCodegen(globalTypeInferenceResults);
    CodegenResults codegenResults;
    if (stage.shouldReadCodegenShards && options.codegenShards != null) {
      codegenResults = await serializationTask.deserializeCodegen(
        backendStrategy,
        globalTypeInferenceResults.closedWorld,
        codegenInputs,
        useDeferredSourceReads,
        sourceLookup,
        indices,
      );
    } else {
      codegenResults = OnDemandCodegenResults(
        codegenInputs,
        backendStrategy.functionCompiler,
      );
      if (stage.shouldWriteCodegen) {
        serializationTask.serializeCodegen(
          backendStrategy,
          globalTypeInferenceResults.closedWorld.abstractValueDomain,
          codegenResults,
          indices,
        );
      }
    }
    return codegenResults;
  }

  bool get shouldStopAfterCodegen => stage.shouldWriteCodegen;

  bool get useDeferredSourceReads => stage.shouldUseDeferredSourceReads;

  Future<void> runSequentialPhases() async {
    // Load kernel.
    final output = await produceKernel();
    if (shouldStopAfterLoadKernel(output)) return;

    final indices = SerializationIndices();

    // Compute closed world.
    JClosedWorld? closedWorld = await produceClosedWorld(output!, indices);
    if (shouldStopAfterClosedWorld(closedWorld)) return;

    // Run global analysis.
    GlobalTypeInferenceResults globalTypeInferenceResults =
        await produceGlobalTypeInferenceResults(
          closedWorld!,
          output.component,
          indices,
        );
    if (shouldStopAfterGlobalTypeInference) return;
    closedWorld = globalTypeInferenceResults.closedWorld;

    // Allow the original references to these to be GCed and only hold
    // references to them if we are actually running the dump info task later.
    SerializationIndices? indicesForDumpInfo;
    GlobalTypeInferenceResults? globalTypeInferenceResultsForDumpInfo;
    AbstractValueDomain? abstractValueDomainForDumpInfo;
    OutputUnitData? outputUnitDataForDumpInfo;
    DataSinkWriter? sinkForDumpInfo;
    if (stage.emitsDumpInfo) {
      globalTypeInferenceResultsForDumpInfo = globalTypeInferenceResults;
      abstractValueDomainForDumpInfo = closedWorld.abstractValueDomain;
      outputUnitDataForDumpInfo = closedWorld.outputUnitData;
      indicesForDumpInfo = indices;
    } else if (stage.shouldWriteDumpInfoData) {
      sinkForDumpInfo = serializationTask.dataSinkWriterForDumpInfo(
        closedWorld.abstractValueDomain,
        indices,
      );
      dumpInfoRegistry.registerDataSinkWriter(sinkForDumpInfo);
    }

    // Run codegen.
    final sourceLookup = SourceLookup(output.component);
    CodegenResults codegenResults = await produceCodegenResults(
      globalTypeInferenceResults,
      sourceLookup,
      indices,
    );
    if (shouldStopAfterCodegen) return;
    final inferredData = globalTypeInferenceResults.inferredData;

    if (stage.shouldReadDumpInfoData) {
      final dumpInfoData = await serializationTask
          .deserializeDumpInfoProgramData(
            backendStrategy,
            abstractValueDomainForDumpInfo!,
            outputUnitDataForDumpInfo!,
            indicesForDumpInfo!,
          );
      await runDumpInfo(
        codegenResults,
        globalTypeInferenceResultsForDumpInfo!,
        dumpInfoData,
      );
    } else {
      // Link.
      final programSize = runCodegenEnqueuer(
        codegenResults,
        inferredData,
        sourceLookup,
        closedWorld,
      );
      if (stage.emitsDumpInfo || stage.shouldWriteDumpInfoData) {
        final dumpInfoData = DumpInfoProgramData.fromEmitterResults(
          backendStrategy.emitterTask,
          dumpInfoRegistry,
          codegenResults,
          programSize,
        );
        dumpInfoRegistry.close();
        if (stage.shouldWriteDumpInfoData) {
          serializationTask.serializeDumpInfoProgramData(
            sinkForDumpInfo!,
            backendStrategy,
            dumpInfoData,
            dumpInfoRegistry,
          );
        } else {
          await runDumpInfo(
            codegenResults,
            globalTypeInferenceResultsForDumpInfo!,
            dumpInfoData,
          );
        }
      }
    }
  }

  Future<void> runDumpInfo(
    CodegenResults codegenResults,
    GlobalTypeInferenceResults globalTypeInferenceResults,
    DumpInfoProgramData dumpInfoProgramData,
  ) async {
    JClosedWorld closedWorld = globalTypeInferenceResults.closedWorld;

    DumpInfoStateData dumpInfoState;
    dumpInfoTask.registerDumpInfoProgramData(dumpInfoProgramData);
    if (options.features.newDumpInfo.isEnabled) {
      untrimmedComponentForDumpInfo ??= (await produceKernel())!.component;
      dumpInfoState = await dumpInfoTask.dumpInfoNew(
        untrimmedComponentForDumpInfo!,
        closedWorld,
        globalTypeInferenceResults,
        codegenResults,
        backendStrategy,
      );
    } else {
      dumpInfoState = await dumpInfoTask.dumpInfo(
        closedWorld,
        globalTypeInferenceResults,
        codegenResults,
        backendStrategy,
      );
    }
    if (retainDataForTesting) {
      dumpInfoStateForTesting = dumpInfoState;
    }
  }

  /// Perform the steps needed to fully end the resolution phase.
  JClosedWorld? closeResolution(
    FunctionEntity mainFunction,
    ResolutionWorldBuilder resolutionWorldBuilder,
  ) {
    _resolutionStatus = _ResolutionStatus.doneResolving;

    KClosedWorld kClosedWorld = resolutionWorldBuilder.closeWorld(reporter);
    OutputUnitData result = deferredLoadTask.run(mainFunction, kClosedWorld);
    if (stage.emitsDeferredLoadIds) return null;

    // Impact data is no longer needed.
    if (!retainDataForTesting) {
      _impactCache.clear();
    }
    JClosedWorld jClosedWorld = backendStrategy.createJClosedWorld(
      kClosedWorld,
      result,
    );
    return jClosedWorld;
  }

  /// Empty the [enqueuer] queue.
  void emptyQueue(
    Enqueuer enqueuer, {
    void Function(Enqueuer enqueuer)? onProgress,
  }) {
    selfTask.measureSubtask("emptyQueue", () {
      enqueuer.forEach((WorkItem work) {
        if (onProgress != null) {
          onProgress(enqueuer);
        }
        reporter.withCurrentElement(
          work.element,
          () => selfTask.measureSubtask("applyImpact", () {
            enqueuer.applyImpact(
              selfTask.measureSubtask("work.run", () => work.run()),
            );
          }),
        );
      });
    });
  }

  void processQueue(
    ElementEnvironment elementEnvironment,
    Enqueuer enqueuer,
    FunctionEntity? mainMethod, {
    void Function(Enqueuer enqueuer)? onProgress,
  }) {
    selfTask.measureSubtask("processQueue", () {
      enqueuer.open(
        mainMethod,
        elementEnvironment.libraries.map(
          (LibraryEntity library) => library.canonicalUri,
        ),
      );
      progress.startPhase();
      emptyQueue(enqueuer, onProgress: onProgress);
      enqueuer.queueIsClosed = true;
      enqueuer.close();
      assert(
        compilationFailed ||
            enqueuer.checkNoEnqueuedInvokedInstanceMethods(elementEnvironment),
      );
    });
  }

  /// Perform various checks of the queue. This includes checking that the
  /// queues are empty (nothing was added after we stopped processing the
  /// queues).
  void checkQueue(Enqueuer enqueuer) {
    enqueuer.checkQueueIsEmpty();
  }

  void showResolutionProgress(Enqueuer enqueuer) {
    assert(
      _resolutionStatus == _ResolutionStatus.resolving,
      'Unexpected phase: $_resolutionStatus',
    );
    progress.showProgress(
      'Resolved ',
      enqueuer.processedEntities.length,
      ' elements.',
    );
  }

  void showCodegenProgress(Enqueuer enqueuer) {
    progress.showProgress(
      'Compiled ',
      enqueuer.processedEntities.length,
      ' methods.',
    );
  }

  void reportDiagnostic(
    DiagnosticMessage message,
    List<DiagnosticMessage> infos,
    api.Diagnostic kind,
  ) {
    _reportDiagnosticMessage(message, kind);
    for (DiagnosticMessage info in infos) {
      _reportDiagnosticMessage(info, api.Diagnostic.context);
    }
  }

  void _reportDiagnosticMessage(
    DiagnosticMessage diagnosticMessage,
    api.Diagnostic kind,
  ) {
    var span = diagnosticMessage.sourceSpan;
    var message = diagnosticMessage.message;
    // If the message came from the CFE use the message code as the text
    // so that tests can determine the cause of the message.
    final messageText =
        diagnosticMessage is DiagnosticCfeMessage && options.testMode
            ? diagnosticMessage.messageCode
            : '$message';
    if (span.isUnknown) {
      callUserHandler(message, null, null, null, messageText, kind);
    } else {
      callUserHandler(
        message,
        span.uri,
        span.begin,
        span.end,
        messageText,
        kind,
      );
    }
  }

  void callUserHandler(
    Message? message,
    Uri? uri,
    int? begin,
    int? end,
    String text,
    api.Diagnostic kind,
  ) {
    try {
      userHandlerTask.measure(() {
        handler.report(message, uri, begin, end, text, kind);
      });
    } catch (ex, s) {
      reportCrashInUserCode('Uncaught exception in diagnostic handler', ex, s);
      rethrow;
    }
  }

  Future<api.Input<Uint8List>> callUserProvider(
    Uri uri,
    api.InputKind inputKind,
  ) {
    try {
      return userProviderTask.measureIo(
        () => provider.readFromUri(uri, inputKind: inputKind),
      );
    } catch (ex, s) {
      reportCrashInUserCode('Uncaught exception in input provider', ex, s);
      rethrow;
    }
  }

  void reportCrashInUserCode(
    String message,
    Object exception,
    StackTrace stackTrace,
  ) {
    reporter.onCrashInUserCode(message, exception, stackTrace);
  }

  /// Messages for which compile-time errors are reported but compilation
  /// continues regardless.
  static const List<MessageKind> benignErrors = <MessageKind>[
    MessageKind.invalidMetadata,
    MessageKind.invalidMetadataGeneric,
  ];

  bool markCompilationAsFailed(DiagnosticMessage message, api.Diagnostic kind) {
    if (options.testMode) {
      // When in test mode, i.e. on the build-bot, we always stop compilation.
      return true;
    }
    if (reporter.options.fatalWarnings) {
      return true;
    }
    return !benignErrors.contains(message.message.kind);
  }

  void fatalDiagnosticReported(
    DiagnosticMessage message,
    List<DiagnosticMessage> infos,
    api.Diagnostic kind,
  ) {
    if (markCompilationAsFailed(message, kind)) {
      compilationFailed = true;
    }
  }

  /// Compute a [SourceSpan] from spannable using the [currentElement] as
  /// context.
  SourceSpan spanFromSpannable(Spannable spannable, Entity? currentElement) {
    SourceSpan span;
    if (_resolutionStatus == _ResolutionStatus.compiling) {
      span = backendStrategy.spanFromSpannable(spannable, currentElement);
    } else {
      span = frontendStrategy.spanFromSpannable(spannable, currentElement);
    }
    return span;
  }

  /// Helper for determining whether [element] is declared within 'user code'.
  bool inUserCode(Entity? element) {
    return element == null || _uriFromElement(element) != null;
  }

  /// Return a canonical URI for the source of [element].
  ///
  /// For a package library with canonical URI 'package:foo/bar/baz.dart' the
  /// return URI is 'package:foo'. For non-package libraries the returned URI is
  /// the canonical URI of the library itself.
  Uri? getCanonicalUri(Entity element) {
    final libraryUri = _uriFromElement(element);
    if (libraryUri == null) return null;
    if (libraryUri.isScheme('package')) {
      int slashPos = libraryUri.path.indexOf('/');
      if (slashPos != -1) {
        String packageName = libraryUri.path.substring(0, slashPos);
        return Uri(scheme: 'package', path: packageName);
      }
    }
    return libraryUri;
  }

  Uri? _uriFromElement(Entity element) {
    if (element is LibraryEntity) {
      return element.canonicalUri;
    } else if (element is ClassEntity) {
      return element.library.canonicalUri;
    } else if (element is MemberEntity) {
      return element.library.canonicalUri;
    }
    return null;
  }

  void logInfo(String message) {
    callUserHandler(null, null, null, null, message, api.Diagnostic.info);
  }

  void logVerbose(String message) {
    callUserHandler(
      null,
      null,
      null,
      null,
      message,
      api.Diagnostic.verboseInfo,
    );
  }

  String _formatMs(int ms) {
    return '${(ms / 1000).toStringAsFixed(3)}s';
  }

  void computeTimings(Duration setupDuration, StringBuffer timings) {
    timings.writeln("Timings:");
    var totalDuration = measurer.elapsedWallClock;
    var asyncDuration = measurer.elapsedAsyncWallClock;
    var cumulatedDuration = Duration.zero;
    var timingData = <_TimingData>[];
    for (final task in tasks) {
      var running = task.isRunning ? "*" : " ";
      var duration = task.duration;
      if (duration != Duration.zero) {
        cumulatedDuration += duration;
        var milliseconds = duration.inMilliseconds;
        timingData.add(
          _TimingData(
            '   $running${task.name}:',
            milliseconds,
            milliseconds * 100 / totalDuration.inMilliseconds,
          ),
        );
        for (String subtask in task.subtasks) {
          var subtime = task.getSubtaskTime(subtask);
          var running = task.getSubtaskIsRunning(subtask) ? "*" : " ";
          timingData.add(
            _TimingData(
              '   $running${task.name} > $subtask:',
              subtime,
              subtime * 100 / totalDuration.inMilliseconds,
            ),
          );
        }
      }
    }
    int longestDescription = timingData
        .map((d) => d.description.length)
        .fold(0, (a, b) => a < b ? b : a);
    for (var data in timingData) {
      var ms = _formatMs(data.milliseconds);
      var padding =
          " " * (longestDescription + 10 - data.description.length - ms.length);
      var percentPadding = data.percent < 10 ? " " : "";
      timings.writeln(
        '${data.description}$padding $ms '
        '$percentPadding(${data.percent.toStringAsFixed(1)}%)',
      );
    }
    var unaccountedDuration =
        totalDuration - cumulatedDuration - setupDuration - asyncDuration;
    var percent =
        unaccountedDuration.inMilliseconds * 100 / totalDuration.inMilliseconds;
    timings.write(
      '    Total compile-time ${_formatMs(totalDuration.inMilliseconds)};'
      ' setup ${_formatMs(setupDuration.inMilliseconds)};'
      ' async ${_formatMs(asyncDuration.inMilliseconds)};'
      ' unaccounted ${_formatMs(unaccountedDuration.inMilliseconds)}'
      ' (${percent.toStringAsFixed(2)}%)',
    );
  }

  void collectMetrics(StringBuffer buffer) {
    buffer.writeln('Metrics:');
    for (final task in tasks) {
      var metrics = task.metrics;
      var namespace = metrics.namespace;
      if (namespace == '') {
        namespace = task.name.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '_',
        );
      }
      void report(Metric metric) {
        buffer.writeln('  $namespace.${metric.name}: ${metric.formatValue()}');
      }

      for (final metric in metrics.primary) {
        report(metric);
      }
      if (options.reportSecondaryMetrics) {
        for (final metric in metrics.secondary) {
          report(metric);
        }
      }
    }
  }
}

class _CompilerOutput implements api.CompilerOutput {
  final Compiler _compiler;
  final api.CompilerOutput _userOutput;

  _CompilerOutput(this._compiler, api.CompilerOutput? output)
    : _userOutput = output ?? const NullCompilerOutput();

  @override
  api.OutputSink createOutputSink(
    String name,
    String extension,
    api.OutputType type,
  ) {
    if (_compiler.compilationFailed) {
      // Ensure that we don't emit output when the compilation has failed.
      return const NullCompilerOutput().createOutputSink(name, extension, type);
    }
    return _userOutput.createOutputSink(name, extension, type);
  }

  @override
  api.BinaryOutputSink createBinarySink(Uri uri) {
    return _userOutput.createBinarySink(uri);
  }
}

class _TimingData {
  final String description;
  final int milliseconds;
  final double percent;

  _TimingData(this.description, this.milliseconds, this.percent);
}

/// Interface for showing progress during compilation.
class Progress {
  const Progress();

  /// Starts a new phase for which to show progress.
  void startPhase() {}

  /// Shows progress of the current phase if needed. The shown message is
  /// computed as '$prefix$count$suffix'.
  void showProgress(String prefix, int count, String suffix) {}
}

/// Progress implementations that prints progress to the [DiagnosticReporter]
/// with 500ms intervals.
class ProgressImpl implements Progress {
  final DiagnosticReporter _reporter;
  final Stopwatch _stopwatch = Stopwatch()..start();

  ProgressImpl(this._reporter);

  @override
  void showProgress(String prefix, int count, String suffix) {
    if (_stopwatch.elapsedMilliseconds > 500) {
      _reporter.log('$prefix$count$suffix');
      _stopwatch.reset();
    }
  }

  @override
  void startPhase() {
    _stopwatch.reset();
  }
}

/// Progress implementations that prints progress to the [DiagnosticReporter]
/// with 500ms intervals using escape sequences to keep the progress data on a
/// single line.
class InteractiveProgress implements Progress {
  final Stopwatch _stopwatchPhase = Stopwatch()..start();
  final Stopwatch _stopwatchInterval = Stopwatch()..start();

  @override
  void startPhase() {
    print('');
    _stopwatchPhase.reset();
    _stopwatchInterval.reset();
  }

  @override
  void showProgress(String prefix, int count, String suffix) {
    if (_stopwatchInterval.elapsedMilliseconds > 500) {
      var time = _stopwatchPhase.elapsedMilliseconds / 1000;
      var rate = count / _stopwatchPhase.elapsedMilliseconds;
      var s =
          StringBuffer('\x1b[1A\x1b[K') // go up and clear the line.
            ..write('\x1b[48;5;40m\x1b[30m==>\x1b[0m $prefix')
            ..write(count)
            ..write('$suffix Elapsed time: ')
            ..write(time.toStringAsFixed(2))
            ..write(' s. Rate: ')
            ..write(rate.toStringAsFixed(2))
            ..write(' units/ms');
      print('$s');
      _stopwatchInterval.reset();
    }
  }
}
