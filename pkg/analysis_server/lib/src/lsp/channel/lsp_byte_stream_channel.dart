// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analysis_server/lsp_protocol/protocol.dart';
import 'package:analysis_server/src/lsp/channel/lsp_channel.dart';
import 'package:analysis_server/src/lsp/lsp_packet_transformer.dart';
import 'package:analyzer/instrumentation/instrumentation.dart';
import 'package:language_server_protocol/json_parsing.dart';

/// Instances of the class [LspByteStreamServerChannel] implement an
/// [LspServerCommunicationChannel] that uses a stream and a sink (typically,
/// standard input and standard output) to communicate with clients.
class LspByteStreamServerChannel implements LspServerCommunicationChannel {
  final Stream<void> _input;

  final IOSink _output;

  final InstrumentationService _instrumentationService;

  /// Completer that will be signalled when the input stream is closed.
  final Completer<void> _closed = Completer();

  /// True if [close] has been called.
  bool _closeRequested = false;

  LspByteStreamServerChannel(
    this._input,
    this._output,
    this._instrumentationService,
  );

  /// Future that will be completed when the input stream is closed.
  @override
  Future<void> get closed {
    return _closed.future;
  }

  @override
  void close() {
    if (!_closeRequested) {
      _closeRequested = true;
      assert(!_closed.isCompleted);
      _closed.complete();
    }
  }

  @override
  StreamSubscription<void> listen(
    void Function(Message message) onMessage, {
    Function? onError,
    void Function()? onDone,
  }) {
    return _input
        .transform(LspPacketTransformer())
        .listen(
          (String data) => _readMessage(data, onMessage),
          onError: onError,
          onDone: () {
            close();
            if (onDone != null) {
              onDone();
            }
          },
        );
  }

  @override
  void sendNotification(NotificationMessage notification) =>
      _sendLsp(notification.toJson());

  @override
  void sendRequest(RequestMessage request) => _sendLsp(request.toJson());

  @override
  void sendResponse(ResponseMessage response) => _sendLsp(response.toJson());

  /// Read a request from the given [data] and use the given function to handle
  /// the message.
  void _readMessage(String data, void Function(Message request) onMessage) {
    // Ignore any further requests after the communication channel is closed.
    if (_closed.isCompleted) {
      return;
    }
    _instrumentationService.logRequest(data);
    var json = jsonDecode(data) as Map<String, Object?>;
    if (RequestMessage.canParse(json, nullLspJsonReporter)) {
      onMessage(RequestMessage.fromJson(json));
    } else if (NotificationMessage.canParse(json, nullLspJsonReporter)) {
      onMessage(NotificationMessage.fromJson(json));
    } else if (ResponseMessage.canParse(json, nullLspJsonReporter)) {
      onMessage(ResponseMessage.fromJson(json));
    } else {
      _sendParseError();
    }
  }

  /// Sends a message prefixed with the required LSP headers.
  void _sendLsp(Map<String, Object?> json) {
    // Don't send any further responses after the communication channel is
    // closed.
    if (_closeRequested) {
      return;
    }
    var jsonEncodedBody = jsonEncode(json);
    var utf8EncodedBody = utf8.encode(jsonEncodedBody);
    var header =
        'Content-Length: ${utf8EncodedBody.length}\r\n'
        'Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n';
    var asciiEncodedHeader = ascii.encode(header);

    // Header is always ascii, body is always utf8!
    _write(asciiEncodedHeader);
    _write(utf8EncodedBody);

    _instrumentationService.logResponse(jsonEncodedBody);
  }

  void _sendParseError() {
    var error = ResponseMessage(
      error: ResponseError(
        code: ErrorCodes.ParseError,
        message: 'Unable to parse message',
      ),
      jsonrpc: jsonRpcVersion,
    );
    sendResponse(error);
  }

  /// Send [bytes] to [_output].
  void _write(List<int> bytes) {
    runZonedGuarded(() => _output.add(bytes), (e, s) => close());
  }
}
