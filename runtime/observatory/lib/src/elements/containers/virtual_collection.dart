// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:web/web.dart';

import 'package:observatory/src/elements/containers/search_bar.dart';
import 'package:observatory/src/elements/helpers/custom_element.dart';
import 'package:observatory/src/elements/helpers/element_utils.dart';
import 'package:observatory/src/elements/helpers/rendering_scheduler.dart';

typedef HTMLElement VirtualCollectionCreateCallback();
typedef List<HTMLElement> VirtualCollectionHeaderCallback();
typedef void VirtualCollectionUpdateCallback(
    HTMLElement el, dynamic item, int index);
typedef bool VirtualCollectionSearchCallback(Pattern pattern, dynamic item);

class VirtualCollectionElement extends CustomElement implements Renderable {
  late RenderingScheduler<VirtualCollectionElement> _r;

  Stream<RenderedEvent<VirtualCollectionElement>> get onRendered =>
      _r.onRendered;

  late VirtualCollectionCreateCallback _create;
  VirtualCollectionHeaderCallback? _createHeader;
  late VirtualCollectionUpdateCallback _update;
  VirtualCollectionSearchCallback? _search;
  double? _itemHeight;
  int? _top;
  double? _height;
  List? _items;
  late StreamSubscription _onScrollSubscription;
  late StreamSubscription _onResizeSubscription;

  List? get items => _items;

  set items(Iterable? value) {
    _items = new List.unmodifiable(value!);
    _top = null;
    _searcher?.update();
    _r.dirty();
  }

  factory VirtualCollectionElement(VirtualCollectionCreateCallback create,
      VirtualCollectionUpdateCallback update,
      {Iterable items = const [],
      VirtualCollectionHeaderCallback? createHeader,
      VirtualCollectionSearchCallback? search,
      RenderingQueue? queue}) {
    VirtualCollectionElement e = new VirtualCollectionElement.created();
    e._r = new RenderingScheduler<VirtualCollectionElement>(e, queue: queue);
    e._create = create;
    e._createHeader = createHeader;
    e._update = update;
    e._search = search;
    e._items = new List.unmodifiable(items);
    return e;
  }

  VirtualCollectionElement.created() : super.created('virtual-collection');

  @override
  attached() {
    super.attached();
    _r.enable();
    _top = null;
    _itemHeight = null;
    _onScrollSubscription = _viewport.onScroll.listen(_onScroll);
    _onResizeSubscription = _viewport.onResize.listen(_onResize);
  }

  @override
  detached() {
    super.detached();
    _r.disable(notify: true);
    children = const [];
    _onScrollSubscription.cancel();
    _onResizeSubscription.cancel();
  }

  HTMLDivElement? _header;
  SearchBarElement? _searcher;
  final HTMLDivElement _viewport = new HTMLDivElement()
    ..className = 'viewport container';
  final HTMLDivElement _spacer = new HTMLDivElement()..className = 'spacer';
  final HTMLDivElement _buffer = new HTMLDivElement()..className = 'buffer';

  static int safeFloor(double x) {
    if (x.isNaN) return 0;
    return x.floor();
  }

  static int safeCeil(double x) {
    if (x.isNaN) return 0;
    return x.ceil();
  }

  dynamic getItemFromElement(HTMLElement element) {
    int el_index = _buffer.children.length;
    while (el_index >= 0 && _buffer.children.item(el_index) != element) {
      el_index--;
    }
    if (el_index < 0) {
      return null;
    }
    final item_index = _top! +
        el_index -
        safeFloor(_buffer.children.length * _inverse_preload);
    if (0 <= item_index && item_index < items!.length) {
      return _items![item_index];
    }
    return null;
  }

  /// The preloaded element before and after the visible area are:
  /// 1/preload_size of the number of items in the visible area.
  static const int _preload = 2;

  /// L = length of all the elements loaded
  /// l = length of the visible area
  ///
  /// L = l + 2 * l / _preload
  /// l = L * _preload / (_preload + 2)
  ///
  /// tail = l / _preload = L * 1 / (_preload + 2) = L * _inverse_preload
  static const double _inverse_preload = 1 / (_preload + 2);

  var _takeIntoView;

  void takeIntoView(item) {
    _takeIntoView = item;
    _r.dirty();
  }

  void render() {
    if (children.isEmpty) {
      final newChildren = <HTMLElement>[
        _viewport
          ..appendChild(
            _spacer..appendChild(_buffer..appendChild(_create())),
          )
      ];
      if (_search != null) {
        _searcher =
            _searcher ?? new SearchBarElement(_doSearch, queue: _r.queue)
              ..onSearchResultSelected.listen((e) {
                takeIntoView(e.item);
              });
        newChildren.insert(0, _searcher!.element);
      }
      if (_createHeader != null) {
        _header = new HTMLDivElement()
          ..className = 'header container'
          ..appendChildren(_createHeader!());
        newChildren.insert(0, _header!);
        final rect = _header!.getBoundingClientRect();
        _header!.className += 'attached';
        _viewport.style.top = '${rect.height}px';

        double width = 0.0;
        for (int i = 0; i < _header!.children.length; i++) {
          width = math.max(
              width, _header!.children.item(i)!.getBoundingClientRect().width);
        }
        _buffer.style.minWidth = '${width}px';
      }
      children = newChildren;

      _itemHeight = (_buffer.firstElementChild! as HTMLElement)
          .getBoundingClientRect()
          .height;
      _height = getBoundingClientRect().height;
    }

    if (_takeIntoView != null) {
      final index = items!.indexOf(_takeIntoView);
      if (index >= 0) {
        final minScrollTop = _itemHeight! * (index + 1) - _height!;
        final maxScrollTop = _itemHeight! * index;
        _viewport.scrollTop =
            safeFloor((maxScrollTop - minScrollTop) / 2 + minScrollTop);
      }
      _takeIntoView = null;
    }

    final top = safeFloor(_viewport.scrollTop / _itemHeight!);

    _spacer.style.height = '${_itemHeight! * (_items!.length)}px';
    final tail_length = safeCeil(_height! / _itemHeight! / _preload);
    final length = tail_length * 2 + tail_length * _preload;

    if (_buffer.children.length < length) {
      while (_buffer.children.length != length) {
        var e = _create();
        e..style.display = 'hidden';
        _buffer.appendChild(e);
      }
      _top = null; // force update;
    }

    if ((_top == null) || ((top - _top!).abs() >= tail_length)) {
      _buffer.style.top = '${_itemHeight! * (top - tail_length)}px';
      int i = top - tail_length;
      for (var j = 0; j < _buffer.children.length; j++) {
        final e = _buffer.children.item(j) as HTMLElement;
        if (0 <= i && i < _items!.length) {
          e.style.display = '';
          _update(e, _items![i], i);
        } else {
          e.style.display = 'hidden';
        }
        i++;
      }
      _top = top;
    }

    if (_searcher != null) {
      final current = _searcher!.current;
      int i = _top! - tail_length;
      for (var j = 0; j < _buffer.children.length; j++) {
        final e = _buffer.children.item(j) as HTMLElement;
        if (0 <= i && i < _items!.length) {
          if (_items![i] == current) {
            e.className += ' marked';
          } else {
            e.className.replaceAll(' marked', '');
          }
        }
        i++;
      }
    }
    _updateHeader();
  }

  void _updateHeader() {
    if (_header != null) {
      _header!.style.left = '${-_viewport.scrollLeft}px';
      final width = _buffer.getBoundingClientRect().width;
      (_header!.lastChild! as HTMLElement).style.width = '${width}px';
    }
  }

  void _onScroll(_) {
    _r.dirty();
    // We anticipate the header in advance to avoid flickering
    _updateHeader();
  }

  void _onResize(_) {
    final newHeight = getBoundingClientRect().height;
    if (newHeight > _height!) {
      _height = newHeight;
      _r.dirty();
    } else {
      // Even if we are not updating the structure the computed size is going to
      // change
      _updateHeader();
    }
  }

  Iterable<dynamic> _doSearch(Pattern search) {
    return _items!.where((item) => _search!(search, item));
  }
}
