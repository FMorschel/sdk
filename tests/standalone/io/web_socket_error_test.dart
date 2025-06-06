// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// VMOptions=
// VMOptions=--short_socket_read
// VMOptions=--short_socket_write
// VMOptions=--short_socket_read --short_socket_write
// OtherResources=certificates/server_chain.pem
// OtherResources=certificates/server_key.pem
// OtherResources=certificates/trusted_certs.pem

import "dart:async";
import "dart:convert";
import "dart:io";
// ignore: IMPORT_INTERNAL_LIBRARY
import "dart:_http" show TestingClass$_SHA1;

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

typedef _SHA1 = TestingClass$_SHA1;

const String webSocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const String CERT_NAME = 'localhost_cert';
const String HOST_NAME = 'localhost';

String localFile(path) => Platform.script.resolve(path).toFilePath();

SecurityContext serverContext = new SecurityContext()
  ..useCertificateChain(localFile('certificates/server_chain.pem'))
  ..usePrivateKey(
    localFile('certificates/server_key.pem'),
    password: 'dartdart',
  );

SecurityContext clientContext = new SecurityContext()
  ..setTrustedCertificates(localFile('certificates/trusted_certs.pem'));

/**
 * A SecurityConfiguration lets us run the tests over HTTP or HTTPS.
 */
class SecurityConfiguration {
  final bool secure;

  SecurityConfiguration({required bool this.secure});

  Future<HttpServer> createServer({int backlog = 0}) => secure
      ? HttpServer.bindSecure(HOST_NAME, 0, serverContext, backlog: backlog)
      : HttpServer.bind(HOST_NAME, 0, backlog: backlog);

  Future<WebSocket> createClient(int port) => WebSocket.connect(
    '${secure ? "wss" : "ws"}://$HOST_NAME:$port/',
    customClient: secure ? HttpClient(context: clientContext) : null,
  );

  void testForceCloseServerEnd(int totalConnections) {
    createServer().then((server) {
      server.listen((request) {
        var response = request.response;
        response.statusCode = HttpStatus.switchingProtocols;
        response.headers.set(HttpHeaders.connectionHeader, "upgrade");
        response.headers.set(HttpHeaders.upgradeHeader, "websocket");
        String? key = request.headers.value("Sec-WebSocket-Key");
        _SHA1 sha1 = new _SHA1();
        sha1.add("$key$webSocketGUID".codeUnits);
        String accept = base64Encode(sha1.close());
        response.headers.add("Sec-WebSocket-Accept", accept);
        response.headers.contentLength = 0;
        response.detachSocket().then((socket) {
          socket.destroy();
        });
      });

      int closeCount = 0;
      for (int i = 0; i < totalConnections; i++) {
        createClient(server.port).then((webSocket) {
          webSocket.add("Hello, world!");
          webSocket.listen(
            (message) {
              Expect.fail("unexpected message");
            },
            onDone: () {
              closeCount++;
              if (closeCount == totalConnections) {
                server.close();
              }
            },
          );
        });
      }
    });
  }

  void runTests() {
    testForceCloseServerEnd(10);
  }
}

main() {
  asyncStart();
  new SecurityConfiguration(secure: false).runTests();
  new SecurityConfiguration(secure: true).runTests();
  asyncEnd();
}
