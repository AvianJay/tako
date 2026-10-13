package tw.avianjay.tako

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

object UpdaterFlavor {
    @Suppress("DEPRECATION")
    fun register(activity: FlutterActivity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "tw.avianjay.tako/updater").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> {
                        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                        result.success(mapOf("abis" to Build.SUPPORTED_ABIS.toList(),
                            "version" to info.versionName, "commit" to BuildConfig.BUILD_COMMIT,
                            "installedAt" to info.lastUpdateTime))
                    }
                    "prepareInstall" -> {
                        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")))
                            result.success(false)
                        } else result.success(true)
                    }
                    "install" -> {
                        val path = requireNotNull(call.argument<String>("path"))
                        val file = File(path).canonicalFile
                        val directory = File(activity.cacheDir, "updates").canonicalFile
                        require(file.parentFile == directory && file.name == "tako-update.apk" && file.isFile)
                        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                        val installed = activity.packageManager.getPackageInfo(activity.packageName, flags)
                        val candidate = requireNotNull(activity.packageManager.getPackageArchiveInfo(file.path, flags))
                        require(candidate.packageName == activity.packageName)
                        val existingSignatures = if (Build.VERSION.SDK_INT >= 28) installed.signingInfo?.apkContentsSigners else installed.signatures
                        val newSignatures = if (Build.VERSION.SDK_INT >= 28) candidate.signingInfo?.apkContentsSigners else candidate.signatures
                        require(!existingSignatures.isNullOrEmpty() && !newSignatures.isNullOrEmpty() &&
                            existingSignatures.toSet() == newSignatures.toSet())
                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updater", file)
                        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri,
                            "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("update_failed", "Could not prepare or install update", null)
            }
        }
    }
}
