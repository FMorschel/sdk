// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library heap_map_element;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'package:observatory/models.dart' as M;
import 'package:observatory/service.dart' as S;
import 'package:observatory/src/elements/helpers/custom_element.dart';
import 'package:observatory/src/elements/helpers/element_utils.dart';
import 'package:observatory/src/elements/helpers/nav_bar.dart';
import 'package:observatory/src/elements/helpers/nav_menu.dart';
import 'package:observatory/src/elements/helpers/rendering_scheduler.dart';
import 'package:observatory/src/elements/nav/isolate_menu.dart';
import 'package:observatory/src/elements/nav/notify.dart';
import 'package:observatory/src/elements/nav/refresh.dart';
import 'package:observatory/src/elements/nav/top_menu.dart';
import 'package:observatory/src/elements/nav/vm_menu.dart';

class HeapMapElement extends CustomElement implements Renderable {
  late RenderingScheduler<HeapMapElement> _r;

  Stream<RenderedEvent<HeapMapElement>> get onRendered => _r.onRendered;

  late M.VM _vm;
  late M.IsolateRef _isolate;
  late M.EventRepository _events;
  late M.NotificationRepository _notifications;
  M.VMRef get vm => _vm;
  M.IsolateRef get isolate => _isolate;
  M.NotificationRepository get notifications => _notifications;

  factory HeapMapElement(M.VM vm, M.IsolateRef isolate,
      M.EventRepository events, M.NotificationRepository notifications,
      {RenderingQueue? queue}) {
    HeapMapElement e = new HeapMapElement.created();
    e._r = new RenderingScheduler<HeapMapElement>(e, queue: queue);
    e._vm = vm;
    e._isolate = isolate;
    e._events = events;
    e._notifications = notifications;
    return e;
  }

  HeapMapElement.created() : super.created('heap-map');

  @override
  attached() {
    super.attached();
    _r.enable();
    _refresh();
  }

  @override
  detached() {
    super.detached();
    _r.disable(notify: true);
    removeChildren();
  }

  HTMLCanvasElement? _canvas;
  ImageData? _fragmentationData;
  int? _pageHeight;
  final _classIdToColor = {};
  final _colorToClassId = {};
  final _classIdToName = {};

  static final _freeColor = [255, 255, 255, 255];
  static final _pageSeparationColor = [0, 0, 0, 255];
  static const _PAGE_SEPARATION_HEIGHT = 4;
  // Many browsers will not display a very tall canvas.
  // TODO(koda): Improve interface for huge heaps.
  static const _MAX_CANVAS_HEIGHT = 6000;

  String _status = 'Loading';
  S.ServiceMap? _fragmentation;

  void render() {
    if (_canvas == null) {
      _canvas = new HTMLCanvasElement()
        ..width = 1
        ..height = 1
        ..onMouseMove.listen(_handleMouseMove);
    }

    // Set hover text to describe the object under the cursor.
    _canvas!.title = _status;

    setChildren(<HTMLElement>[
      navBar(<HTMLElement>[
        new NavTopMenuElement(queue: _r.queue).element,
        new NavVMMenuElement(_vm, _events, queue: _r.queue).element,
        new NavIsolateMenuElement(_isolate, _events, queue: _r.queue).element,
        navMenu('heap map'),
        (new NavRefreshElement(label: 'Mark-Compact', queue: _r.queue)
              ..onRefresh.listen((_) => _refresh(gc: "mark-compact")))
            .element,
        (new NavRefreshElement(label: 'Mark-Sweep', queue: _r.queue)
              ..onRefresh.listen((_) => _refresh(gc: "mark-sweep")))
            .element,
        (new NavRefreshElement(label: 'Scavenge', queue: _r.queue)
              ..onRefresh.listen((_) => _refresh(gc: "scavenge")))
            .element,
        (new NavRefreshElement(queue: _r.queue)
              ..onRefresh.listen((_) => _refresh()))
            .element,
        (new NavNotifyElement(_notifications, queue: _r.queue)).element
      ]),
      new HTMLDivElement()
        ..className = 'content-centered-big'
        ..appendChildren(<HTMLElement>[
          new HTMLHeadingElement.h2()..textContent = _status,
          new HTMLHRElement(),
        ]),
      new HTMLDivElement()
        ..className = 'flex-row'
        ..appendChild(_canvas!)
    ]);
  }

  // Encode color as single integer, to enable using it as a map key.
  int _packColor(Iterable<int> color) {
    int packed = 0;
    for (var component in color) {
      packed = packed * 256 + component;
    }
    return packed;
  }

  void _addClass(int classId, String name, Iterable<int> color) {
    _classIdToName[classId] = name.split('@')[0];
    _classIdToColor[classId] = color;
    _colorToClassId[_packColor(color)] = classId;
  }

  void _updateClassList(classList, int freeClassId) {
    for (var member in classList['classes']) {
      if (member is! S.Class) {
        // TODO(turnidge): The printing for some of these non-class
        // members is broken.  Fix this:
        //
        // Logger.root.info('$member');
        print('Ignoring non-class in class list');
        continue;
      }
      var classId = int.parse(member.id!.split('/').last);
      var color = _classIdToRGBA(classId);
      _addClass(classId, member.name!, color);
    }
    _addClass(freeClassId, 'Free', _freeColor);
    _addClass(0, '', _pageSeparationColor);
  }

  Iterable<int> _classIdToRGBA(int classId) {
    // TODO(koda): Pick random hue, but fixed saturation and value.
    var rng = new Random(classId);
    return [rng.nextInt(128), rng.nextInt(128), rng.nextInt(128), 255];
  }

  String _classNameAt(Point<num> point) {
    var color = new PixelReference(_fragmentationData!, point).color;
    return _classIdToName[_colorToClassId[_packColor(color)]];
  }

  ObjectInfo? _objectAt(Point<num> point) {
    if (_fragmentation == null || _canvas == null) {
      return null;
    }
    var pagePixels = _pageHeight! * _fragmentationData!.width;
    var index = new PixelReference(_fragmentationData!, point).index;
    var pageIndex = index ~/ pagePixels;
    num pageOffset = index % pagePixels;
    var pages = _fragmentation!['pages'];
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return null;
    }
    // Scan the page to find start and size.
    var page = pages[pageIndex];
    var objects = page['objects'];
    var offset = 0;
    var size = 0;
    for (var i = 0; i < objects.length; i += 2) {
      size = objects[i];
      offset += size;
      if (offset > pageOffset) {
        pageOffset = offset - size;
        break;
      }
    }
    return new ObjectInfo(
        int.parse(page['objectStart']) +
            pageOffset * _fragmentation!['unitSizeBytes'],
        size * _fragmentation!['unitSizeBytes']);
  }

  void _handleMouseMove(MouseEvent event) {
    var info = _objectAt(Point(event.offsetX, event.offsetY));
    if (info == null) {
      _status = '';
      _r.dirty();
      return;
    }
    var addressString = '${info.size}B @ 0x${info.address.toRadixString(16)}';
    var className = _classNameAt(Point(event.offsetX, event.offsetY));
    _status = (className == '') ? '-' : '$className $addressString';
    _r.dirty();
  }

  void _updateFragmentationData() {
    if (_fragmentation == null || _canvas == null) {
      return;
    }
    _updateClassList(
        _fragmentation!['classList'], _fragmentation!['freeClassId']);
    final pages = _fragmentation!['pages'];
    final int width = max(_canvas!.parentElement!.clientWidth, 1);
    _pageHeight = _PAGE_SEPARATION_HEIGHT +
        (_fragmentation!['pageSizeBytes'] as int) ~/
            (_fragmentation!['unitSizeBytes'] as int) ~/
            width;
    final height = min(_pageHeight! * pages.length, _MAX_CANVAS_HEIGHT) as int;
    _fragmentationData =
        _canvas!.context2D.createImageData(width as dynamic, height);
    _canvas!.width = _fragmentationData!.width;
    _canvas!.height = _fragmentationData!.height;
    _renderPages(0);
  }

  // Renders and draws asynchronously, one page at a time to avoid
  // blocking the UI.
  void _renderPages(int startPage) {
    var pages = _fragmentation!['pages'];
    _status = 'Loaded $startPage of ${pages.length} pages';
    _r.dirty();
    var startY = (startPage * _pageHeight!).round();
    var endY = startY + _pageHeight!.round();
    if (startPage >= pages.length || endY > _fragmentationData!.height) {
      return;
    }
    var pixel = new PixelReference(_fragmentationData!, new Point(0, startY));
    var objects = pages[startPage]['objects'];
    for (var i = 0; i < objects.length; i += 2) {
      var count = objects[i];
      var classId = objects[i + 1];
      var color = _classIdToColor[classId];
      while (count-- > 0) {
        pixel.color = color;
        pixel = pixel.next();
      }
    }
    while (pixel.point.y < endY) {
      pixel.color = _pageSeparationColor;
      pixel = pixel.next();
    }
    _canvas!.context2D.putImageData(
        _fragmentationData!, 0, 0, 0, startY, _fragmentationData!.width, endY);
    // Continue with the next page, asynchronously.
    new Future(() {
      _renderPages(startPage + 1);
    });
  }

  Future _refresh({String? gc}) {
    final isolate = _isolate as S.Isolate;
    var params = {};
    if (gc != null) {
      params['gc'] = gc;
    }
    return isolate.invokeRpc('_getHeapMap', params).then((serviceObject) {
      S.ServiceMap response = serviceObject as S.ServiceMap;
      assert(response['type'] == 'HeapMap');
      _fragmentation = response;
      _updateFragmentationData();
    });
  }
}

// A reference to a particular pixel of ImageData.
class PixelReference {
  final ImageData _data;
  final int _dataIndex;
  static const NUM_COLOR_COMPONENTS = 4;

  PixelReference(ImageData data, Point<num> point)
      : _data = data,
        _dataIndex =
            (point.y * data.width + point.x) * NUM_COLOR_COMPONENTS as int;

  PixelReference._fromDataIndex(this._data, this._dataIndex);

  Point<num> get point => new Point(index % _data.width, index ~/ _data.width);

  void set color(Iterable<int> color) {
    (_data.data as Uint8ClampedList)
        .setRange(_dataIndex, _dataIndex + NUM_COLOR_COMPONENTS, color);
  }

  Iterable<int> get color => (_data.data as Uint8ClampedList)
      .getRange(_dataIndex, _dataIndex + NUM_COLOR_COMPONENTS);

  // Returns the next pixel in row-major order.
  PixelReference next() => new PixelReference._fromDataIndex(
      _data, _dataIndex + NUM_COLOR_COMPONENTS);

  // The row-major index of this pixel.
  int get index => _dataIndex ~/ NUM_COLOR_COMPONENTS;
}

class ObjectInfo {
  final address;
  final size;
  ObjectInfo(this.address, this.size);
}
