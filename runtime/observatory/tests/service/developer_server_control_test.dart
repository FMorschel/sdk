// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:developer';

import 'package:expect/expect.dart';

import 'package:observatory/service_io.dart' as S;
import 'test_helper.dart';

int? majorVersion;
int? minorVersion;
Uri? serverUri;
Uri? wsServerUri;

Future<Null> testeeBefore() async {
  print('testee before');
  // First grab the URL where the VM service is listening and the
  // service protocol version numbers. We expect the URL to be null as
  // the server has not been started yet.
  ServiceProtocolInfo info = await Service.getInfo();
  majorVersion = info.majorVersion;
  minorVersion = info.minorVersion;
  Expect.isNull(info.serverUri);
  Expect.isNull(info.serverWebSocketUri);
  {
    // Now, start the web server and store the URI which is expected to be
    // non NULL in the top level variable.
    ServiceProtocolInfo info =
        await Service.controlWebServer(enable: true, silenceOutput: true);
    Expect.equals(info.majorVersion, majorVersion);
    Expect.equals(info.minorVersion, minorVersion);
    Expect.isNotNull(info.serverUri);
    Expect.isNotNull(info.serverWebSocketUri);
    serverUri = info.serverUri;
    wsServerUri = info.serverWebSocketUri;
    Expect.equals(wsServerUri!.scheme, 'ws');
    Expect.isTrue(wsServerUri!.path.endsWith('ws'));
  }
  {
    // Now try starting the web server again, this should just return the
    // existing state without any change (port number does not change).
    ServiceProtocolInfo info = await Service.controlWebServer(enable: true);
    Expect.equals(info.majorVersion, majorVersion);
    Expect.equals(info.minorVersion, minorVersion);
    Expect.equals(info.serverUri, serverUri);
    Expect.equals(info.serverWebSocketUri, wsServerUri);
  }
  {
    // Try turning off the web server, this should turn off the server and
    // the Uri returned should be null.
    ServiceProtocolInfo info = await Service.controlWebServer(enable: false);
    Expect.equals(info.majorVersion, majorVersion);
    Expect.equals(info.minorVersion, minorVersion);
    Expect.isNull(info.serverUri);
    Expect.isNull(info.serverWebSocketUri);
  }
  {
    // Try turning off the web server again, this should be a nop
    // and the Uri returned should be null.
    ServiceProtocolInfo info = await Service.controlWebServer(enable: false);
    Expect.equals(info.majorVersion, majorVersion);
    Expect.equals(info.minorVersion, minorVersion);
    Expect.isNull(info.serverUri);
    Expect.isNull(info.serverWebSocketUri);
  }
  {
    // Start the web server again for the test below.
    ServiceProtocolInfo info = await Service.controlWebServer(enable: true);
    majorVersion = info.majorVersion;
    minorVersion = info.minorVersion;
    Expect.equals(info.majorVersion, majorVersion);
    Expect.equals(info.minorVersion, minorVersion);
    Expect.isNotNull(info.serverUri);
    Expect.isNotNull(info.serverWebSocketUri);
  }
}

var tests = <IsolateTest>[
  (S.Isolate isolate) async {
    await isolate.reload();
    // Just getting here means that the testee enabled the service protocol
    // web server.
    Expect.equals(true, true);
  }
];

main(args) => runIsolateTests(args, tests,
    testeeBefore: testeeBefore,
    // the testee is responsible for starting the
    // web server.
    testeeControlsServer: true);
