// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Testing file input stream, VM-only, standalone test.

/// Tests the Dart scripts can be read from named pipes, e.g.
/// `echo 'main(){print("hello, world");}' | dart /dev/fd/0`

import "dart:convert";
import "dart:io";

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

main() async {
  asyncStart();
  // Reading a script from a named pipe is only supported on Linux.
  // TODO(https://dartbug.com/26237): Enable support for additional platforms.
  if (!Platform.isLinux) {
    print("This test is only supported on Linux.");
    asyncEnd();
    return;
  }

  final String script = 'main() { print("Hello, World!"); }';
  final String stdinPipePath = '/dev/fd/0';

  // If there's no file system access to the pipe, then we can't do a meaningful
  // test.
  if (!await (new File(stdinPipePath).exists())) {
    print("Couldn't find $stdinPipePath.");
    asyncEnd();
    return;
  }

  StringBuffer output = new StringBuffer();
  Process process = await Process.start(
    Platform.executable,
    []
      ..addAll(Platform.executableArguments)
      ..add('--sound-null-safety')
      ..add('--verbosity=warning')
      ..add(stdinPipePath),
  );
  bool stdinWriteFailed = false;
  process.stdout.transform(utf8.decoder).listen(output.write);
  process.stderr.transform(utf8.decoder).listen((data) {
    if (!stdinWriteFailed) {
      Expect.fail(data);
      process.kill();
    }
  });
  process.stdin.done.catchError((e) {
    // If the write to stdin fails, then give up. We can't test the thing we
    // wanted to test.
    stdinWriteFailed = true;
    process.kill();
  });
  process.stdin.writeln(script);
  await process.stdin.flush();
  await process.stdin.close();

  int status = await process.exitCode;
  if (!stdinWriteFailed) {
    Expect.equals(0, status);
    Expect.equals("Hello, World!\n", output.toString());
  }
  asyncEnd();
}
