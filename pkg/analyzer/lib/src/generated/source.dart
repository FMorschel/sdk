// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer/src/context/source.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/sdk.dart' show DartSdk;
import 'package:path/path.dart' as path;

/// Base class providing implementations for the methods in [Source] that don't
/// require filesystem access.
abstract class BasicSource extends Source {
  @override
  final Uri uri;

  BasicSource(this.uri);

  @override
  String get fullName => '$uri';

  @override
  int get hashCode => uri.hashCode;

  @override
  String get shortName => path.basename(fullName);

  @override
  bool operator ==(Object other) => other is Source && other.uri == uri;
}

/// Instances of the class `DartUriResolver` resolve `dart` URI's.
class DartUriResolver extends UriResolver {
  /// The name of the `dart` scheme.
  static String DART_SCHEME = "dart";

  /// The Dart SDK against which URI's are to be resolved.
  final DartSdk _sdk;

  /// Initialize a newly created resolver to resolve Dart URI's against the
  /// given platform within the given Dart SDK.
  DartUriResolver(this._sdk);

  /// Return the [DartSdk] against which URIs are to be resolved.
  ///
  /// @return the [DartSdk] against which URIs are to be resolved.
  DartSdk get dartSdk => _sdk;

  @override
  Uri? pathToUri(String path) {
    return _sdk.pathToUri(path);
  }

  @override
  Source? resolveAbsolute(Uri uri) {
    if (!isDartUri(uri)) {
      return null;
    }
    return _sdk.mapDartUri(uri.toString());
  }

  /// Return `true` if the given URI is a `dart:` URI.
  ///
  /// @param uri the URI being tested
  /// @return `true` if the given URI is a `dart:` URI
  static bool isDartUri(Uri uri) => uri.isScheme(DART_SCHEME);
}

/// An implementation of an non-existing [Source].
class NonExistingSource extends Source {
  static final unknown = NonExistingSource(
    '/unknown.dart',
    path.toUri('/unknown.dart'),
  );

  @override
  final String fullName;

  @override
  final Uri uri;

  NonExistingSource(this.fullName, this.uri);

  @override
  TimestampedData<String> get contents {
    throw UnsupportedError('$fullName does not exist.');
  }

  @override
  int get hashCode => fullName.hashCode;

  @override
  String get shortName => path.basename(fullName);

  @override
  bool operator ==(Object other) {
    if (other is NonExistingSource) {
      return other.uri == uri && other.fullName == fullName;
    }
    return false;
  }

  @override
  bool exists() => false;

  @override
  String toString() => 'NonExistingSource($uri, $fullName)';
}

/// Instances of the class `SourceFactory` resolve possibly relative URI's
/// against an existing [Source].
abstract class SourceFactory {
  /// Initialize a newly created source factory with the given absolute URI
  /// [resolvers].
  factory SourceFactory(List<UriResolver> resolvers) = SourceFactoryImpl;

  /// Return the [DartSdk] associated with this [SourceFactory], or `null` if
  /// there is no such SDK.
  ///
  /// @return the [DartSdk] associated with this [SourceFactory], or `null` if
  ///         there is no such SDK
  DartSdk? get dartSdk;

  /// A table mapping package names to paths of directories containing the
  /// package (or `null` if there is no registered package URI resolver).
  Map<String, List<Folder>>? get packageMap;

  /// Return a source object representing the given absolute URI, or `null` if
  /// the URI is not a valid URI or if it is not an absolute URI.
  ///
  /// @param absoluteUri the absolute URI to be resolved
  /// @return a source object representing the absolute URI
  Source? forUri(String absoluteUri);

  /// Return a source object representing the given absolute URI, or `null` if
  /// the URI is not an absolute URI.
  ///
  /// @param absoluteUri the absolute URI to be resolved
  /// @return a source object representing the absolute URI
  Source? forUri2(Uri absoluteUri);

  /// Return the URI that should be used to reference the file at the absolute
  /// [path], or `null` if there is no valid way to reference the file.
  /// The file at that path is not required to exist.
  ///
  /// Throws an [ArgumentError] if the [path] is not a valid path.
  Uri? pathToUri(String path);

  /// Return a source representing the URI that results from resolving the given
  /// (possibly relative) [containedUri] against the URI associated with the
  /// [containingSource], whether or not the resulting source exists, or `null`
  /// if either the [containedUri] is invalid or if it cannot be resolved
  /// against the [containingSource]'s URI.
  Source? resolveUri(Source? containingSource, String? containedUri);
}

/// The enumeration `SourceKind` defines the different kinds of sources that are
/// known to the analysis engine.
class SourceKind implements Comparable<SourceKind> {
  /// A source containing HTML. The HTML might or might not contain Dart
  /// scripts.
  static const SourceKind HTML = SourceKind('HTML', 0);

  /// A Dart compilation unit that is not a part of another library. Libraries
  /// might or might not contain any directives, including a library directive.
  static const SourceKind LIBRARY = SourceKind('LIBRARY', 1);

  /// A Dart compilation unit that is part of another library. Parts contain a
  /// part-of directive.
  static const SourceKind PART = SourceKind('PART', 2);

  /// An unknown kind of source. Used both when it is not possible to identify
  /// the kind of a source and also when the kind of a source is not known
  /// without performing a computation and the client does not want to spend the
  /// time to identify the kind.
  static const SourceKind UNKNOWN = SourceKind('UNKNOWN', 3);

  static const List<SourceKind> values = [HTML, LIBRARY, PART, UNKNOWN];

  /// The name of this source kind.
  final String name;

  /// The ordinal value of the source kind.
  final int ordinal;

  const SourceKind(this.name, this.ordinal);

  @override
  int get hashCode => ordinal;

  @override
  int compareTo(SourceKind other) => ordinal - other.ordinal;

  @override
  String toString() => name;
}

/// The abstract class `UriResolver` defines the behavior of objects that are
/// used to resolve URI's for a source factory. Subclasses of this class are
/// expected to resolve a single scheme of absolute URI.
abstract class UriResolver {
  /// Return the absolute URI that should be used to reference the file at the
  /// absolute [path], or `null` if this resolver cannot reference this file.
  /// The file at that path is not required to exist.
  ///
  /// Throws an [ArgumentError] if the [path] is not a valid path.
  Uri? pathToUri(String path);

  /// Resolve the given absolute [uri]. Return a [Source] representing the file
  /// to which it was resolved, whether or not the resulting source exists, or
  /// `null` if it could not be resolved because the URI is invalid.
  Source? resolveAbsolute(Uri uri);
}
