package tw.avianjay.tako

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.util.DisplayMetrics
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction
import android.view.accessibility.AccessibilityWindowInfo
import androidx.annotation.RequiresApi
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Screen control. Enabled only by the user in system settings. Window content
 * is read only when a screen tool runs; events are used only to wait for the
 * screen to settle, and their content is ignored.
 */
class TakoAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile
        var instance: TakoAccessibilityService? = null
            private set
    }

    @Volatile
    internal var reader: ScreenReader? = null
        private set

    @Volatile
    internal var lastEventAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        reader = ScreenReader(this)
        instance = this
        ControlSignals.statusChanged()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Tako's own windows (the approval prompt) do not count as a change.
        if (event?.packageName?.toString() == packageName) return
        lastEventAt = SystemClock.uptimeMillis()
    }

    override fun onInterrupt() {}

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        reader?.configurationChanged()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        shutdown()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }

    private fun shutdown() {
        if (instance !== this) return
        instance = null
        reader?.dispose()
        reader = null
        ControlSignals.statusChanged()
    }
}

/**
 * Snapshots, trusted target resolution and actions. Node work runs in order
 * on one background thread; replies and window changes happen on main.
 * Tako's own windows are never read or acted on, and nothing is done while
 * an approval is on screen.
 */
internal class ScreenReader(private val service: TakoAccessibilityService) : ScreenBackend {
    private companion object {
        const val MAX_DEPTH = 80
        const val SUBTREE_LIMIT = 200
        const val IDENTITY_FLAGS = ScreenFlags.CLICKABLE or ScreenFlags.EDITABLE or
            ScreenFlags.PASSWORD or ScreenFlags.CHECKABLE
        val SEPARATOR = Char(31)
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val imageWorker = Executors.newSingleThreadExecutor()
    private val overlay = ApprovalOverlay(service)
    private val controlOverlay = ControlOverlay(service)
    private val labels = mutableMapOf<String, String>()

    // Worker thread only.
    private var token = 0L
    private var nodes: List<AccessibilityNodeInfo> = emptyList()

    override val screenshots get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    private fun error(code: String) = ControlError(code, code, null)

    private fun <T> work(callback: (Result<T>) -> Unit, block: () -> T) {
        try {
            worker.execute {
                val result = try {
                    Result.success(block())
                } catch (cause: ControlError) {
                    Result.failure(cause)
                } catch (_: Throwable) {
                    // Never return node text or stack traces from a failure.
                    Result.failure(error("screen_failed"))
                }
                main.post { callback(result) }
            }
        } catch (_: RejectedExecutionException) {
            callback(Result.failure(error("screen_control_off")))
        }
    }

    fun dispose() {
        overlay.hide()
        controlOverlay.hide("", true)
        worker.shutdownNow()
        imageWorker.shutdownNow()
    }

    fun configurationChanged() = controlOverlay.refresh()

    private fun hideControlForOperation(screenshot: Boolean): Boolean {
        val ready = CountDownLatch(1)
        controlOverlay.hideForOperation(screenshot) { ready.countDown() }
        return ready.await(750, TimeUnit.MILLISECONDS)
    }

    /**
     * An approval answered in the app hides the prompt asynchronously; wait
     * for it to go rather than act under it. Worker thread only.
     */
    private fun ensureNoApproval() {
        val deadline = SystemClock.uptimeMillis() + 1500
        while (overlay.visible) {
            if (SystemClock.uptimeMillis() >= deadline) throw error("approval_pending")
            Thread.sleep(20)
        }
    }

    // ---- Reading ----

    private class Raw(
        val node: AccessibilityNodeInfo,
        val parent: Int,
        val window: Int,
        val className: String,
        val text: String?,
        val description: String?,
        val hint: String?,
        val viewId: String?,
        val state: String?,
        val flags: Int,
        val bounds: Rect,
    )

    private fun clean(value: CharSequence?, max: Int): String? {
        if (value == null) return null
        val text = buildString(min(value.length, max + 16)) {
            for (char in value) {
                if (length >= max) break
                append(if (char.code < 32) ' ' else char)
            }
        }.split(' ').filter { it.isNotEmpty() }.joinToString(" ")
        return text.ifEmpty { null }
    }

    private fun isPassword(node: AccessibilityNodeInfo): Boolean {
        if (node.isPassword) return true
        val type = node.inputType
        val variation = type and InputType.TYPE_MASK_VARIATION
        return when (type and InputType.TYPE_MASK_CLASS) {
            InputType.TYPE_CLASS_TEXT -> variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
            InputType.TYPE_CLASS_NUMBER -> variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
            else -> false
        }
    }

    @Suppress("DEPRECATION") // isChecked: getChecked() needs API 36.
    private fun flags(node: AccessibilityNodeInfo): Int {
        var flags = 0
        if (node.isClickable) flags = flags or ScreenFlags.CLICKABLE
        if (node.isLongClickable) flags = flags or ScreenFlags.LONG_CLICKABLE
        if (node.isEditable) flags = flags or ScreenFlags.EDITABLE
        if (node.isScrollable) flags = flags or ScreenFlags.SCROLLABLE
        if (node.isCheckable) flags = flags or ScreenFlags.CHECKABLE
        if (node.isChecked) flags = flags or ScreenFlags.CHECKED
        if (node.isEnabled) flags = flags or ScreenFlags.ENABLED
        if (node.isFocused) flags = flags or ScreenFlags.FOCUSED
        if (node.isSelected) flags = flags or ScreenFlags.SELECTED
        if (isPassword(node)) flags = flags or ScreenFlags.PASSWORD
        if (node.isFocusable) flags = flags or ScreenFlags.FOCUSABLE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && node.isHeading) flags = flags or ScreenFlags.HEADING
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            node.actionList.any { it.id == AccessibilityAction.ACTION_IME_ENTER.id }) {
            flags = flags or ScreenFlags.IME_ENTER
        }
        if (node.isMultiLine) flags = flags or ScreenFlags.MULTI_LINE
        return flags
    }

    private fun raw(node: AccessibilityNodeInfo, parent: Int, window: Int): Raw {
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        return Raw(
            node = node,
            parent = parent,
            window = window,
            className = node.className?.toString()?.take(100).orEmpty(),
            text = clean(node.text, 500),
            description = clean(node.contentDescription, 300),
            hint = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) clean(node.hintText, 200) else null,
            viewId = node.viewIdResourceName?.take(150),
            state = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) clean(node.stateDescription, 100) else null,
            flags = flags(node),
            bounds = bounds,
        )
    }

    /** Visible nodes under [root] in preorder, so each subtree is contiguous. */
    private fun collect(root: AccessibilityNodeInfo, window: Int, into: MutableList<Raw>, limit: Int): Boolean {
        val stack = ArrayDeque<Triple<AccessibilityNodeInfo, Int, Int>>()
        stack.addLast(Triple(root, -1, 0))
        while (stack.isNotEmpty()) {
            val (node, parent, depth) = stack.removeLast()
            if (!node.isVisibleToUser) continue
            if (into.size >= limit) return false
            val index = into.size
            into.add(raw(node, parent, window))
            if (depth < MAX_DEPTH) {
                for (child in node.childCount - 1 downTo 0) {
                    node.getChild(child)?.let { stack.addLast(Triple(it, index, depth + 1)) }
                }
            }
        }
        return true
    }

    /**
     * A node's identity: its own properties and the first texts of its
     * subtree. Bounds and transient state are excluded, so scrolling or focus
     * does not invalidate an approval, but recycled or relabelled views do.
     */
    private fun checks(raws: List<Raw>): List<String> {
        val end = IntArray(raws.size) { it }
        for (index in raws.indices.reversed()) {
            val parent = raws[index].parent
            if (parent >= 0 && end[index] > end[parent]) end[parent] = end[index]
        }
        return raws.indices.map { index ->
            val raw = raws[index]
            val text = StringBuilder()
            for (part in listOf(raw.className, raw.viewId, raw.text, raw.description, raw.hint)) {
                text.append(part).append(SEPARATOR)
            }
            text.append(raw.flags and IDENTITY_FLAGS)
            var count = 0
            for (child in index + 1..min(end[index], index + SUBTREE_LIMIT - 1)) {
                val label = raws[child].text ?: raws[child].description ?: continue
                text.append(SEPARATOR).append(label.take(80))
                if (++count >= 30 || text.length > 2000) break
            }
            val digest = MessageDigest.getInstance("SHA-256").digest(text.toString().toByteArray(Charsets.UTF_8))
            digest.take(8).joinToString("") { "%02x".format(it) }
        }
    }

    private fun check(node: AccessibilityNodeInfo): String {
        val subtree = mutableListOf<Raw>()
        collect(node, 0, subtree, SUBTREE_LIMIT)
        return checks(subtree).firstOrNull().orEmpty()
    }

    private fun data(raw: Raw, check: String) = ScreenNodeData(
        parent = raw.parent.toLong(),
        window = raw.window.toLong(),
        className = raw.className,
        text = raw.text,
        description = raw.description,
        hint = raw.hint,
        viewId = raw.viewId,
        state = raw.state,
        flags = raw.flags.toLong(),
        left = raw.bounds.left.toLong(),
        top = raw.bounds.top.toLong(),
        right = raw.bounds.right.toLong(),
        bottom = raw.bounds.bottom.toLong(),
        check = check,
    )

    private fun screenSize(): Pair<Int, Int> {
        val display = service.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        display.getRealMetrics(metrics)
        return metrics.widthPixels to metrics.heightPixels
    }

    private fun label(packageName: String): String = labels.getOrPut(packageName) {
        try {
            val manager = service.packageManager
            manager.getApplicationLabel(manager.getApplicationInfo(packageName, 0)).toString().take(100)
        } catch (_: PackageManager.NameNotFoundException) {
            packageName
        }
    }

    private fun isIgnoredType(type: Int) = type == AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY ||
        type == AccessibilityWindowInfo.TYPE_INPUT_METHOD ||
        type == AccessibilityWindowInfo.TYPE_SPLIT_SCREEN_DIVIDER ||
        (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && type == AccessibilityWindowInfo.TYPE_MAGNIFICATION_OVERLAY)

    private fun windowData(window: AccessibilityWindowInfo, packageName: String): ScreenWindowData {
        val bounds = Rect()
        window.getBoundsInScreen(bounds)
        return ScreenWindowData(
            id = window.id.toLong(),
            packageName = packageName,
            title = clean(window.title, 200),
            type = window.type.toLong(),
            own = packageName == service.packageName,
            left = bounds.left.toLong(),
            top = bounds.top.toLong(),
            right = bounds.right.toLong(),
            bottom = bounds.bottom.toLong(),
        )
    }

    private fun windowsByLayer() = service.windows.sortedByDescending { it.layer }

    /** The front application window's package and label. */
    private fun frontApp(): Pair<String, String>? {
        val window = windowsByLayer().firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION } ?: return null
        val packageName = window.root?.packageName?.toString() ?: return null
        return packageName to label(packageName)
    }

    /** Waits for the first window event after [since], up to [limit] ms. */
    private fun awaitChange(since: Long, limit: Long) {
        val deadline = SystemClock.uptimeMillis() + limit
        while (service.lastEventAt <= since && SystemClock.uptimeMillis() < deadline) Thread.sleep(20)
    }

    private fun awaitQuiet(quiet: Long, limit: Long) {
        val deadline = SystemClock.uptimeMillis() + limit
        while (true) {
            val now = SystemClock.uptimeMillis()
            val idle = now - service.lastEventAt
            if (idle >= quiet || now >= deadline) return
            Thread.sleep(min(quiet - idle, deadline - now).coerceAtLeast(10))
        }
    }

    override fun snapshot(screenshot: Boolean, maxNodes: Int, callback: (Result<ScreenSnapshotData>) -> Unit) = work(callback) {
        ensureNoApproval()
        awaitQuiet(300, 1500)
        // During a transition the next window may not have content yet.
        val readyBy = SystemClock.uptimeMillis() + 1200
        while (SystemClock.uptimeMillis() < readyBy &&
            windowsByLayer().none { it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.root != null }) {
            Thread.sleep(100)
        }
        val image = if (screenshot && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) capture() else null
        val (width, height) = screenSize()
        val screenArea = width.toLong() * height
        val windows = mutableListOf<ScreenWindowData>()
        val raws = mutableListOf<Raw>()
        var front: String? = null
        var ownInFront = false
        var complete = true
        for (window in windowsByLayer()) {
            if (isIgnoredType(window.type)) continue
            val root = window.root ?: continue
            val packageName = root.packageName?.toString() ?: continue
            val own = packageName == service.packageName
            if (window.type == AccessibilityWindowInfo.TYPE_APPLICATION && front == null) {
                front = packageName
                ownInFront = own
            }
            if (own || !complete) continue
            val bounds = Rect()
            window.getBoundsInScreen(bounds)
            // Status and navigation bars are noise; an expanded shade is not.
            if (window.type == AccessibilityWindowInfo.TYPE_SYSTEM &&
                bounds.width().toLong() * bounds.height() < screenArea / 2) continue
            windows.add(windowData(window, packageName))
            complete = collect(root, windows.lastIndex, raws, maxNodes)
        }
        val checks = checks(raws)
        token += 1
        nodes = raws.map { it.node }
        ScreenSnapshotData(
            token = token,
            packageName = front.orEmpty(),
            appLabel = front?.let(::label).orEmpty(),
            width = width.toLong(),
            height = height.toLong(),
            ownAppInFront = ownInFront,
            windows = windows,
            nodes = raws.mapIndexed { index, raw -> data(raw, checks[index]) },
            truncated = !complete,
            image = image?.bytes,
            imageWidth = (image?.width ?: 0).toLong(),
            imageHeight = (image?.height ?: 0).toLong(),
        )
    }

    private class Capture(val bytes: ByteArray, val width: Int, val height: Int)

    @RequiresApi(Build.VERSION_CODES.R)
    private fun capture(): Capture? {
        try {
            if (!hideControlForOperation(true)) return null
            // Keep the full-display geometry on every supported Android version.
            // Neither our frame nor status should become model-visible content.
            return captureScreen()
        } finally {
            controlOverlay.restoreAfterOperation(true)
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun captureScreen(): Capture? {
        val done = CountDownLatch(1)
        val result = AtomicReference<Capture?>(null)
        service.takeScreenshot(Display.DEFAULT_DISPLAY, imageWorker, object : AccessibilityService.TakeScreenshotCallback {
            override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                try {
                    val buffer = screenshot.hardwareBuffer
                    val hardware = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
                    val bitmap = hardware?.copy(Bitmap.Config.ARGB_8888, false)
                    hardware?.recycle()
                    buffer.close()
                    if (bitmap != null) {
                        // Vision models see at most 1568 px on the long edge.
                        val scale = min(1f, 1568f / max(bitmap.width, bitmap.height))
                        val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bitmap,
                            (bitmap.width * scale).roundToInt(), (bitmap.height * scale).roundToInt(), true) else bitmap
                        val bytes = ByteArrayOutputStream()
                        scaled.compress(Bitmap.CompressFormat.JPEG, 80, bytes)
                        result.set(Capture(bytes.toByteArray(), scaled.width, scaled.height))
                        if (scaled !== bitmap) scaled.recycle()
                        bitmap.recycle()
                    }
                } catch (_: Throwable) {
                    // Secure windows and transient failures leave no screenshot.
                } finally {
                    done.countDown()
                }
            }

            override fun onFailure(errorCode: Int) {
                done.countDown()
            }
        })
        done.await(4, TimeUnit.SECONDS)
        return result.get()
    }

    // ---- Targets ----

    private fun liveNode(token: Long, index: Int): AccessibilityNodeInfo {
        if (token != this.token) throw error("stale_ids_read_again")
        val node = nodes.getOrNull(index) ?: throw error("unknown_id")
        if (!node.refresh()) throw error("element_gone_read_again")
        if (!node.isVisibleToUser) throw error("element_not_visible_read_again")
        if (node.packageName?.toString() == service.packageName) throw error("own_app")
        return node
    }

    private fun describe(target: AccessibilityNodeInfo?, window: AccessibilityWindowInfo, token: Long, index: Int): ScreenTargetData {
        val (width, height) = screenSize()
        val packageName = window.root?.packageName?.toString() ?: target?.packageName?.toString().orEmpty()
        if (packageName == service.packageName) throw error("own_app")
        val subtree = mutableListOf<Raw>()
        if (target != null) collect(target, 0, subtree, SUBTREE_LIMIT)
        val checks = checks(subtree)
        val ancestors = mutableListOf<ScreenNodeData>()
        var parent = target?.parent
        while (parent != null && ancestors.size < 12) {
            ancestors.add(data(raw(parent, -1, 0), ""))
            parent = parent.parent
        }
        // A tap on a child reaches its clickable ancestor; keyword checks need
        // that ancestor's text too (an icon inside a "Send" button).
        val actionNode = target?.let { node -> ancestorOrSelf(node, 8) { it.isClickable || it.isLongClickable } }
        val actionText = if (actionNode != null && actionNode != target) {
            val raws = mutableListOf<Raw>()
            collect(actionNode, 0, raws, 120)
            raws.mapNotNull { it.text ?: it.description }.joinToString(" ").take(600)
        } else ""
        val windowInfo = windowData(window, packageName)
        // Only small windows (dialogs) need their text: an "OK" there may
        // confirm a deletion described above it.
        val area = (windowInfo.right - windowInfo.left) * (windowInfo.bottom - windowInfo.top)
        val windowText = if (area < width.toLong() * height * 9 / 10) {
            window.root?.let { root ->
                val raws = mutableListOf<Raw>()
                collect(root, 0, raws, 120)
                raws.mapNotNull { it.text ?: it.description }.joinToString(" ").take(600)
            }.orEmpty()
        } else ""
        return ScreenTargetData(
            token = token,
            node = index.toLong(),
            window = windowInfo,
            appLabel = label(packageName),
            target = subtree.firstOrNull()?.let { data(it, checks[0]) },
            ancestors = ancestors,
            descendants = subtree.drop(1).mapIndexed { offset, raw -> data(raw, checks[offset + 1]) },
            actionText = actionText,
            windowText = windowText,
            width = width.toLong(),
            height = height.toLong(),
        )
    }

    override fun resolveNode(token: Long, node: Int, callback: (Result<ScreenTargetData>) -> Unit) = work(callback) {
        ensureNoApproval()
        val target = liveNode(token, node)
        val window = target.window ?: throw error("element_gone_read_again")
        describe(target, window, token, node)
    }

    /** The front window at a point; never the keyboard or an overlay. */
    private fun windowAt(x: Int, y: Int): AccessibilityWindowInfo {
        val bounds = Rect()
        val window = windowsByLayer().firstOrNull {
            it.getBoundsInScreen(bounds)
            // Only our status/frame and a just-removed approval may be skipped.
            // Other services' overlays continue to block the point.
            bounds.contains(x, y) && !controlOverlay.owns(it) &&
                !(it.type == AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY &&
                    !overlay.visible && (it.id == overlay.lastWindowId ||
                        it.root?.viewIdResourceName == service.resources.getResourceName(R.id.approval_overlay)))
        } ?: throw error("point_outside_screen")
        when {
            window.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD -> throw error("keyboard_blocked_use_type_text")
            window.type == AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY -> throw error("point_covered")
            window.root?.packageName?.toString() == service.packageName -> throw error("own_app")
        }
        return window
    }

    /** The deepest visible node at a point; later children are drawn on top. */
    private fun hitTest(window: AccessibilityWindowInfo, x: Int, y: Int): AccessibilityNodeInfo? {
        var node = window.root ?: return null
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        if (!bounds.contains(x, y)) return null
        var depth = 0
        descend@ while (depth++ < MAX_DEPTH) {
            for (child in node.childCount - 1 downTo 0) {
                val next = node.getChild(child) ?: continue
                if (!next.isVisibleToUser) continue
                next.getBoundsInScreen(bounds)
                if (bounds.contains(x, y)) {
                    node = next
                    continue@descend
                }
            }
            break
        }
        return node
    }

    private fun screenPoint(x: Double, y: Double): Pair<Int, Int> {
        val (width, height) = screenSize()
        val px = x.roundToInt()
        val py = y.roundToInt()
        if (px !in 0 until width || py !in 0 until height) throw error("point_outside_screen")
        return px to py
    }

    override fun resolvePoint(x: Double, y: Double, callback: (Result<ScreenTargetData>) -> Unit) = work(callback) {
        ensureNoApproval()
        val (px, py) = screenPoint(x, y)
        val window = windowAt(px, py)
        describe(hitTest(window, px, py), window, token, -1)
    }

    override fun resolveFocus(callback: (Result<ScreenTargetData>) -> Unit) = work(callback) {
        ensureNoApproval()
        val focused = service.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: throw error("no_focused_field")
        val window = focused.window ?: throw error("no_focused_field")
        describe(focused, window, token, -1)
    }

    // ---- Actions ----

    private inline fun ancestorOrSelf(
        node: AccessibilityNodeInfo,
        levels: Int,
        predicate: (AccessibilityNodeInfo) -> Boolean,
    ): AccessibilityNodeInfo? {
        var current: AccessibilityNodeInfo? = node
        var level = 0
        while (current != null && level++ <= levels) {
            if (predicate(current)) return current
            current = current.parent
        }
        return null
    }

    /** The approved node, unchanged since the user saw it. */
    private fun approvedNode(action: ScreenActionData): AccessibilityNodeInfo {
        val node = liveNode(action.token, action.node.toInt())
        if (check(node) != action.check) throw error("element_changed_read_again")
        return node
    }

    /** The approved point: the same window and the same node under it. */
    private fun approvedPoint(action: ScreenActionData): Triple<Float, Float, AccessibilityNodeInfo?> {
        val (px, py) = screenPoint(action.x ?: throw error("invalid_arguments"), action.y ?: throw error("invalid_arguments"))
        val window = windowAt(px, py)
        if (window.id.toLong() != action.windowId) throw error("screen_changed_read_again")
        val hit = hitTest(window, px, py)
        if ((hit?.let(::check) ?: "") != action.check) throw error("element_changed_read_again")
        return Triple(px.toFloat(), py.toFloat(), hit)
    }

    private fun approvedFocus(action: ScreenActionData): AccessibilityNodeInfo {
        val focused = service.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: throw error("no_focused_field")
        if (focused.packageName?.toString() == service.packageName) throw error("own_app")
        if (check(focused) != action.check) throw error("element_changed_read_again")
        return focused
    }

    /** A gesture point inside [node] that hits the node's own window. */
    private fun centerOf(node: AccessibilityNodeInfo): Pair<Float, Float> {
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        val (width, height) = screenSize()
        if (!bounds.intersect(0, 0, width, height) || bounds.isEmpty) throw error("element_not_visible_read_again")
        val x = bounds.exactCenterX()
        val y = bounds.exactCenterY()
        if (windowAt(x.roundToInt(), y.roundToInt()).id != node.windowId) throw error("element_covered_read_again")
        return x to y
    }

    private fun gesture(path: Path, duration: Long): Boolean {
        val done = CountDownLatch(1)
        val completed = AtomicBoolean(false)
        val description = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, duration))
            .build()
        main.post {
            val dispatched = service.dispatchGesture(description, object : AccessibilityService.GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    completed.set(true)
                    done.countDown()
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    done.countDown()
                }
            }, main)
            if (!dispatched) done.countDown()
        }
        done.await(duration + 3000, TimeUnit.MILLISECONDS)
        return completed.get()
    }

    private fun tap(x: Float, y: Float, long: Boolean): String {
        if (!gesture(Path().apply { moveTo(x, y) }, if (long) 650 else 60)) throw error("gesture_failed")
        return "gesture"
    }

    private fun press(action: ScreenActionData): String {
        val long = action.action == "long_press"
        if (action.node < 0) {
            val (x, y) = approvedPoint(action)
            return tap(x, y, long)
        }
        val node = approvedNode(action)
        val target = ancestorOrSelf(node, 8) { if (long) it.isLongClickable else it.isClickable }
        if (target != null && target.isEnabled &&
            target.performAction(if (long) AccessibilityNodeInfo.ACTION_LONG_CLICK else AccessibilityNodeInfo.ACTION_CLICK)) {
            return if (long) "long_click" else "click"
        }
        val (x, y) = centerOf(node)
        return tap(x, y, long)
    }

    private fun type(action: ScreenActionData): String {
        val text = action.text ?: throw error("invalid_arguments")
        val found = when {
            action.node >= 0 -> approvedNode(action)
            action.x != null -> approvedPoint(action).third
            else -> approvedFocus(action)
        } ?: throw error("not_editable")
        val field = ancestorOrSelf(found, 3) { it.isEditable } ?: throw error("not_editable")
        if (isPassword(field)) throw error("password_entry_blocked")
        // Fail before typing rather than leave half an action behind.
        if (action.submit && Build.VERSION.SDK_INT < Build.VERSION_CODES.R) throw error("submit_unsupported_tap_the_button")
        if (!field.isFocused) field.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val arguments = Bundle()
        arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        if (!field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) throw error("type_failed")
        if (!action.submit || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return "set_text"
        field.refresh()
        return if (field.performAction(AccessibilityAction.ACTION_IME_ENTER.id)) "set_text_submitted" else "set_text_submit_failed"
    }

    private fun largestScrollable(): AccessibilityNodeInfo? {
        val window = windowsByLayer().firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION } ?: return null
        val root = window.root ?: return null
        if (root.packageName?.toString() == service.packageName) throw error("own_app")
        val raws = mutableListOf<Raw>()
        collect(root, 0, raws, 600)
        return raws.filter { it.flags and ScreenFlags.SCROLLABLE != 0 }
            .maxByOrNull { it.bounds.width().toLong() * it.bounds.height() }?.node
    }

    private fun swipeIn(area: Rect, direction: String) {
        val (width, height) = screenSize()
        if (!area.intersect(0, 0, width, height) || area.isEmpty) throw error("element_not_visible_read_again")
        val x = area.exactCenterX()
        val y = area.exactCenterY()
        val dx = area.width() * 0.35f
        val dy = area.height() * 0.35f
        val (fromX, fromY, toX, toY) = when (direction) {
            "up" -> listOf(x, y + dy, x, y - dy)
            "down" -> listOf(x, y - dy, x, y + dy)
            "left" -> listOf(x + dx, y, x - dx, y)
            "right" -> listOf(x - dx, y, x + dx, y)
            else -> throw error("invalid_arguments")
        }
        if (windowAt(fromX.roundToInt(), fromY.roundToInt()).root?.packageName?.toString() == service.packageName) {
            throw error("own_app")
        }
        val path = Path().apply {
            moveTo(fromX, fromY)
            lineTo(toX, toY)
        }
        if (!gesture(path, 300)) throw error("gesture_failed")
    }

    private fun scroll(action: ScreenActionData): String {
        val direction = action.direction ?: throw error("invalid_arguments")
        val node = when {
            action.node >= 0 -> approvedNode(action)
            action.x != null -> approvedPoint(action).third
            else -> null
        }
        val scrollable = if (node != null) ancestorOrSelf(node, 10) { it.isScrollable } else largestScrollable()
        if (scrollable != null) {
            val directional = when (direction) {
                "down" -> AccessibilityAction.ACTION_SCROLL_DOWN
                "up" -> AccessibilityAction.ACTION_SCROLL_UP
                "left" -> AccessibilityAction.ACTION_SCROLL_LEFT
                "right" -> AccessibilityAction.ACTION_SCROLL_RIGHT
                else -> throw error("invalid_arguments")
            }
            if (scrollable.actionList.any { it.id == directional.id } && scrollable.performAction(directional.id)) return "scroll"
            val step = if (direction == "down" || direction == "right") AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            if (scrollable.performAction(step)) return "scroll"
        }
        // Showing content below means moving the finger up.
        val area = Rect()
        val (width, height) = screenSize()
        (scrollable ?: node)?.getBoundsInScreen(area) ?: area.set(0, 0, width, height)
        swipeIn(area, when (direction) { "down" -> "up"; "up" -> "down"; "left" -> "right"; else -> "left" })
        return "gesture"
    }

    private fun swipe(action: ScreenActionData): String {
        val direction = action.direction ?: throw error("invalid_arguments")
        val (width, height) = screenSize()
        val (x, y) = when {
            action.node >= 0 -> centerOf(approvedNode(action))
            action.x != null -> approvedPoint(action).let { it.first to it.second }
            else -> width / 2f to height / 2f
        }
        val reach = if (direction == "up" || direction == "down") height * 0.4f else width * 0.4f
        val (toX, toY) = when (direction) {
            "up" -> x to y - reach
            "down" -> x to y + reach
            "left" -> x - reach to y
            "right" -> x + reach to y
            else -> throw error("invalid_arguments")
        }
        if (windowAt(x.roundToInt(), y.roundToInt()).root?.packageName?.toString() == service.packageName) {
            throw error("own_app")
        }
        val path = Path().apply {
            moveTo(x, y)
            lineTo(toX.coerceIn(1f, width - 2f), toY.coerceIn(1f, height - 2f))
        }
        if (!gesture(path, 300)) throw error("gesture_failed")
        return "gesture"
    }

    private fun key(key: String?): String {
        val global = when (key) {
            "back" -> AccessibilityService.GLOBAL_ACTION_BACK
            "home" -> AccessibilityService.GLOBAL_ACTION_HOME
            "recents" -> AccessibilityService.GLOBAL_ACTION_RECENTS
            "notifications" -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
            else -> throw error("invalid_arguments")
        }
        if (!service.performGlobalAction(global)) throw error("key_failed")
        return "key"
    }

    override fun act(action: ScreenActionData, callback: (Result<ScreenActionResultData>) -> Unit) = work(callback) {
        ensureNoApproval()
        val started = SystemClock.uptimeMillis()
        val method = try {
            // A coordinate beneath our status always reaches the approved app,
            // never the Stop button. The touch-through frame remains visible.
            if (!hideControlForOperation(false)) throw error("screen_failed")
            when (action.action) {
                "tap", "long_press" -> press(action)
                "set_text" -> type(action)
                "scroll" -> scroll(action)
                "swipe" -> swipe(action)
                "key" -> key(action.key)
                else -> throw error("invalid_arguments")
            }
        } finally {
            controlOverlay.restoreAfterOperation(false)
        }
        // Let the app start reacting, then wait for its window to settle.
        awaitChange(started, 1200)
        awaitQuiet(350, 2500)
        val front = frontApp()
        ScreenActionResultData(
            method = method,
            packageName = front?.first.orEmpty(),
            appLabel = front?.second.orEmpty(),
            changed = service.lastEventAt > started,
        )
    }

    override fun showApproval(data: ApprovalOverlayData, callback: (String?) -> Unit) {
        controlOverlay.suspendForApproval(true)
        overlay.show(data) { choice ->
            controlOverlay.suspendForApproval(false)
            callback(choice)
        }
    }

    override fun hideApproval() = overlay.hide()

    override fun showControlOverlay(data: ControlOverlayData) = controlOverlay.show(data)

    override fun hideControlOverlay(sessionId: String, endSession: Boolean) = controlOverlay.hide(sessionId, endSession)
}
