package tw.avianjay.tako

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.security.SecureRandom
import java.util.UUID

/** Routes Termux results to the waiting call. Results need the call's nonce. */
object ShellResults {
    private val waiting = mutableMapOf<Int, Pair<String, (Bundle) -> Unit>>()

    @Synchronized
    fun register(id: Int, nonce: String, deliver: (Bundle) -> Unit) {
        waiting[id] = nonce to deliver
    }

    @Synchronized
    fun unregister(id: Int) {
        waiting.remove(id)
    }

    fun deliver(id: Int, nonce: String?, result: Bundle) {
        val deliver = synchronized(this) {
            val entry = waiting[id]
            if (entry == null || entry.first != nonce) return
            waiting.remove(id)
            entry.second
        }
        deliver(result)
    }
}

/** Receives the RUN_COMMAND result PendingIntent. Not exported. */
class ShellResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(ShellApiHost.EXTRA_EXECUTION, 0)
        val nonce = intent.getStringExtra(ShellApiHost.EXTRA_NONCE)
        ShellResults.deliver(id, nonce, intent.getBundleExtra("result") ?: Bundle())
    }
}

/**
 * run_shell through Termux's RUN_COMMAND service. Termux runs the command as
 * its own user; Tako only sends the command after the app's permission gate.
 */
class ShellApiHost(
    private val activity: Activity,
    private val permissions: PermissionBroker,
) : ShellApi {
    companion object {
        const val EXTRA_EXECUTION = "tw.avianjay.tako.extra.EXECUTION"
        const val EXTRA_NONCE = "tw.avianjay.tako.extra.NONCE"
        private const val TERMUX = "com.termux"
        private const val PERMISSION = "com.termux.permission.RUN_COMMAND"
        private const val SERVICE = "com.termux.app.RunCommandService"
        private const val BASH = "/data/data/com.termux/files/usr/bin/bash"
        private const val HOME = "/data/data/com.termux/files/home"
        private const val MAX_OUTPUT = 64_000
    }

    private val main = Handler(Looper.getMainLooper())
    private val random = SecureRandom()

    private class Pending(
        val execution: Int,
        val callback: (Result<ShellResultData>) -> Unit,
    ) {
        var timeout: Runnable? = null
    }

    private val running = mutableMapOf<String, Pending>()
    private val cancelledBeforeStart = linkedSetOf<String>()

    private fun error(code: String) = ControlError(code, code, null)

    private fun installed() = try {
        activity.packageManager.getPackageInfo(TERMUX, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    override fun status() = ShellStatusData(installed(), installed() && permissions.granted(PERMISSION))

    override fun requestPermission(callback: (Result<Boolean>) -> Unit) {
        if (!installed()) {
            callback(Result.success(false))
            return
        }
        permissions.request(PERMISSION) { callback(Result.success(it)) }
    }

    override fun openTermux(): Boolean {
        val intent = activity.packageManager.getLaunchIntentForPackage(TERMUX) ?: return false
        activity.startActivity(intent)
        return true
    }

    override fun run(operationId: String, command: String, timeoutMillis: Long, callback: (Result<ShellResultData>) -> Unit) {
        if (operationId.length !in 1..100 || running.containsKey(operationId) || command.isBlank() ||
            command.length > 16_000 || timeoutMillis !in 1_000..600_000) {
            callback(Result.failure(error("invalid_arguments")))
            return
        }
        if (cancelledBeforeStart.remove(operationId)) {
            callback(Result.failure(error("cancelled")))
            return
        }
        if (!installed()) {
            callback(Result.failure(error("termux_not_installed")))
            return
        }
        if (!permissions.granted(PERMISSION)) {
            callback(Result.failure(error("permission_denied")))
            return
        }
        var execution: Int
        do { execution = random.nextInt(Int.MAX_VALUE - 1) + 1 } while (running.values.any { it.execution == execution })
        val nonce = UUID.randomUUID().toString()
        val pending = Pending(execution, callback)
        running[operationId] = pending
        ShellResults.register(execution, nonce) { bundle -> finish(operationId, pending, parse(bundle)) }
        val resultIntent = Intent(activity, ShellResultReceiver::class.java)
            .putExtra(EXTRA_EXECUTION, execution)
            .putExtra(EXTRA_NONCE, nonce)
        // Mutable so Termux can attach the result; the component stays fixed.
        val flags = PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_CANCEL_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        val resultPending = PendingIntent.getBroadcast(activity, execution, resultIntent, flags)
        val intent = Intent("com.termux.RUN_COMMAND")
            .setClassName(TERMUX, SERVICE)
            .putExtra("com.termux.RUN_COMMAND_PATH", BASH)
            .putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", command))
            .putExtra("com.termux.RUN_COMMAND_WORKDIR", HOME)
            .putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            .putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", "Tako run_shell")
            .putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", resultPending)
        val timeout = Runnable { finish(operationId, pending, Result.failure(error("timeout"))) }
        pending.timeout = timeout
        main.postDelayed(timeout, timeoutMillis)
        try {
            // Termux targets an SDK below the foreground-service start limits and
            // calls startForeground itself, so this works while Tako is hidden.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity.startForegroundService(intent)
            else activity.startService(intent)
        } catch (_: SecurityException) {
            finish(operationId, pending, Result.failure(error("permission_denied")))
        } catch (_: Exception) {
            finish(operationId, pending, Result.failure(error("termux_unavailable")))
        }
    }

    private fun finish(operationId: String, pending: Pending, result: Result<ShellResultData>) {
        if (running[operationId] !== pending) return
        running.remove(operationId)
        pending.timeout?.let(main::removeCallbacks)
        ShellResults.unregister(pending.execution)
        pending.callback(result)
    }

    @Suppress("DEPRECATION") // Bundle.get: Termux has sent lengths as both types.
    private fun parse(bundle: Bundle): Result<ShellResultData> {
        fun string(key: String) = bundle.getString(key).orEmpty()
        fun length(key: String, fallback: Int): Long = when (val value = bundle.get(key)) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: fallback.toLong()
            else -> fallback.toLong()
        }
        val stdout = string("stdout")
        val stderr = string("stderr")
        val err = bundle.getInt("err", -1)
        val message = string("errmsg")
        if (err != -1) {
            // Termux reports setup problems here, e.g. allow-external-apps.
            val code = if (message.contains("allow-external-apps")) "termux_external_apps_disabled" else "termux_error"
            return Result.success(ShellResultData(-1, "", "", 0, 0, code, message.take(500)))
        }
        return Result.success(ShellResultData(
            exitCode = bundle.getInt("exitCode", -1).toLong(),
            stdout = stdout.takeLast(MAX_OUTPUT),
            stderr = stderr.takeLast(MAX_OUTPUT),
            stdoutLength = length("stdout_original_length", stdout.length),
            stderrLength = length("stderr_original_length", stderr.length),
        ))
    }

    override fun cancel(operationId: String) {
        val pending = running[operationId]
        if (pending == null) {
            cancelledBeforeStart.add(operationId)
            if (cancelledBeforeStart.size > 64) cancelledBeforeStart.remove(cancelledBeforeStart.first())
            return
        }
        // Termux has no cancel API; the command may keep running.
        finish(operationId, pending, Result.failure(error("cancelled")))
    }

    fun dispose() {
        running.keys.toList().forEach(::cancel)
    }
}
