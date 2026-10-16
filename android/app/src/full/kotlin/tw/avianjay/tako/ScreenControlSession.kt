package tw.avianjay.tako

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager

/** Session resources survive overlay hiding, screenshots and model thinking. */
internal class ScreenControlSession(private val service: AccessibilityService) {
    private val main = Handler(Looper.getMainLooper())
    private var sessionId: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val timeout = Runnable {
        // Stop through Dart so a committed gesture finishes before returning.
        ControlSignals.stopRequested()
    }

    fun begin(id: String) {
        main.post {
            if (id.isEmpty() || sessionId == id) return@post
            finish(returnToApp = false)
            sessionId = id
            try {
                val power = service.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "tako:screen-control").apply {
                    setReferenceCounted(false)
                    acquire(MAX_SESSION_MILLIS)
                }
            } catch (_: SecurityException) {
                // Screen control remains available if the OS rejects the lock.
            }
            main.postDelayed(timeout, MAX_SESSION_MILLIS)
        }
    }

    fun end(id: String, returnToApp: Boolean) {
        main.post {
            if (id.isEmpty() || sessionId == id) finish(returnToApp)
        }
    }

    private fun finish(returnToApp: Boolean) {
        val hadSession = sessionId != null
        sessionId = null
        main.removeCallbacks(timeout)
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (!hadSession || !returnToApp) return
        try {
            // Reuse the running Flutter activity and its current conversation.
            service.startActivity(Intent(service, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ))
        } catch (_: Exception) {
            // The reply notification still links to Tako if launch is blocked.
        }
    }

    companion object {
        private const val MAX_SESSION_MILLIS = 30 * 60 * 1000L
    }
}
