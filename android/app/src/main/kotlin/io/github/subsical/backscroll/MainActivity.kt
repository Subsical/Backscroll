package io.github.subsical.backscroll

import android.Manifest
import android.app.DownloadManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "backscroll/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "downloadsDir" -> result.success(downloadsDir())
                    "ensureWriteAccess" -> ensureWriteAccess(result)
                    "openFolder" -> result.success(openFolder(call.argument<String>("path") ?: ""))
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun downloadsDir(): String =
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath

    // Files apps open a folder from its storage provider URI. When none can,
    // a folder inside Downloads still gets the Downloads screen.
    private fun openFolder(path: String): Boolean {
        val folder = File(path).absoluteFile.normalize()
        val intents = mutableListOf<Intent>()
        storageDocumentId(folder)?.let { id ->
            val uri = DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE, id)
            intents += Intent(Intent.ACTION_VIEW).setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
        }
        if (folder.startsWith(File(downloadsDir()))) {
            intents += Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)
        }
        for (intent in intents) {
            try {
                startActivity(intent)
                return true
            } catch (e: RuntimeException) {
                continue
            }
        }
        return false
    }

    @Suppress("DEPRECATION")
    private fun storageDocumentId(folder: File): String? {
        val primary = Environment.getExternalStorageDirectory()
        if (folder.startsWith(primary)) return "primary:${folder.toRelativeString(primary)}"
        val card = Regex("^/storage/([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})(?:/(.*))?$").find(folder.path) ?: return null
        return "${card.groupValues[1]}:${card.groupValues[2]}"
    }

    // writing into Downloads by path needs the legacy permission up to Android 10
    private fun ensureWriteAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_REQUEST) {
            pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    private companion object {
        const val STORAGE_REQUEST = 4100
        const val EXTERNAL_STORAGE = "com.android.externalstorage.documents"
    }
}
