// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:web/web.dart';

import 'package:observatory/src/elements/helpers/custom_element.dart';
import 'package:observatory/src/elements/helpers/rendering_scheduler.dart';
import 'package:observatory/src/elements/helpers/uris.dart';

import 'package:observatory/models.dart' as M
    show IsolateRef, SubtypeTestCacheRef;

class SubtypeTestCacheRefElement extends CustomElement implements Renderable {
  late RenderingScheduler<SubtypeTestCacheRefElement> _r;

  Stream<RenderedEvent<SubtypeTestCacheRefElement>> get onRendered =>
      _r.onRendered;

  late M.IsolateRef _isolate;
  late M.SubtypeTestCacheRef _subtypeTestCache;

  M.IsolateRef get isolate => _isolate;
  M.SubtypeTestCacheRef get subtypeTestCache => _subtypeTestCache;

  factory SubtypeTestCacheRefElement(
      M.IsolateRef isolate, M.SubtypeTestCacheRef subtypeTestCache,
      {RenderingQueue? queue}) {
    SubtypeTestCacheRefElement e = new SubtypeTestCacheRefElement.created();
    e._r = new RenderingScheduler<SubtypeTestCacheRefElement>(e, queue: queue);
    e._isolate = isolate;
    e._subtypeTestCache = subtypeTestCache;
    return e;
  }

  SubtypeTestCacheRefElement.created() : super.created('subtypetestcache-ref');

  @override
  void attached() {
    super.attached();
    _r.enable();
  }

  @override
  void detached() {
    super.detached();
    _r.disable(notify: true);
    removeChildren();
  }

  void render() {
    children = <HTMLElement>[
      new HTMLAnchorElement()
        ..href = Uris.inspect(_isolate, object: _subtypeTestCache)
        ..appendChild(
          new HTMLSpanElement()
            ..className = 'emphasize'
            ..textContent = 'SubtypeTestCache',
        )
    ];
  }
}
