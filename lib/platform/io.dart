// Keep native file semantics; browsers persist the same records in IndexedDB.
export 'dart:io' if (dart.library.js_interop) 'browser_io.dart';
