# bean_budget

A Flutter desktop app (Windows) for managing receipts and budgets, with OCR powered by Tesseract via the [flusseract](https://pub.dev/packages/flusseract) plugin.

## flusseract Windows patches

`flusseract 0.1.3` does not build on Windows out of the box. The following manual patches are required to the pub cache copy of the package at `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\flusseract-0.1.3\src\`.

### 1. `flusseract.cpp` — guard `unistd.h`

`unistd.h` is a Unix-only header. It is included but nothing from it is used on Windows.

```diff
 #include <stdio.h>
-#include <unistd.h>
+#ifndef _WIN32
+#include <unistd.h>
+#endif
```

### 2. `common.h` — add Windows POSIX aliases

The `BEGIN_STREAM_CAPTURE` / `END_STREAM_CAPTURE` macros use POSIX APIs (`dup`, `dup2`, `pipe`, `close`, `read`, `ssize_t`). Windows provides these under underscore-prefixed names in `<io.h>` and `<fcntl.h>`.

```diff
 #if _WIN32
 #include <windows.h>
+#include <io.h>
+#include <fcntl.h>
+#define dup _dup
+#define dup2 _dup2
+#define close _close
+#define read _read
+#define pipe(fds) _pipe(fds, 4096, O_BINARY)
+typedef int ssize_t;
 #else
 #include <pthread.h>
 #include <unistd.h>
 #endif
```

### 3. `windows/CMakeLists.txt` — bundle vcpkg runtime DLLs

The flusseract plugin links against tesseract and leptonica from vcpkg, but those DLLs are not automatically copied to the output directory. The following install rule was added to `windows/CMakeLists.txt`:

```cmake
set(VCPKG_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../vcpkg/installed/x64-windows/bin")
file(GLOB VCPKG_DLLS "${VCPKG_BIN}/*.dll")
install(FILES ${VCPKG_DLLS}
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
```

### 4. `lib/tessdata.dart` — replace deprecated `AssetManifest.json` with current API

Newer Flutter no longer generates `AssetManifest.json`. The `loadString('AssetManifest.json')` call throws at runtime. Replace with `AssetManifest.loadFromAssetBundle()` and use `firstOrNull` instead of `firstWhere` (which throws when no element matches):

```diff
-import 'dart:convert';
-
-      final assetManifest = jsonDecode(
-        await assetBundle!.loadString('AssetManifest.json'),
-      );
-      final tessConfig = assetManifest.keys.firstWhere(
-        (String key) => key.toLowerCase().startsWith('assets/tessconfig'),
-      );
-      ...
-      final tessDataFiles = assetManifest.keys.where(
-        (String key) => key.toLowerCase().startsWith('assets/tessdata/'),
-      );
+      final manifest = await AssetManifest.loadFromAssetBundle(assetBundle!);
+      final allAssets = manifest.listAssets();
+      final tessConfig = allAssets.where(
+        (String key) => key.toLowerCase().startsWith('assets/tessconfig'),
+      ).firstOrNull;
+      ...
+      final tessDataFiles = allAssets.where(
+        (String key) => key.toLowerCase().startsWith('assets/tessdata/'),
+      );
```

### 5. `assets/tessconfig/` — placeholder to avoid empty `tessConfig` path

A placeholder file at `assets/tessconfig/quiet` (declared in `pubspec.yaml`) ensures `_tessConfigPath` is set after the fix above, avoiding a null path being passed to Tesseract init.
