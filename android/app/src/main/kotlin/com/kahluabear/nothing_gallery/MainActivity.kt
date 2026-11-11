package com.kahluabear.nothing_gallery

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.kahluabear.nothing_gallery/native_trash"
    private var pendingResult: MethodChannel.Result? = null
    private var pendingDeleteItems: List<Map<String, Any>>? = null
    private val REQ_TRASH = 1001
    private val REQ_DELETE = 1002

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null) { _, uri ->
                            runOnUiThread { result.success(uri?.toString()) }
                        }
                    } else {
                        result.error("ERROR", "Path is null", null)
                    }
                }
                "restoreItems" -> {
                    val items = call.argument<List<Map<String, Any>>>("items")
                    if (items != null && items.isNotEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val uris = items.mapNotNull { item ->
                                val idStr = item["id"] as? String
                                val isVideo = item["isVideo"] as? Boolean ?: false
                                val id = idStr?.toLongOrNull()
                                if (id != null) {
                                    val baseUri = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                                    ContentUris.withAppendedId(baseUri, id)
                                } else null
                            }
                            if (uris.isNotEmpty()) {
                                val pi = MediaStore.createTrashRequest(contentResolver, uris, false)
                                pendingResult = result
                                startIntentSenderForResult(pi.intentSender, REQ_TRASH, null, 0, 0, 0)
                            } else {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    } else {
                        result.success(null)
                    }
                }
                "deletePermanently" -> {
                    val items = call.argument<List<Map<String, Any>>>("items")
                    if (items != null && items.isNotEmpty()) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            try {
                                val uris = items.mapNotNull { item ->
                                    val idStr = item["id"] as? String
                                    val isVideo = item["isVideo"] as? Boolean ?: false
                                    val id = idStr?.toLongOrNull()
                                    if (id != null) {
                                        val baseUri = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                                        ContentUris.withAppendedId(baseUri, id)
                                    } else null
                                }
                                if (uris.isNotEmpty()) {
                                    val pi = MediaStore.createDeleteRequest(contentResolver, uris)
                                    pendingResult = result
                                    pendingDeleteItems = items
                                    startIntentSenderForResult(pi.intentSender, REQ_DELETE, null, 0, 0, 0)
                                } else {
                                    // Fallback direct delete
                                    for (item in items) {
                                        val p = item["path"] as? String
                                        if (p != null) {
                                            try { java.io.File(p).delete() } catch (_: Exception) {}
                                        }
                                    }
                                    result.success(true)
                                }
                            } catch (e: Exception) {
                                for (item in items) {
                                    val p = item["path"] as? String
                                    if (p != null) {
                                        try { java.io.File(p).delete() } catch (_: Exception) {}
                                    }
                                }
                                result.success(true)
                            }
                        } else {
                            // Android 10 or below
                            for (item in items) {
                                val idStr = item["id"] as? String
                                val isVideo = item["isVideo"] as? Boolean ?: false
                                val p = item["path"] as? String
                                val id = idStr?.toLongOrNull()
                                if (id != null) {
                                    val baseUri = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                                    val uri = ContentUris.withAppendedId(baseUri, id)
                                    try { contentResolver.delete(uri, null, null) } catch (_: Exception) {}
                                }
                                if (p != null) {
                                    try { java.io.File(p).delete() } catch (_: Exception) {}
                                }
                            }
                            result.success(true)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_TRASH) {
            val success = resultCode == Activity.RESULT_OK
            pendingResult?.success(success)
            pendingResult = null
        } else if (requestCode == REQ_DELETE) {
            val success = resultCode == Activity.RESULT_OK
            if (success) {
                pendingDeleteItems?.forEach { item ->
                    val path = item["path"] as? String
                    if (path != null) {
                        try {
                            val f = java.io.File(path)
                            if (f.exists()) f.delete()
                        } catch (_: Exception) {}
                    }
                }
            }
            pendingDeleteItems = null
            pendingResult?.success(success)
            pendingResult = null
        }
    }
}
