package com.diubang.nasclient

import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.provider.MediaStore
import android.util.Log
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream

class MainActivity : FlutterActivity() {
    private val NSD_CHANNEL = "com.nasclient/nsd"
    private val MEDIA_STORAGE_CHANNEL = "com.nasclient/media_storage"
    private val BACKUP_SCHEDULER_CHANNEL = "com.nasclient/backup_scheduler"
    private val DEVICE_IDENTITY_CHANNEL = "com.nasclient/device_identity"
    private val TAG = "NAS Client"
    private var nsdManager: NsdManager? = null
    private val discoveryListeners = mutableMapOf<String, NsdManager.DiscoveryListener>()
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var backupSchedulerChannel: BackupSchedulerChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nsdManager = getSystemService(Context.NSD_SERVICE) as NsdManager
        backupSchedulerChannel = BackupSchedulerChannel(applicationContext)

        setupNsdChannel(flutterEngine)
        setupMediaStorageChannel(flutterEngine)
        setupBackupSchedulerChannel(flutterEngine)
        setupDeviceIdentityChannel(flutterEngine)
    }

    private fun setupNsdChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NSD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startDiscovery" -> {
                    val serviceTypes = call.argument<List<String>>("serviceTypes")
                    if (serviceTypes != null) {
                        Log.d(TAG, "Starting NSD discovery with service types: $serviceTypes")
                        startDiscovery(serviceTypes)
                    } else {
                        val defaultType = "_webdavs._tcp."
                        Log.d(TAG, "Starting NSD discovery with default service type: $defaultType")
                        startDiscovery(listOf(defaultType))
                    }
                    result.success(null)
                }
                "stopDiscovery" -> {
                    Log.d(TAG, "Stopping all NSD discoveries")
                    stopAllDiscoveries()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "${NSD_CHANNEL}/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    Log.d(TAG, "NSD EventChannel listener attached")
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    Log.d(TAG, "NSD EventChannel listener cancelled")
                }
            }
        )
    }

    private fun setupMediaStorageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToPublicStorage" -> {
                    val fileName = call.argument<String>("fileName")
                    val data = call.argument<ByteArray>("data")
                    val fileType = call.argument<String>("fileType")

                    if (fileName != null && data != null && fileType != null) {
                        try {
                            val uri = saveToPublicStorage(fileName, data, fileType)
                            result.success(uri)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to save file: ${e.message}", e)
                            result.error("SAVE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "fileName, data and fileType are required", null)
                    }
                }

                "saveFileToPublicStorage" -> {
                    val fileName = call.argument<String>("fileName")
                    val filePath = call.argument<String>("filePath")
                    val fileType = call.argument<String>("fileType")

                    if (fileName != null && filePath != null && fileType != null) {
                        try {
                            val uri = saveFileToPublicStorage(fileName, filePath, fileType)
                            result.success(uri)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to save file: ${e.message}", e)
                            result.error("SAVE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "fileName, filePath and fileType are required", null)
                    }
                }
                "readContentUri" -> {
                    val uri = call.argument<String>("uri")
                    if (uri != null) {
                        try {
                            val bytes = readContentUriBytes(uri)
                            result.success(bytes)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to read content URI: ${e.message}", e)
                            result.error("READ_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "uri is required", null)
                    }
                }
                "deleteContentUri" -> {
                    val uri = call.argument<String>("uri")
                    if (uri != null) {
                        try {
                            val deleted = deleteContentUri(uri)
                            result.success(deleted)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to delete content URI: ${e.message}", e)
                            result.error("DELETE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "uri is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readContentUriBytes(uriString: String): ByteArray {
        val uri = Uri.parse(uriString)
        contentResolver.openInputStream(uri)?.use { input ->
            return input.readBytes()
        } ?: throw Exception("Failed to open content URI: $uriString")
    }

    private fun deleteContentUri(uriString: String): Int {
        val uri = Uri.parse(uriString)
        return contentResolver.delete(uri, null, null)
    }

    private fun setupBackupSchedulerChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_SCHEDULER_CHANNEL)
            .setMethodCallHandler { call, result ->
                backupSchedulerChannel.onMethodCall(call, result)
            }
    }

    private fun setupDeviceIdentityChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_IDENTITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidId" -> {
                        val androidId =
                            Settings.Secure.getString(
                                applicationContext.contentResolver,
                                Settings.Secure.ANDROID_ID,
                            )?.trim()

                        if (androidId.isNullOrEmpty()) {
                            result.error(
                                "ANDROID_ID_UNAVAILABLE",
                                "ANDROID_ID is unavailable on this device",
                                null,
                            )
                        } else {
                            result.success(androidId)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToPublicStorage(fileName: String, data: ByteArray, fileType: String): String? {
        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, getMimeType(fileName))
            put(MediaStore.MediaColumns.RELATIVE_PATH, getRelativePath(fileType))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val contentResolver = contentResolver
        val uri: Uri? = when (fileType) {
            "image" -> contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
            "video" -> contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                } else {
                    val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    val destFile = java.io.File(downloadsDir, "NASClient/$fileName")
                    destFile.parentFile?.mkdirs()
                    destFile.writeBytes(data)
                    return destFile.absolutePath
                }
            }
        }

        if (uri == null) {
            throw Exception("Failed to create MediaStore entry")
        }

        try {
            val outputStream: OutputStream? = contentResolver.openOutputStream(uri)
            outputStream?.use { stream ->
                stream.write(data)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.clear()
                contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, contentValues, null, null)
            }

            Log.d(TAG, "File saved successfully: $uri")
            return uri.toString()
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
    }

    private fun saveFileToPublicStorage(fileName: String, filePath: String, fileType: String): String? {
        val sourceFile = java.io.File(filePath)
        if (!sourceFile.exists()) {
            throw Exception("Source file does not exist: $filePath")
        }

        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, getMimeType(fileName))
            put(MediaStore.MediaColumns.RELATIVE_PATH, getRelativePath(fileType))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val contentResolver = contentResolver
        val uri: Uri? = when (fileType) {
            "image" -> contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
            "video" -> contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                } else {
                    val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    val destFile = java.io.File(downloadsDir, "NASClient/$fileName")
                    destFile.parentFile?.mkdirs()
                    sourceFile.copyTo(destFile, overwrite = true)
                    return destFile.absolutePath
                }
            }
        }

        if (uri == null) {
            throw Exception("Failed to create MediaStore entry")
        }

        try {
            val outputStream: OutputStream? = contentResolver.openOutputStream(uri)
            outputStream?.use { stream ->
                sourceFile.inputStream().use { input ->
                    input.copyTo(stream)
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.clear()
                contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, contentValues, null, null)
            }

            Log.d(TAG, "File saved successfully: $uri")
            return uri.toString()
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
    }

    private fun getRelativePath(fileType: String): String {
        return when (fileType) {
            "image" -> "${Environment.DIRECTORY_DCIM}/NASClient"
            "video" -> "${Environment.DIRECTORY_MOVIES}/NASClient"
            else -> "${Environment.DIRECTORY_DOWNLOADS}/NASClient"
        }
    }

    private fun getMimeType(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        return when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "bmp" -> "image/bmp"
            "heic", "heif" -> "image/heic"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "avi" -> "video/x-msvideo"
            "mov" -> "video/quicktime"
            "wmv" -> "video/x-ms-wmv"
            "webm" -> "video/webm"
            "3gp" -> "video/3gpp"
            "pdf" -> "application/pdf"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "txt" -> "text/plain"
            "zip" -> "application/zip"
            else -> "application/octet-stream"
        }
    }

    private fun startDiscovery(serviceTypes: List<String>) {
        stopAllDiscoveries()

        for (serviceType in serviceTypes) {
            val listener = createDiscoveryListener(serviceType)
            discoveryListeners[serviceType] = listener

            try {
                nsdManager?.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
                Log.d(TAG, "Started NSD discovery for: $serviceType")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start NSD discovery for $serviceType: ${e.message}")
            }
        }
    }

    private fun createDiscoveryListener(serviceType: String): NsdManager.DiscoveryListener {
        return object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                Log.d(TAG, "NSD discovery started for: $regType")
            }

            override fun onServiceFound(service: NsdServiceInfo) {
                Log.d(TAG, "NSD service found: ${service.serviceName}, type: ${service.serviceType}")
                resolveService(service)
            }

            override fun onServiceLost(service: NsdServiceInfo) {
                Log.d(TAG, "NSD service lost: ${service.serviceName}")
            }

            override fun onDiscoveryStopped(serviceType: String) {
                Log.d(TAG, "NSD discovery stopped for: $serviceType")
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e(TAG, "NSD start discovery failed for $serviceType: error $errorCode")
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e(TAG, "NSD stop discovery failed for $serviceType: error $errorCode")
            }
        }
    }

    private fun resolveService(serviceInfo: NsdServiceInfo) {
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "NSD resolve failed for ${serviceInfo.serviceName}: error $errorCode")
            }

            override fun onServiceResolved(resolvedInfo: NsdServiceInfo) {
                Log.d(TAG, "NSD service resolved: ${resolvedInfo.serviceName}, host: ${resolvedInfo.host}, port: ${resolvedInfo.port}")
                mainHandler.post {
                    eventSink?.success(mapOf(
                        "method" to "onServiceFound",
                        "name" to resolvedInfo.serviceName,
                        "host" to resolvedInfo.host?.hostAddress,
                        "port" to resolvedInfo.port,
                        "serviceType" to resolvedInfo.serviceType,
                        "txtRecords" to resolvedInfo.attributes.mapValues { entry ->
                            entry.value?.toString(Charsets.UTF_8) ?: ""
                        }
                    ))
                }
            }
        }

        try {
            nsdManager?.resolveService(serviceInfo, resolveListener)
        } catch (e: Exception) {
            Log.e(TAG, "NSD exception in resolveService: ${e.message}")
        }
    }

    private fun stopAllDiscoveries() {
        for ((serviceType, listener) in discoveryListeners) {
            try {
                nsdManager?.stopServiceDiscovery(listener)
                Log.d(TAG, "Stopped NSD discovery for: $serviceType")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop NSD discovery for $serviceType: ${e.message}")
            }
        }
        discoveryListeners.clear()
    }

    override fun onDestroy() {
        stopAllDiscoveries()
        super.onDestroy()
    }
}
