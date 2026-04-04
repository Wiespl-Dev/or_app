package com.example.wiespl_contrl_panel

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

// DicomHero imports
import com.dicomhero.api.CodecFactory
import com.dicomhero.api.ColorTransformsFactory
import com.dicomhero.api.DataSet
import com.dicomhero.api.DrawBitmap
import com.dicomhero.api.Image
import com.dicomhero.api.TagId
import com.dicomhero.api.TransformsChain
import com.dicomhero.api.VOILUT
import com.dicomhero.api.drawBitmapType_t

// JPEG 2000
import com.gemalto.jp2.JP2Decoder

class MainActivity : FlutterActivity() {

    // ── Existing channels ─────────────────────────────────────────────────────
    private val CHANNEL           = "app_launcher_channel"
    private val RECORDING_CHANNEL = "com.example.wiespl_contrl_panel/recording_service"
    private val FILE_CHANNEL      = "com.example.wiespl_contrl_panel/file_open"

    // ── New DICOM channel ─────────────────────────────────────────────────────
    private val DICOM_CHANNEL     = "com.example.wiespl_contrl_panel/dicom"

    private val handler              = Handler(Looper.getMainLooper())
    private var activeRecordingCount = 0
    private val dicomScope           = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val TAG                  = "DicomViewer"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        super.configureFlutterEngine(flutterEngine)

        // Load DicomHero native library
        try { System.loadLibrary("dicomhero6") } catch (e: UnsatisfiedLinkError) { e.printStackTrace() }

        checkOverlayPermission()

        // ── App launcher channel ──────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchApp" -> launchApp(call.arguments as String, result)
                    "launchAppAndEnterPip" -> {
                        val pkg = call.argument<String>("packageName") ?: ""
                        launchAppAndEnterPip(pkg, result)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Recording service channel ─────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        activeRecordingCount++
                        if (activeRecordingCount == 1) {
                            val intent = Intent(this, RecordingService::class.java)
                                .apply { action = RecordingService.ACTION_START }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                                startForegroundService(intent)
                            else startService(intent)
                        }
                        result.success(null)
                    }
                    "stopService" -> {
                        activeRecordingCount = maxOf(0, activeRecordingCount - 1)
                        if (activeRecordingCount == 0) {
                            val intent = Intent(this, RecordingService::class.java)
                                .apply { action = RecordingService.ACTION_STOP }
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "updateNotification" -> {
                        val text = call.argument<String>("text") ?: "Recording…"
                        val intent = Intent(this, RecordingService::class.java).apply {
                            action = RecordingService.ACTION_UPDATE
                            putExtra(RecordingService.EXTRA_TEXT, text)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── File open channel ─────────────────────────────────────────────────
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
                                this, "${packageName}.fileprovider", file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "video/mp4")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            }
                            if (intent.resolveActivity(packageManager) != null) {
                                startActivity(intent); result.success(null)
                            } else {
                                intent.setDataAndType(uri, "video/*")
                                if (intent.resolveActivity(packageManager) != null) {
                                    startActivity(intent); result.success(null)
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

        // ── DICOM viewer channel ──────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DICOM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "renderDicom" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("NO_PATH", "Path is null", null)
                            return@setMethodCallHandler
                        }
                        dicomScope.launch {
                            try {
                                val data = withContext(Dispatchers.IO) { renderDicom(path) }
                                result.success(data)
                            } catch (e: Exception) {
                                e.printStackTrace()
                                result.error("RENDER_ERROR", e.message ?: "Unknown", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── DICOM rendering ───────────────────────────────────────────────────────
    private fun renderDicom(path: String): Map<String, Any> {
        val file = File(path)
        if (!file.exists()) throw Exception("File not found: $path")

        val dicomBytes = file.readBytes()

        var transferSyntax      = "1.2.840.10008.1.2.1"
        var patientName         = ""
        var modality            = ""
        var studyDate           = ""
        var institution         = ""
        var rows                = 0
        var cols                = 0
        var bitsAlloc           = 16
        var pixelRepresentation = 0
        var rescaleSlope        = 1.0f
        var rescaleIntercept    = 0.0f
        var windowCenter        = Float.NaN
        var windowWidth         = Float.NaN

        try {
            val dataSet: DataSet = CodecFactory.load(path)
            transferSyntax      = safeTag { dataSet.getString(TagId(0x0002, 0x0010), 0, "") }
            patientName         = safeTag { dataSet.getString(TagId(0x0010, 0x0010), 0, "") }
            modality            = safeTag { dataSet.getString(TagId(0x0008, 0x0060), 0, "") }
            studyDate           = safeTag { dataSet.getString(TagId(0x0008, 0x0020), 0, "") }
            institution         = safeTag { dataSet.getString(TagId(0x0008, 0x0080), 0, "") }
            rows                = safeInt { dataSet.getUint32(TagId(0x0028, 0x0010), 0).toInt() } ?: 0
            cols                = safeInt { dataSet.getUint32(TagId(0x0028, 0x0011), 0).toInt() } ?: 0
            bitsAlloc           = safeInt { dataSet.getUint32(TagId(0x0028, 0x0100), 0).toInt() } ?: 16
            pixelRepresentation = safeInt { dataSet.getUint32(TagId(0x0028, 0x0103), 0).toInt() } ?: 0
            rescaleSlope        = safeFloat { dataSet.getDouble(TagId(0x0028, 0x1053), 0).toFloat() } ?: 1.0f
            rescaleIntercept    = safeFloat { dataSet.getDouble(TagId(0x0028, 0x1052), 0).toFloat() } ?: 0.0f
            windowCenter        = safeFloat { dataSet.getDouble(TagId(0x0028, 0x1050), 0).toFloat() } ?: Float.NaN
            windowWidth         = safeFloat { dataSet.getDouble(TagId(0x0028, 0x1051), 0).toFloat() } ?: Float.NaN

            try {
                val png = renderViaDigomHero(dataSet)
                return buildResult(png, cols, rows, patientName, modality, studyDate, institution)
            } catch (e: Exception) {
                Log.w(TAG, "DicomHero native render failed: ${e.message}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "DataSet load failed: ${e.message}")
            transferSyntax = extractTransferSyntax(dicomBytes)
            modality       = extractTag(dicomBytes, 0x0008, 0x0060) ?: ""
            rows           = extractUint16(dicomBytes, 0x0028, 0x0010)
            cols           = extractUint16(dicomBytes, 0x0028, 0x0011)
            bitsAlloc      = extractUint16(dicomBytes, 0x0028, 0x0100).takeIf { it > 0 } ?: 16
        }

        Log.i(TAG, "TS=$transferSyntax  ${cols}x${rows}  $bitsAlloc-bit")

        val png: ByteArray = when {
            transferSyntax.startsWith("1.2.840.10008.1.2.4.9") ->
                decodeJpeg2000(dicomBytes)
                    ?: throw Exception("JPEG 2000 decode failed.\nTS: $transferSyntax")
            transferSyntax.startsWith("1.2.840.10008.1.2.4") ->
                decodeJpeg(dicomBytes)
                    ?: throw Exception("JPEG decode failed.\nTS: $transferSyntax")
            else ->
                decodeRawPixels(dicomBytes, rows, cols, bitsAlloc, pixelRepresentation,
                    rescaleSlope, rescaleIntercept, windowCenter, windowWidth)
                    ?: throw Exception("Raw decode failed.\nTS: $transferSyntax  ${cols}x${rows}")
        }

        return buildResult(png, cols, rows, patientName, modality, studyDate, institution)
    }

    private fun renderViaDigomHero(dataSet: DataSet): ByteArray {
        val image: Image = dataSet.getImageApplyModalityTransform(0)
        val w = image.width.toInt(); val h = image.height.toInt()
        val chain = TransformsChain()
        if (ColorTransformsFactory.isMonochrome(image.colorSpace))
            chain.addTransform(VOILUT(VOILUT.getOptimalVOI(image, 0, 0, image.width, image.height)))
        val mem  = DrawBitmap(chain).getBitmap(image, drawBitmapType_t.drawBitmapRGBA, 4)
        val rgba = ByteArray(mem.size().toInt())
        mem.data(rgba)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    private fun decodeJpeg2000(dicomBytes: ByteArray): ByteArray? {
        val j2kStart = findMarker(dicomBytes, byteArrayOf(0xFF.toByte(), 0x4F.toByte()))
        val jp2Start = findMarker(dicomBytes, byteArrayOf(0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20))
        val start = when {
            j2kStart >= 0 && jp2Start >= 0 -> minOf(j2kStart, jp2Start)
            j2kStart >= 0 -> j2kStart
            jp2Start >= 0 -> jp2Start
            else -> 0
        }
        val j2kBytes = dicomBytes.copyOfRange(start, dicomBytes.size)
        return try {
            val bitmap = JP2Decoder(j2kBytes).decode() ?: return null
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            Log.w(TAG, "JP2Decoder failed: ${e.message}"); null
        }
    }

    private fun decodeJpeg(dicomBytes: ByteArray): ByteArray? {
        val start = findMarker(dicomBytes, byteArrayOf(0xFF.toByte(), 0xD8.toByte()))
        if (start < 0) return null
        var end = dicomBytes.size
        for (i in dicomBytes.size - 2 downTo start)
            if (dicomBytes[i] == 0xFF.toByte() && dicomBytes[i+1] == 0xD9.toByte()) { end = i+2; break }
        val bmp = android.graphics.BitmapFactory.decodeByteArray(dicomBytes, start, end - start)
            ?: return null
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out); bmp.recycle()
        return out.toByteArray()
    }

    private fun decodeRawPixels(
        d: ByteArray, rows: Int, cols: Int, bitsAlloc: Int, pixelRep: Int,
        slope: Float, intercept: Float, wc: Float, ww: Float,
    ): ByteArray? {
        if (rows <= 0 || cols <= 0) return null
        val off = findPixelData(d) ?: return null
        val pixels = rows * cols
        return if (bitsAlloc <= 8) render8bit(d, off, pixels, cols, rows)
        else render16bit(d, off, pixels, cols, rows, pixelRep, slope, intercept, wc, ww)
    }

    private fun render8bit(data: ByteArray, off: Int, pixels: Int, w: Int, h: Int): ByteArray {
        val rgba = ByteArray(pixels * 4)
        for (i in 0 until pixels) {
            val v = if (off+i < data.size) data[off+i].toInt() and 0xFF else 0
            rgba[i*4]=v.toByte(); rgba[i*4+1]=v.toByte(); rgba[i*4+2]=v.toByte(); rgba[i*4+3]=0xFF.toByte()
        }
        return rgbaToPng(rgba, w, h)
    }

    private fun render16bit(
        data: ByteArray, off: Int, pixels: Int, w: Int, h: Int,
        pixelRep: Int, slope: Float, intercept: Float, wc: Float, ww: Float,
    ): ByteArray {
        val count = minOf(pixels, (data.size - off) / 2)
        val buf = ByteBuffer.wrap(data, off, count * 2).order(ByteOrder.LITTLE_ENDIAN)
        val samples = FloatArray(count) {
            var r = buf.short.toInt()
            if (pixelRep == 1 && r > 32767) r -= 65536
            r * slope + intercept
        }
        val lo: Float; val hi: Float
        if (!wc.isNaN() && !ww.isNaN() && ww > 0f) { lo = wc - ww/2f; hi = wc + ww/2f }
        else { var mn=samples[0]; var mx=mn; for(s in samples){if(s<mn)mn=s; if(s>mx)mx=s}; lo=mn; hi=mn+(mx-mn).coerceAtLeast(1f) }
        val rgba = ByteArray(pixels * 4)
        for (i in 0 until count) {
            val g = ((samples[i]-lo)/(hi-lo)*255f).toInt().coerceIn(0,255)
            rgba[i*4]=g.toByte(); rgba[i*4+1]=g.toByte(); rgba[i*4+2]=g.toByte(); rgba[i*4+3]=0xFF.toByte()
        }
        return rgbaToPng(rgba, w, h)
    }

    private fun rgbaToPng(rgba: ByteArray, w: Int, h: Int): ByteArray {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out); bmp.recycle()
        return out.toByteArray()
    }

    private fun findMarker(data: ByteArray, m: ByteArray): Int {
        outer@ for (i in 0..data.size-m.size) {
            for (j in m.indices) if (data[i+j]!=m[j]) continue@outer; return i }
        return -1
    }

    private fun findPixelData(data: ByteArray): Int? {
        for (i in 0 until data.size-12) {
            if (data[i]==0xE0.toByte()&&data[i+1]==0x7F.toByte()&&data[i+2]==0x10.toByte()&&data[i+3]==0x00.toByte()) {
                val vr = String(byteArrayOf(data[i+4],data[i+5]))
                return if (vr=="OB"||vr=="OW") i+12 else i+8
            }
        }
        return null
    }

    private fun extractTransferSyntax(data: ByteArray) =
        extractTag(data, 0x0002, 0x0010) ?: "1.2.840.10008.1.2.1"

    private fun extractTag(data: ByteArray, group: Int, element: Int): String? {
        val g0=(group and 0xFF).toByte(); val g1=((group shr 8)and 0xFF).toByte()
        val e0=(element and 0xFF).toByte(); val e1=((element shr 8)and 0xFF).toByte()
        for (i in 0 until data.size-8) {
            if (data[i]==g0&&data[i+1]==g1&&data[i+2]==e0&&data[i+3]==e1) {
                val len=(data[i+6].toInt()and 0xFF) or ((data[i+7].toInt()and 0xFF) shl 8)
                if (len<=0||i+8+len>data.size) continue
                return String(data,i+8,len).trim().trimEnd('\u0000')
            }
        }
        return null
    }

    private fun extractUint16(data: ByteArray, group: Int, element: Int): Int {
        val g0=(group and 0xFF).toByte(); val g1=((group shr 8)and 0xFF).toByte()
        val e0=(element and 0xFF).toByte(); val e1=((element shr 8)and 0xFF).toByte()
        for (i in 0 until data.size-8) {
            if (data[i]==g0&&data[i+1]==g1&&data[i+2]==e0&&data[i+3]==e1) {
                val o=i+8; if(o+2>data.size) continue
                return (data[o].toInt()and 0xFF) or ((data[o+1].toInt()and 0xFF) shl 8)
            }
        }
        return 0
    }

    private fun buildResult(png: ByteArray, w: Int, h: Int, pn: String, mod: String, sd: String, inst: String) =
        mapOf("pixels" to png, "width" to w, "height" to h,
            "patientName" to pn, "modality" to mod, "studyDate" to sd, "institution" to inst)

    private fun safeTag(fn: () -> String): String  = try { fn().trim() } catch (_: Exception) { "" }
    private fun safeInt(fn: () -> Int): Int?        = try { fn() }       catch (_: Exception) { null }
    private fun safeFloat(fn: () -> Float): Float?  = try { fn() }       catch (_: Exception) { null }

    // ── Existing helpers ──────────────────────────────────────────────────────
    override fun onDestroy() {
        dicomScope.cancel()
        if (activeRecordingCount > 0) {
            activeRecordingCount = 0
            val intent = Intent(this, RecordingService::class.java)
                .apply { action = RecordingService.ACTION_STOP }
            startService(intent)
        }
        super.onDestroy()
    }

    private fun checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            startActivityForResult(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")), 1234)
        }
    }

    private fun launchApp(packageName: String, result: MethodChannel.Result) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) { startActivity(intent); result.success(true) }
            else result.success(false)
        } catch (e: Exception) { result.success(false) }
    }

    private fun launchAppAndEnterPip(packageName: String, result: MethodChannel.Result) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
                ?: run { result.success(false); return }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            intent.putExtra("enter_pip", true)
            intent.putExtra("pip_on_launch", true)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }
}