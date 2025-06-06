// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' as io;

import 'package:expect/expect.dart';
import 'package:test/test.dart';

import 'package:observatory/service_io.dart';
import 'test_helper.dart';

const String content = 'some random content';
const String udpContent = 'aghfkjdb';
const String kClearSocketProfileRPC = 'ext.dart.io.clearSocketProfile';
const String kGetSocketProfileRPC = 'ext.dart.io.getSocketProfile';
const String kGetVersionRPC = 'ext.dart.io.getVersion';
const String kSocketProfilingEnabledRPC = 'ext.dart.io.socketProfilingEnabled';
const String localhost = '127.0.0.1';

List<Object> sockets = [];

Future<void> setup() async {}

Future<void> socketTest() async {
  // Socket
  var serverSocket = await io.ServerSocket.bind(localhost, 0);
  var socket = await io.Socket.connect(localhost, serverSocket.port);
  socket.write(content);
  await socket.flush();
  socket.destroy();

  // rawDatagram
  final doneCompleter = Completer<void>();
  var server = await io.RawDatagramSocket.bind(localhost, 0);
  server.listen((io.RawSocketEvent event) {
    if (event == io.RawSocketEvent.read) {
      server.receive()!;
      if (!doneCompleter.isCompleted) {
        doneCompleter.complete();
      }
    }
  });
  var client = await io.RawDatagramSocket.bind(localhost, 0);
  client.send(
      utf8.encode(udpContent), io.InternetAddress(localhost), server.port);
  client.send([1, 2, 3], io.InternetAddress(localhost), server.port);

  // Wait for datagram to arrive.
  await doneCompleter.future;
  // Post finish event
  postEvent('socketTest', {'socket': 'test'});
  // Workaround for dartbug.com/49111: make sure socket IDs are not reused.
  sockets.add(serverSocket);
  sockets.add(socket);
  sockets.add(server);
  sockets.add(client);
}

bool checkFinishEvent(ServiceEvent event) {
  expect(event.kind, equals(ServiceEvent.kExtension));
  if (event.extensionKind != 'socketTest') {
    return false;
  }
  expect(event.extensionData, isA<Map>());
  expect(event.extensionData!['socket'], equals('test'));
  return true;
}

var tests = <IsolateTest>[
  (Isolate isolate) async {
    await isolate.load();
    // Ensure all network profiling service extensions are registered.
    expect(isolate.extensionRPCs.length, greaterThanOrEqualTo(5));
    expect(isolate.extensionRPCs.contains(kClearSocketProfileRPC), isTrue);
    expect(isolate.extensionRPCs.contains(kGetVersionRPC), isTrue);
    expect(isolate.extensionRPCs.contains(kSocketProfilingEnabledRPC), isTrue);
  },

  // Test getSocketProfiler
  (Isolate isolate) async {
    await isolate.load();
    Library lib = isolate.rootLibrary;
    await lib.load();

    var response = await isolate.invokeRpcNoUpgrade(kGetSocketProfileRPC, {});
    expect(response['type'], 'SocketProfile');
    // returns an empty list in 'sockets'
    expect(response['sockets'].length, 0);
  },

  // Test getSocketProfile and socketProfilingEnabled
  (Isolate isolate) async {
    await isolate.load();
    Library lib = isolate.rootLibrary;
    await lib.load();

    var response = await isolate
        .invokeRpcNoUpgrade(kSocketProfilingEnabledRPC, {'enabled': true});
    expect(response['type'], 'SocketProfilingState');
    expect(response['enabled'], true);

    // Check whether socketTest has finished.
    Completer completer = Completer();
    var sub;
    sub = await isolate.vm.listenEventStream(Isolate.kExtensionStream,
        (ServiceEvent event) {
      if (checkFinishEvent(event)) {
        sub.cancel();
        completer.complete();
      }
    });

    await isolate.invokeRpc("invoke",
        {"targetId": lib.id, "selector": "socketTest", "argumentIds": []});
    await completer.future;

    response = await isolate.invokeRpcNoUpgrade(kGetSocketProfileRPC, {});
    expect(response['type'], 'SocketProfile');
    var stats = response['sockets'];
    // 1 tcp socket, 2 udp datagrams
    expect(stats.length, 3);
    stats.forEach((socket) {
      expect(socket['address'], contains(localhost));
      Expect.type<int>(socket['startTime']);
      Expect.type<String>(socket['id']);
      Expect.type<int>(socket['port']);
      if (socket['socketType'] == 'tcp') {
        expect(socket['writeBytes'], content.length);
        expect(socket.containsKey('lastWriteTime'), true);
        expect(socket['lastWriteTime'] > 0, true);
      } else {
        // 2 udp sockets, one of them is writing and the other is listening.
        expect(socket['socketType'], 'udp');
        if (socket['readBytes'] == 0) {
          // [1, 2, 3] was sent.
          expect(socket['writeBytes'], 3 + udpContent.length);
          expect(socket.containsKey('lastWriteTime'), true);
          expect(socket['lastWriteTime'] > 0, true);
          expect(socket.containsKey('lastReadTime'), false);
        } else {
          // [1, 2, 3] was sent.
          expect(socket['writeBytes'], 0);
          expect(socket['readBytes'], 3 + udpContent.length);
          expect(socket.containsKey('lastWriteTime'), false);
          expect(socket.containsKey('lastReadTime'), true);
          expect(socket['lastReadTime'] > 0, true);
        }
      }
    });

    // run 99 more times and check we have 100 sockets statistic.
    for (int i = 0; i < 99; i++) {
      completer = Completer();
      sub = await isolate.vm.listenEventStream(Isolate.kExtensionStream,
          (ServiceEvent event) {
        if (checkFinishEvent(event)) {
          sub.cancel();
          completer.complete();
        }
      });
      await isolate.invokeRpc("invoke",
          {"targetId": lib.id, "selector": "socketTest", "argumentIds": []});
      await completer.future;
    }

    response = await isolate.invokeRpcNoUpgrade(kGetSocketProfileRPC, {});
    expect(response['type'], 'SocketProfile');
    // 1 tcp socket, 2 udp datagrams
    expect(response['sockets'].length, 3 * 100);
  },

  // Test clearSocketProfiler
  (Isolate isolate) async {
    await isolate.load();
    Library lib = isolate.rootLibrary;
    await lib.load();

    var response = await isolate.invokeRpcNoUpgrade(kClearSocketProfileRPC, {});
    expect(response['type'], 'Success');

    response = await isolate.invokeRpcNoUpgrade(kGetSocketProfileRPC, {});
    expect(response['type'], 'SocketProfile');
    expect(response['sockets'].length, 0);
  },

  // Test socketProfilingEnabled
  (Isolate isolate) async {
    await isolate.load();
    Library lib = isolate.rootLibrary;
    await lib.load();

    var response = await isolate
        .invokeRpcNoUpgrade(kSocketProfilingEnabledRPC, {'enabled': true});
    expect(response['type'], 'SocketProfilingState');
    expect(response['enabled'], true);

    response = await isolate
        .invokeRpcNoUpgrade(kSocketProfilingEnabledRPC, {'enabled': false});
    expect(response['type'], 'SocketProfilingState');
    expect(response['enabled'], false);

    // Check whether socketTest has finished.
    Completer completer = Completer();
    var sub;
    sub = await isolate.vm.listenEventStream(Isolate.kExtensionStream,
        (ServiceEvent event) {
      if (checkFinishEvent(event)) {
        sub.cancel();
        completer.complete();
      }
    });

    await isolate.invokeRpc("invoke",
        {"targetId": lib.id, "selector": "socketTest", "argumentIds": []});
    await completer.future;

    response = await isolate.invokeRpcNoUpgrade(kGetSocketProfileRPC, {});
    expect(response['type'], 'SocketProfile');
    expect(response['sockets'].length, 0);
  }
];

main(args) async => runIsolateTests(args, tests, testeeBefore: setup);
