package tw.avianjay.tako

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.OperationCanceledException
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.CalendarContract
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** No private information is read at construction or capability discovery. */
class AndroidDeviceApi(private val activity: Context) : DeviceApi {
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val operations = mutableMapOf<String, Pending<*>>()
    private val cancelledBeforeStart = linkedSetOf<String>()
    private var nextPermissionCode = 4000
    private var activePermissionCode: Int? = null
    private val permissions = mutableMapOf<Int, () -> Unit>()

    private class Pending<T>(val id: String, val callback: (Result<T>) -> Unit) {
        val cancelled = AtomicBoolean(false)
        val committing = AtomicBoolean(false)
        val signal = CancellationSignal()
        var cleanup: () -> Unit = {}
        var timeout: Runnable? = null
    }

    private fun error(code: String) = FlutterError(code, code, null)

    // Native exception messages can contain provider data or full URLs.
    private fun sanitized(cause: Throwable): FlutterError = when (cause) {
        is FlutterError -> cause
        is SecurityException -> error("permission_denied")
        is ActivityNotFoundException -> error("unavailable")
        is OperationCanceledException -> error("cancelled")
        is IllegalArgumentException -> error("invalid_arguments")
        else -> error("device_operation_failed")
    }

    private inline fun <T> safe(block: () -> T): T = try { block() } catch (cause: Throwable) {
        throw sanitized(cause)
    }

    private fun <T> begin(id: String, callback: (Result<T>) -> Unit): Pending<T> {
        if (id.length !in 1..100 || operations.containsKey(id)) throw error("invalid_arguments")
        if (cancelledBeforeStart.remove(id)) throw error("cancelled")
        val pending = Pending(id, callback)
        operations[id] = pending
        val timeout = Runnable {
            synchronized(pending) {
                if (!pending.committing.get()) finish(pending, Result.failure(error("timeout")))
            }
        }
        pending.timeout = timeout
        handler.postDelayed(timeout, 120_000)
        return pending
    }

    private fun <T> finish(pending: Pending<T>, result: Result<T>) {
        if (operations.remove(pending.id) !== pending) return
        pending.cancelled.set(true)
        try { pending.signal.cancel() } catch (_: Exception) { /* Already ended. */ }
        pending.timeout?.let(handler::removeCallbacks)
        try { pending.cleanup() } catch (_: Exception) { /* Already ended. */ }
        pending.callback(result)
    }

    private fun <T> withPermissions(pending: Pending<T>, required: Array<String>, any: Boolean = false, action: () -> Unit) {
        fun granted() = if (any) required.any { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
            else required.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        if (granted()) {
            try { action() } catch (cause: Throwable) { finish(pending, Result.failure(sanitized(cause))) }
            return
        }
        if (activity !is Activity) { finish(pending, Result.failure(error("foreground_required"))); return }
        // Android supports one foreground permission dialog at a time.
        if (activePermissionCode != null) {
            finish(pending, Result.failure(error("permission_request_busy")))
            return
        }
        val code = nextPermissionCode++
        activePermissionCode = code
        permissions[code] = {
            if (!pending.cancelled.get()) {
                if (!granted()) finish(pending, Result.failure(error("permission_denied")))
                else try { action() } catch (cause: Throwable) { finish(pending, Result.failure(sanitized(cause))) }
            }
        }
        val previousCleanup = pending.cleanup
        pending.cleanup = { previousCleanup(); permissions.remove(code) }
        try { activity.requestPermissions(required, code) }
        catch (cause: Throwable) {
            activePermissionCode = null
            finish(pending, Result.failure(sanitized(cause)))
        }
    }

    fun onPermissionResult(code: Int) {
        if (activePermissionCode == code) activePermissionCode = null
        permissions.remove(code)?.invoke()
    }

    override fun cancelOperation(operationId: String) {
        val pending = operations[operationId]
        if (pending == null) {
            // Different Pigeon channels may deliver cancellation before start.
            cancelledBeforeStart.add(operationId)
            if (cancelledBeforeStart.size > 128) cancelledBeforeStart.remove(cancelledBeforeStart.first())
            return
        }
        synchronized(pending) {
            // Provider inserts cannot be cancelled once submitted. Preserve the
            // eventual result so Dart can record the action in its audit log.
            if (!pending.committing.get()) finish(pending, Result.failure(error("cancelled")))
        }
    }

    fun dispose() {
        operations.keys.toList().forEach(::cancelOperation)
        permissions.clear()
        worker.shutdownNow()
    }

    override fun snapshot(): DeviceSnapshot = safe {
        val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percent = if (level >= 0 && scale > 0) 100L * level / scale else null
        val manager = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
        val network = when {
            capabilities == null -> "offline"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "connected"
        }
        DeviceSnapshot(Build.VERSION.RELEASE, Build.MODEL, percent, network)
    }

    override fun getLocation(operationId: String, callback: (Result<DeviceLocation>) -> Unit) {
        val pending = begin(operationId, callback)
        withPermissions(pending, arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION), any = true) {
            val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
                .filter { manager.allProviders.contains(it) && manager.isProviderEnabled(it) }
            if (providers.isEmpty()) throw error("location_unavailable")
            fun fresh(location: Location): Boolean {
                val age = SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos
                return age >= 0 && age <= 120_000_000_000L
            }
            fun deliver(location: Location?) {
                if (location != null && fresh(location)) finish(pending, Result.success(DeviceLocation(
                    location.latitude, location.longitude, location.accuracy.toDouble(), location.time)))
            }
            // Only after both the app's gate and the OS permission have succeeded.
            val cached = providers.mapNotNull { manager.getLastKnownLocation(it) }.filter(::fresh).maxByOrNull { it.elapsedRealtimeNanos }
            if (cached != null) { deliver(cached); return@withPermissions }
            pending.timeout?.let(handler::removeCallbacks)
            pending.timeout = Runnable { finish(pending, Result.failure(error("location_timeout"))) }
            handler.postDelayed(pending.timeout!!, 20_000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val signals = mutableListOf<CancellationSignal>()
                val previousCleanup = pending.cleanup
                pending.cleanup = { previousCleanup(); signals.forEach { it.cancel() } }
                providers.forEach { provider ->
                    val signal = CancellationSignal()
                    signals.add(signal)
                    manager.getCurrentLocation(provider, signal, activity.mainExecutor, ::deliver)
                }
            } else {
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) { deliver(location) }
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                    @Deprecated("Required for pre-30 Android")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                }
                val previousCleanup = pending.cleanup
                pending.cleanup = { previousCleanup(); manager.removeUpdates(listener) }
                @Suppress("DEPRECATION")
                providers.forEach { manager.requestSingleUpdate(it, listener, Looper.getMainLooper()) }
            }
        }
    }

    override fun clipboardRead(): String? = safe {
        if ((activity as? Activity)?.hasWindowFocus() != true) throw error("foreground_required")
        val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip ?: return@safe null
        if (clip.itemCount == 0) return@safe null
        // Do not coerce URI clipboard items: that could read an unrelated file.
        clip.getItemAt(0).text?.take(6000)?.toString()
    }

    override fun clipboardWrite(text: String) = safe {
        if (text.length > 100_000) throw error("invalid_arguments")
        val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Tako", text))
    }

    private fun validRange(start: Long, end: Long) {
        if (start < 0 || end <= start || end - start > 366L * 86_400_000) throw error("invalid_arguments")
    }

    override fun calendarList(operationId: String, startMillis: Long, endMillis: Long, limit: Long, callback: (Result<DeviceCalendarListing>) -> Unit) {
        val pending = begin(operationId, callback)
        try { validRange(startMillis, endMillis); if (limit !in 1..100) throw error("invalid_arguments") }
        catch (cause: Throwable) { finish(pending, Result.failure(sanitized(cause))); return }
        withPermissions(pending, arrayOf(Manifest.permission.READ_CALENDAR)) {
            worker.execute {
                val result = runCatching {
                    pending.signal.throwIfCanceled()
                    val resolver = activity.contentResolver
                    val calendars = mutableListOf<DeviceCalendar>()
                    var truncated = false
                    resolver.query(CalendarContract.Calendars.CONTENT_URI,
                        arrayOf("_id", "calendar_displayName", "calendar_access_level"),
                        "visible = 1", null, "_id ASC", pending.signal)?.use { cursor ->
                        while (cursor.moveToNext()) {
                            pending.signal.throwIfCanceled()
                            if (calendars.size == 30) { truncated = true; break }
                            calendars.add(DeviceCalendar(cursor.getLong(0), cursor.getString(1).orEmpty().take(200),
                                cursor.getInt(2) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR))
                        }
                    } ?: throw error("calendar_unavailable")
                    val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
                    ContentUris.appendId(uri, startMillis)
                    ContentUris.appendId(uri, endMillis)
                    val events = mutableListOf<DeviceCalendarEvent>()
                    resolver.query(uri.build(), arrayOf("event_id", "calendar_id", "title", "begin", "end", "allDay", "eventLocation"),
                        "visible = 1", null, "begin ASC", pending.signal)?.use { cursor ->
                        while (cursor.moveToNext()) {
                            pending.signal.throwIfCanceled()
                            if (events.size >= limit) { truncated = true; break }
                            events.add(DeviceCalendarEvent(cursor.getLong(0), cursor.getLong(1), cursor.getString(2).orEmpty().take(500),
                                cursor.getLong(3), cursor.getLong(4), cursor.getInt(5) != 0, cursor.getString(6)?.take(500)))
                        }
                    } ?: throw error("calendar_unavailable")
                    DeviceCalendarListing(calendars, events, truncated)
                }.recoverCatching { throw sanitized(it) }
                handler.post { finish(pending, result) }
            }
        }
    }

    override fun calendarAdd(operationId: String, draft: DeviceEventDraft, callback: (Result<Long>) -> Unit) {
        val pending = begin(operationId, callback)
        try {
            validRange(draft.startMillis, draft.endMillis)
            if (draft.calendarId <= 0 || draft.title.isBlank() || draft.title.length > 500 ||
                (draft.notes?.length ?: 0) > 4000 || (draft.location?.length ?: 0) > 500) throw error("invalid_arguments")
        } catch (cause: Throwable) { finish(pending, Result.failure(sanitized(cause))); return }
        withPermissions(pending, arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)) {
            worker.execute {
                val result = runCatching {
                    val resolver = activity.contentResolver
                    pending.signal.throwIfCanceled()
                    val writable = resolver.query(CalendarContract.Calendars.CONTENT_URI, arrayOf("_id"),
                        "_id = ? AND calendar_access_level >= ?", arrayOf(draft.calendarId.toString(),
                            CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString()), null, pending.signal)?.use { it.moveToFirst() } ?: false
                    if (!writable) throw error("calendar_not_writable")
                    val values = ContentValues().apply {
                        put(CalendarContract.Events.CALENDAR_ID, draft.calendarId)
                        put(CalendarContract.Events.TITLE, draft.title)
                        put(CalendarContract.Events.DTSTART, draft.startMillis)
                        put(CalendarContract.Events.DTEND, draft.endMillis)
                        put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                        put(CalendarContract.Events.DESCRIPTION, draft.notes)
                        put(CalendarContract.Events.EVENT_LOCATION, draft.location)
                    }
                    synchronized(pending) {
                        pending.signal.throwIfCanceled()
                        pending.committing.set(true)
                    }
                    // Once submitted, Android's provider insert cannot be rolled back by Stop.
                    val uri = resolver.insert(CalendarContract.Events.CONTENT_URI, values) ?: throw error("calendar_unavailable")
                    ContentUris.parseId(uri)
                }.recoverCatching { throw sanitized(it) }
                handler.post { finish(pending, result) }
            }
        }
    }

    private fun launch(intent: Intent): DeviceLaunchResult = safe {
        if (activity !is Activity) throw error("foreground_required")
        activity.startActivity(intent)
        // Launching does not prove the user completed the external action.
        DeviceLaunchResult(true)
    }

    override fun setAlarm(hour: Long, minute: Long, label: String?): DeviceLaunchResult {
        if (hour !in 0..23 || minute !in 0..59 || (label?.length ?: 0) > 200) throw error("invalid_arguments")
        return launch(Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour.toInt())
            putExtra(AlarmClock.EXTRA_MINUTES, minute.toInt())
            putExtra(AlarmClock.EXTRA_MESSAGE, label.orEmpty())
            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
        })
    }

    override fun setTimer(seconds: Long, label: String?): DeviceLaunchResult {
        if (seconds !in 1..86_400 || (label?.length ?: 0) > 200) throw error("invalid_arguments")
        return launch(Intent(AlarmClock.ACTION_SET_TIMER).apply {
            putExtra(AlarmClock.EXTRA_LENGTH, seconds.toInt())
            putExtra(AlarmClock.EXTRA_MESSAGE, label.orEmpty())
            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
        })
    }

    override fun openUrl(url: String): DeviceLaunchResult {
        val uri = Uri.parse(url)
        if (url.length > 8192 || uri.scheme !in setOf("https", "http") || uri.host.isNullOrBlank() ||
            uri.userInfo != null || url.any { it.code <= 32 }) throw error("invalid_arguments")
        return launch(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
    }

    override fun openApp(packageName: String): DeviceLaunchResult = safe {
        if (packageName.length > 255 || !Regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+").matches(packageName)) throw error("invalid_arguments")
        val intent = activity.packageManager.getLaunchIntentForPackage(packageName) ?: throw error("app_not_found")
        launch(intent)
    }

    override fun listApps(): List<DeviceAppEntry> = safe {
        val manager = activity.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        manager.queryIntentActivities(launcher, 0)
            .map { DeviceAppEntry(it.loadLabel(manager).toString().take(100), it.activityInfo.packageName) }
            .filter { it.packageName != activity.packageName }
            .distinctBy { it.packageName }
            .take(500)
    }
}
