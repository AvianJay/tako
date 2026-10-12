package tw.avianjay.tako

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper

/**
 * Process-wide signals from services and receivers to the Flutter engine,
 * delivered on the main thread. Nothing is queued while no engine listens.
 */
object ControlSignals {
    interface Listener {
        fun stopRequested()
        fun statusChanged()
    }

    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var listener: Listener? = null

    fun stopRequested() {
        main.post { listener?.stopRequested() }
    }

    fun statusChanged() {
        main.post { listener?.statusChanged() }
    }
}

/** The Stop action of the screen-control notification. Not exported. */
class ControlActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == AlertNotifications.ACTION_STOP) ControlSignals.stopRequested()
    }
}

/** Runtime permissions requested from setup screens, one dialog at a time. */
class PermissionBroker(private val activity: Activity) {
    private var nextCode = 7000
    private val pending = mutableMapOf<Int, (Boolean) -> Unit>()

    fun granted(permission: String) =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun request(permission: String, callback: (Boolean) -> Unit) {
        if (granted(permission)) {
            callback(true)
            return
        }
        if (pending.isNotEmpty()) {
            callback(false)
            return
        }
        val code = nextCode++
        pending[code] = callback
        try {
            activity.requestPermissions(arrayOf(permission), code)
        } catch (_: Exception) {
            pending.remove(code)
            callback(false)
        }
    }

    fun onResult(code: Int, grantResults: IntArray) {
        val callback = pending.remove(code) ?: return
        callback(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
    }

    fun dispose() {
        val callbacks = pending.values.toList()
        pending.clear()
        callbacks.forEach { it(false) }
    }
}
