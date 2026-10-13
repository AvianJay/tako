package tw.avianjay.tako

import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger

// No updater channel or installer is present in Google Play builds.
object UpdaterFlavor {
    fun register(activity: FlutterActivity, messenger: BinaryMessenger) = Unit
}
