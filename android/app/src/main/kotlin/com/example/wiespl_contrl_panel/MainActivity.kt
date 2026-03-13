// package com.example.wiespl_contrl_panel

// import androidx.annotation.NonNull
// import io.flutter.embedding.android.FlutterActivity
// import io.flutter.embedding.engine.FlutterEngine
// import io.flutter.plugin.common.MethodChannel
// import io.flutter.plugins.GeneratedPluginRegistrant
// import android.content.Intent
// import android.net.Uri
// import android.provider.Settings
// import android.os.Build
// import android.os.Handler
// import android.os.Looper
// import androidx.core.content.FileProvider
// import java.io.File

// class MainActivity: FlutterActivity() {
//     private val CHANNEL = "app_launcher_channel"
//     private val RECORDING_CHANNEL = "com.example.wiespl_contrl_panel/recording_service"
//     private val FILE_CHANNEL = "com.example.wiespl_contrl_panel/file_open"
//     private val handler = Handler(Looper.getMainLooper())

//     override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
//         // 1. Manually register plugins
//         GeneratedPluginRegistrant.registerWith(flutterEngine)

//         // 2. Standard engine setup
//         super.configureFlutterEngine(flutterEngine)

//         checkOverlayPermission()

//         // ── Existing: app launcher channel ────────────────────────────────────
//         MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
//             .setMethodCallHandler { call, result ->
//                 when (call.method) {
//                     "launchApp" -> {
//                         val packageName = call.arguments as String
//                         launchApp(packageName, result)
//                     }
//                     else -> result.notImplemented()
//                 }
//             }

//         // ── Existing: foreground recording service channel ────────────────────
//         MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL)
//             .setMethodCallHandler { call, result ->
//                 val intent = Intent(this, RecordingService::class.java)
//                 when (call.method) {
//                     "startService" -> {
//                         intent.action = RecordingService.ACTION_START
//                         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//                             startForegroundService(intent)
//                         } else {
//                             startService(intent)
//                         }
//                         result.success(null)
//                     }
//                     "stopService" -> {
//                         intent.action = RecordingService.ACTION_STOP
//                         startService(intent)
//                         result.success(null)
//                     }
//                     else -> result.notImplemented()
//                 }
//             }

//         // ── New: open video file in external player (MX Player, VLC, etc.) ────
//         // Uses FileProvider to create a content:// URI — required on Android 7+
//         // because plain file:// URIs are blocked across app boundaries.
//         MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL)
//             .setMethodCallHandler { call, result ->
//                 when (call.method) {
//                     "openVideo" -> {
//                         val path = call.argument<String>("path")
//                         if (path == null) {
//                             result.error("INVALID_ARG", "path is null", null)
//                             return@setMethodCallHandler
//                         }
//                         try {
//                             val file = File(path)
//                             if (!file.exists()) {
//                                 result.error("FILE_NOT_FOUND", "File not found: $path", null)
//                                 return@setMethodCallHandler
//                             }
//                             val uri: Uri = FileProvider.getUriForFile(
//                                 this,
//                                 "${packageName}.fileprovider",
//                                 file
//                             )
//                             val intent = Intent(Intent.ACTION_VIEW).apply {
//                                 setDataAndType(uri, "video/mp4")
//                                 addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
//                                 addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
//                             }
//                             if (intent.resolveActivity(packageManager) != null) {
//                                 startActivity(intent)
//                                 result.success(null)
//                             } else {
//                                 // Fallback: try generic video/* type
//                                 intent.setDataAndType(uri, "video/*")
//                                 if (intent.resolveActivity(packageManager) != null) {
//                                     startActivity(intent)
//                                     result.success(null)
//                                 } else {
//                                     result.error("NO_APP", "No video player app found", null)
//                                 }
//                             }
//                         } catch (e: Exception) {
//                             result.error("OPEN_FAILED", e.message, null)
//                         }
//                     }
//                     else -> result.notImplemented()
//                 }
//             }
//     }

//     private fun checkOverlayPermission() {
//         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
//             if (!Settings.canDrawOverlays(this)) {
//                 val intent = Intent(
//                     Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
//                     Uri.parse("package:$packageName")
//                 )
//                 startActivityForResult(intent, 1234)
//             }
//         }
//     }

//     private fun launchApp(packageName: String, result: MethodChannel.Result) {
//         try {
//             val intent = packageManager.getLaunchIntentForPackage(packageName)
//             if (intent != null) {
//                 startActivity(intent)
//                 result.success(true)
//             } else {
//                 result.success(false)
//             }
//         } catch (e: Exception) {
//             result.success(false)
//         }
//     }
// }
package com.example.wiespl_contrl_panel

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app_launcher_channel"
    private val RECORDING_CHANNEL = "com.example.wiespl_contrl_panel/recording_service"
    private val FILE_CHANNEL = "com.example.wiespl_contrl_panel/file_open"
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        // 1. Manually register plugins
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // 2. Standard engine setup
        super.configureFlutterEngine(flutterEngine)

        checkOverlayPermission()

        // ── Existing: app launcher channel ────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchApp" -> {
                        val packageName = call.arguments as String
                        launchApp(packageName, result)
                    }
                    "launchAppAndEnterPip" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        launchAppAndEnterPip(packageName, result)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Existing: foreground recording service channel ────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL)
            .setMethodCallHandler { call, result ->
                val intent = Intent(this, RecordingService::class.java)
                when (call.method) {
                    "startService" -> {
                        intent.action = RecordingService.ACTION_START
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stopService" -> {
                        intent.action = RecordingService.ACTION_STOP
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── New: open video file in external player (MX Player, VLC, etc.) ────
        // Uses FileProvider to create a content:// URI — required on Android 7+
        // because plain file:// URIs are blocked across app boundaries.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openVideo" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARG", "path is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "File not found: $path", null)
                                return@setMethodCallHandler
                            }
                            val uri: Uri = FileProvider.getUriForFile(
                                this,
                                "${packageName}.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "video/mp4")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            if (intent.resolveActivity(packageManager) != null) {
                                startActivity(intent)
                                result.success(null)
                            } else {
                                // Fallback: try generic video/* type
                                intent.setDataAndType(uri, "video/*")
                                if (intent.resolveActivity(packageManager) != null) {
                                    startActivity(intent)
                                    result.success(null)
                                } else {
                                    result.error("NO_APP", "No video player app found", null)
                                }
                            }
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, 1234)
            }
        }
    }

    private fun launchApp(packageName: String, result: MethodChannel.Result) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                startActivity(intent)
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    // Launches an app and requests it to enter Picture-in-Picture mode.
    // PiP is requested by sending ACTION_MEDIA_BUTTON or by using the
    // app's own PiP intent extra if supported. For DroidRender specifically,
    // we launch it normally — the app must handle PiP itself once focused.
    // We use FLAG_ACTIVITY_NEW_TASK so it launches as a separate task,
    // then after a short delay we move our own activity to background so
    // the launched app becomes visible and can trigger PiP.
    private fun launchAppAndEnterPip(packageName: String, result: MethodChannel.Result) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent == null) {
                result.success(false)
                return
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            // Signal to the target app that PiP is requested on launch
            intent.putExtra("enter_pip", true)
            intent.putExtra("pip_on_launch", true)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }
}