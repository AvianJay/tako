package tw.avianjay.tako

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings

/**
 * Screen control implemented by the accessibility service of the `full`
 * flavor. The `play` flavor has no backend, so every call reports unavailable.
 */
interface ScreenBackend {
    val screenshots: Boolean
    fun snapshot(screenshot: Boolean, maxNodes: Int, callback: (Result<ScreenSnapshotData>) -> Unit)
    fun resolveNode(token: Long, node: Int, callback: (Result<ScreenTargetData>) -> Unit)
    fun resolvePoint(x: Double, y: Double, callback: (Result<ScreenTargetData>) -> Unit)
    fun resolveFocus(callback: (Result<ScreenTargetData>) -> Unit)
    fun act(action: ScreenActionData, callback: (Result<ScreenActionResultData>) -> Unit)
    fun showApproval(data: ApprovalOverlayData, callback: (String?) -> Unit)
    fun hideApproval()
    fun showControlOverlay(data: ControlOverlayData)
    fun hideControlOverlay(sessionId: String, endSession: Boolean)
}

/** Bit flags of [ScreenNodeData.flags]; mirrored in lib/core/screen. */
object ScreenFlags {
    const val CLICKABLE = 1
    const val LONG_CLICKABLE = 2
    const val EDITABLE = 4
    const val SCROLLABLE = 8
    const val CHECKABLE = 16
    const val CHECKED = 32
    const val ENABLED = 64
    const val FOCUSED = 128
    const val SELECTED = 256
    const val PASSWORD = 512
    const val FOCUSABLE = 1024
    const val HEADING = 2048
    const val IME_ENTER = 4096
    const val MULTI_LINE = 8192
}

class ScreenApiHost(private val activity: Activity) : ScreenApi {
    private fun backend(): ScreenBackend? = ScreenControlFlavor.backend()

    private fun unavailable() = ControlError("screen_control_off", "screen_control_off", null)

    override fun status(): ScreenStatusData {
        val backend = backend()
        return ScreenStatusData(ScreenControlFlavor.SUPPORTED, backend != null, backend?.screenshots == true)
    }

    private fun start(intent: Intent) {
        try {
            activity.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            throw ControlError("unavailable", "unavailable", null)
        }
    }

    override fun openSettings() = start(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))

    override fun openAppInfo() = start(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null)),
    )

    override fun snapshot(screenshot: Boolean, maxNodes: Long, callback: (Result<ScreenSnapshotData>) -> Unit) {
        val backend = backend() ?: return callback(Result.failure(unavailable()))
        if (maxNodes !in 1..3000) return callback(Result.failure(ControlError("invalid_arguments", "invalid_arguments", null)))
        backend.snapshot(screenshot, maxNodes.toInt(), callback)
    }

    override fun resolveNode(token: Long, node: Long, callback: (Result<ScreenTargetData>) -> Unit) {
        val backend = backend() ?: return callback(Result.failure(unavailable()))
        if (node !in 0..100_000) return callback(Result.failure(ControlError("unknown_id", "unknown_id", null)))
        backend.resolveNode(token, node.toInt(), callback)
    }

    override fun resolvePoint(x: Double, y: Double, callback: (Result<ScreenTargetData>) -> Unit) {
        val backend = backend() ?: return callback(Result.failure(unavailable()))
        if (!x.isFinite() || !y.isFinite()) return callback(Result.failure(ControlError("invalid_arguments", "invalid_arguments", null)))
        backend.resolvePoint(x, y, callback)
    }

    override fun resolveFocus(callback: (Result<ScreenTargetData>) -> Unit) {
        val backend = backend() ?: return callback(Result.failure(unavailable()))
        backend.resolveFocus(callback)
    }

    override fun act(action: ScreenActionData, callback: (Result<ScreenActionResultData>) -> Unit) {
        val backend = backend() ?: return callback(Result.failure(unavailable()))
        backend.act(action, callback)
    }

    override fun showApproval(data: ApprovalOverlayData, callback: (Result<String?>) -> Unit) {
        val backend = backend() ?: return callback(Result.success(null))
        backend.showApproval(data) { callback(Result.success(it)) }
    }

    override fun hideApproval() {
        backend()?.hideApproval()
    }

    override fun showControlOverlay(data: ControlOverlayData) {
        backend()?.showControlOverlay(data)
    }

    override fun hideControlOverlay(sessionId: String, endSession: Boolean) {
        backend()?.hideControlOverlay(sessionId, endSession)
    }

    fun dispose() {
        hideApproval()
        backend()?.hideControlOverlay("", true)
    }
}
