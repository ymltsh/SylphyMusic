import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// media_kit 1.2.6 stores debug pointers under a PID-only filename. A Windows
/// test worker can reuse a PID from an exited worker, but not its address space.
/// Run before testMain (and therefore before MediaKit.ensureInitialized), and
/// touch only this worker's file. Release builds do not use this debug holder.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (!Platform.isWindows) {
    await testMain();
    return;
  }
  final reference = File(
    p.join(
      Directory.systemTemp.path,
      'com.alexmercerind.media_kit.NativeReferenceHolder.$pid',
    ),
  );
  Future<void> removeReference() async {
    if (await reference.exists()) await reference.delete();
  }

  await removeReference();
  try {
    await testMain();
  } finally {
    await removeReference();
  }
}
