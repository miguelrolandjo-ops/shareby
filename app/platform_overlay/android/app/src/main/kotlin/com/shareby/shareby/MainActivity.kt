package com.shareby.shareby

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Dart side: lib/data/share_intake.dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shareby/share_intake")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "drainPending" -> result.success(ShareInbox.drain(applicationContext))
                    else -> result.notImplemented()
                }
            }
    }
}
