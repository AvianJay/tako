package tw.avianjay.tako

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.Executors

/**
 * Bound by the system once the user grants notification access. It keeps no
 * history: notifications_list reads the active notifications on request.
 */
class TakoNotificationListener : NotificationListenerService() {
    companion object {
        @Volatile
        var instance: TakoNotificationListener? = null
            private set
    }

    override fun onListenerConnected() {
        instance = this
        ControlSignals.statusChanged()
    }

    override fun onListenerDisconnected() {
        if (instance === this) instance = null
        ControlSignals.statusChanged()
    }
}

/** No notification is read at construction or while checking status. */
class NotificationApiHost(
    private val activity: Activity,
    private val permissions: PermissionBroker,
) : NotificationApi {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val component get() = ComponentName(activity, TakoNotificationListener::class.java)
    private val manager get() = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun error(code: String) = ControlError(code, code, null)

    private fun hasAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            return manager.isNotificationListenerAccessGranted(component)
        }
        val enabled = Settings.Secure.getString(activity.contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(':').mapNotNull(ComponentName::unflattenFromString).any { it == component }
    }

    override fun status() = NotificationStatusData(hasAccess(), manager.areNotificationsEnabled())

    override fun openAccessSettings() {
        val fallback = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
        } else fallback
        try {
            activity.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            try { activity.startActivity(fallback) } catch (_: ActivityNotFoundException) { throw error("unavailable") }
        }
    }

    override fun requestPostPermission(callback: (Result<Boolean>) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            callback(Result.success(manager.areNotificationsEnabled()))
            return
        }
        permissions.request(Manifest.permission.POST_NOTIFICATIONS) {
            callback(Result.success(it && manager.areNotificationsEnabled()))
        }
    }

    override fun list(limit: Long, callback: (Result<List<DeviceNotificationData>>) -> Unit) {
        if (limit !in 1..50) {
            callback(Result.failure(error("invalid_arguments")))
            return
        }
        if (!hasAccess()) {
            callback(Result.failure(error("notification_access_required")))
            return
        }
        val listener = TakoNotificationListener.instance
        if (listener == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) NotificationListenerService.requestRebind(component)
            callback(Result.failure(error("notification_listener_unavailable")))
            return
        }
        worker.execute {
            val result = try {
                Result.success(read(listener, limit.toInt()))
            } catch (_: SecurityException) {
                Result.failure(error("notification_access_required"))
            } catch (_: Throwable) {
                Result.failure(error("notification_read_failed"))
            }
            main.post { callback(result) }
        }
    }

    private fun read(listener: NotificationListenerService, limit: Int): List<DeviceNotificationData> {
        val active = listener.activeNotifications.orEmpty().filter { it.packageName != activity.packageName }
        // A group summary repeats its children; keep it only when it is alone.
        val groups = active.filter { !isSummary(it) }.mapNotNull { it.groupKey }.toSet()
        val labels = mutableMapOf<String, String>()
        return active
            .filter { !isSummary(it) || it.groupKey !in groups }
            .sortedByDescending { it.postTime }
            .take(limit)
            .map { notification ->
                val extras = notification.notification.extras ?: Bundle.EMPTY
                val title = text(extras, Notification.EXTRA_TITLE_BIG) ?: text(extras, Notification.EXTRA_TITLE)
                val body = text(extras, Notification.EXTRA_BIG_TEXT) ?: text(extras, Notification.EXTRA_TEXT)
                DeviceNotificationData(
                    packageName = notification.packageName,
                    appLabel = labels.getOrPut(notification.packageName) { label(notification.packageName) },
                    title = title?.take(300),
                    text = body?.take(1000),
                    lines = lines(extras),
                    postedAt = notification.postTime,
                    ongoing = notification.isOngoing,
                    category = notification.notification.category,
                )
            }
    }

    private fun isSummary(notification: StatusBarNotification) =
        notification.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0

    private fun text(extras: Bundle, key: String): String? =
        extras.getCharSequence(key)?.toString()?.let(::clean)?.takeIf { it.isNotEmpty() }

    private fun clean(value: String) = value.replace(Regex("[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F]"), "").trim()

    @Suppress("DEPRECATION")
    private fun lines(extras: Bundle): List<String> {
        val result = mutableListOf<String>()
        // Messaging style: the latest messages with their senders.
        val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        messages?.takeLast(5)?.forEach { item ->
            val message = item as? Bundle ?: return@forEach
            val text = message.getCharSequence("text")?.toString()?.let(::clean).orEmpty()
            val sender = message.getCharSequence("sender")?.toString()?.let(::clean).orEmpty()
            if (text.isNotEmpty()) result.add((if (sender.isEmpty()) text else "$sender: $text").take(300))
        }
        if (result.isEmpty()) {
            extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.take(8)?.forEach { line ->
                val text = clean(line.toString())
                if (text.isNotEmpty()) result.add(text.take(300))
            }
        }
        return result
    }

    private fun label(packageName: String): String = try {
        val info = activity.packageManager.getApplicationInfo(packageName, 0)
        activity.packageManager.getApplicationLabel(info).toString().take(100)
    } catch (_: PackageManager.NameNotFoundException) {
        packageName
    }

    override fun showSession(title: String, body: String, stop: String, channel: String) =
        AlertNotifications.showSession(activity, title, body, stop, channel)

    override fun clearSession() = AlertNotifications.clearSession(activity)

    override fun showAlert(kind: String, title: String, body: String, channel: String) =
        AlertNotifications.showAlert(activity, kind, title, body, channel)

    override fun cancelAlert(kind: String) = AlertNotifications.cancelAlert(activity, kind)

    fun dispose() {
        worker.shutdownNow()
    }
}
