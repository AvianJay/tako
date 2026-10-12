package tw.avianjay.tako

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * The app's own notifications. Texts and channel names come from Dart, so
 * they follow the in-app language. Nothing here contains message content.
 */
object AlertNotifications {
    const val ACTION_STOP = "tw.avianjay.tako.action.STOP"
    private const val SESSION_CHANNEL = "screen_session"
    private const val ALERT_CHANNEL = "assistant_alerts"
    private const val SESSION_ID = 4101
    private const val APPROVAL_ID = 4102
    private const val REPLY_ID = 4103

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun channel(context: Context, id: String, name: String, importance: Int, silent: Boolean = false) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Re-creating an existing channel only updates its name.
        val channel = NotificationChannel(id, name.take(80), importance)
        if (silent) {
            channel.setSound(null, null)
            channel.enableVibration(false)
        }
        manager(context).createNotificationChannel(channel)
    }

    private fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, channel)
        else @Suppress("DEPRECATION") Notification.Builder(context)

    private fun openApp(context: Context): PendingIntent? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    fun showSession(context: Context, title: String, body: String, stop: String, channelName: String) {
        // Default importance keeps Stop visible in the shade; the channel is silent.
        channel(context, SESSION_CHANNEL, channelName, NotificationManager.IMPORTANCE_DEFAULT, silent = true)
        val stopIntent = PendingIntent.getBroadcast(context, 1,
            Intent(context, ControlActionReceiver::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = builder(context, SESSION_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_tako)
            .setContentTitle(title.take(120))
            .setContentText(body.take(240))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setContentIntent(openApp(context))
            .addAction(Notification.Action.Builder(null, stop.take(40), stopIntent).build())
            .build()
        try {
            manager(context).notify(SESSION_ID, notification)
        } catch (_: SecurityException) {
            // Notifications were not allowed; the in-app setup screen says so.
        }
    }

    fun clearSession(context: Context) {
        manager(context).cancel(SESSION_ID)
    }

    fun showAlert(context: Context, kind: String, title: String, body: String, channelName: String) {
        val id = idFor(kind) ?: return
        channel(context, ALERT_CHANNEL, channelName, NotificationManager.IMPORTANCE_HIGH)
        val notification = builder(context, ALERT_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_tako)
            .setContentTitle(title.take(120))
            .setContentText(body.take(240))
            .setAutoCancel(true)
            .setCategory(if (kind == "approval") Notification.CATEGORY_REMINDER else Notification.CATEGORY_STATUS)
            .setContentIntent(openApp(context))
            .apply {
                @Suppress("DEPRECATION")
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) setPriority(Notification.PRIORITY_HIGH)
            }
            .build()
        try {
            manager(context).notify(id, notification)
        } catch (_: SecurityException) {
            // Notifications were not allowed.
        }
    }

    fun cancelAlert(context: Context, kind: String) {
        idFor(kind)?.let { manager(context).cancel(it) }
    }

    private fun idFor(kind: String) = when (kind) {
        "approval" -> APPROVAL_ID
        "reply" -> REPLY_ID
        else -> null
    }
}
