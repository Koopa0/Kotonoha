package com.koopa.kotonoha

import android.content.Intent
import com.koopa.kotonoha.snapshot.SnapshotSafStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var snapshotSaf: SnapshotSafStore

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        snapshotSaf = SnapshotSafStore.attach(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SnapshotSafStore.CHANNEL,
        ).setMethodCallHandler(snapshotSaf)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (::snapshotSaf.isInitialized &&
            snapshotSaf.onActivityResult(requestCode, resultCode, data)
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
