package tw.avianjay.tako

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Choreographer
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.min
import kotlin.math.roundToInt

/** View's direct window-id accessor is hidden; use its public node API. */
internal fun View.overlayWindowId(): Int {
    val node = createAccessibilityNodeInfo() ?: return -1
    val id = node.windowId
    @Suppress("DEPRECATION")
    node.recycle()
    return id
}

/** A touch-through gradient frame and a separate, small Stop/status window. */
internal class ControlOverlay(private val service: AccessibilityService) {
    private val main = Handler(Looper.getMainLooper())
    private val manager get() = service.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var data: ControlOverlayData? = null
    private var frame: View? = null
    private var status: LinearLayout? = null
    private var label: TextView? = null
    private var title: TextView? = null
    private var stop: TextView? = null
    private var suspended = false
    private var captureHidden = false
    private var controlsHidden = false
    private val closedSessions = linkedSetOf<String>()
    @Volatile private var frameWindowId = -1
    @Volatile private var statusWindowId = -1

    private fun dp(value: Int) = (value * service.resources.displayMetrics.density).roundToInt()

    fun show(value: ControlOverlayData) {
        main.post {
            if (value.sessionId.isEmpty() || value.sessionId in closedSessions) return@post
            data = value
            try {
                if (frame == null) open()
                label?.text = value.label.take(120)
                title?.text = value.title.take(80)
                stop?.text = value.stop.take(40)
                frame?.invalidate()
                syncVisibility()
            } catch (_: Exception) {
                closeWindows()
                // The notification still provides Stop if drawing fails.
            }
        }
    }

    fun hide(sessionId: String, endSession: Boolean) {
        main.post {
            if (endSession) revoke(sessionId.ifEmpty { data?.sessionId.orEmpty() })
            if (sessionId.isEmpty() || data?.sessionId == sessionId) {
                if (endSession) data = null
                closeWindows()
            }
        }
    }

    private fun revoke(sessionId: String) {
        if (sessionId.isEmpty()) return
        closedSessions.add(sessionId)
        while (closedSessions.size > 32) closedSessions.remove(closedSessions.first())
    }

    fun suspendForApproval(value: Boolean) {
        main.post {
            suspended = value
            syncVisibility()
        }
    }

    /** Wait for the compositor to receive the hidden views before capturing or tapping. */
    fun hideForOperation(screenshot: Boolean, done: () -> Unit) {
        main.post {
            if (screenshot) captureHidden = true else controlsHidden = true
            val visible = if (screenshot) frame != null || status != null else status != null
            syncVisibility()
            if (!visible) {
                done()
            } else {
                val choreographer = Choreographer.getInstance()
                choreographer.postFrameCallback {
                    choreographer.postFrameCallback { done() }
                }
            }
        }
    }

    fun restoreAfterOperation(screenshot: Boolean) {
        main.post {
            if (screenshot) captureHidden = false else controlsHidden = false
            syncVisibility()
        }
    }

    /** Only our known status/frame windows may be ignored by target hit testing.
     * The status is hidden before gestures, so a model can never press Stop. */
    fun owns(window: AccessibilityWindowInfo): Boolean {
        if (window.type != AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY) return false
        val root = window.root
        if (root != null && root.packageName?.toString() != service.packageName) return false
        if (window.id == frameWindowId || window.id == statusWindowId) return true
        val id = root?.viewIdResourceName
        return id == service.resources.getResourceName(R.id.control_overlay_frame) ||
            id == service.resources.getResourceName(R.id.control_overlay_status)
    }

    fun refresh() {
        main.post {
            if (frame == null) return@post
            closeWindows()
            data?.let { show(it) }
        }
    }

    private fun syncVisibility() {
        frame?.visibility = if (captureHidden) View.INVISIBLE else View.VISIBLE
        status?.visibility = if (captureHidden || controlsHidden || suspended || data?.phase == "waitingApproval") {
            View.INVISIBLE
        } else View.VISIBLE
    }

    private fun closeWindows() {
        frame?.let {
            frameWindowId = it.overlayWindowId()
            try { manager.removeView(it) } catch (_: Exception) { }
        }
        status?.let {
            statusWindowId = it.overlayWindowId()
            try { manager.removeView(it) } catch (_: Exception) { }
        }
        frame = null
        status = null
        label = null
        title = null
        stop = null
    }

    private fun open() {
        val night = (service.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val accent = if (night) 0xFFAED1B8.toInt() else 0xFF466953.toInt()
        val teal = if (night) 0xFF8BC8C3.toInt() else 0xFF648B87.toInt()
        val pale = if (night) 0xFFC7DEC3.toInt() else 0xFF88A98B.toInt()
        val surface = if (night) 0xFF253A2C.toInt() else 0xFFF0F6ED.toInt()
        val onSurface = if (night) 0xFFE1E3DE.toInt() else 0xFF191C19.toInt()
        val secondary = if (night) 0xFFC1C9BF.toInt() else 0xFF536052.toInt()
        val buttonFill = if (night) 0xFFC8EBD3.toInt() else 0xFF2F513C.toInt()
        val buttonText = if (night) 0xFF022110.toInt() else 0xFFFFFFFF.toInt()
        fun rounded(color: Int, radius: Int) = GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
        }
        fun text(size: Float, color: Int) = TextView(service).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
            setTextColor(color)
            maxLines = 2
        }

        val border = object : View(service) {
            private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp(2).toFloat()
            }
            private val rect = RectF()
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                paint.shader = LinearGradient(0f, h.toFloat(), w.toFloat(), 0f,
                    intArrayOf(accent, teal, pale), null, Shader.TileMode.CLAMP)
                val inset = dp(3).toFloat()
                rect.set(inset, inset, w - inset, h - inset)
            }
            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                paint.alpha = if (data?.phase == "thinking") 160 else 230
                canvas.drawRoundRect(rect, dp(25).toFloat(), dp(25).toFloat(), paint)
            }
        }.apply {
            id = R.id.control_overlay_frame
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        val frameParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                setFitInsetsTypes(0)
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        manager.addView(border, frameParams)
        frame = border
        border.post { if (frame === border) frameWindowId = border.overlayWindowId() }

        val pill = LinearLayout(service).apply {
            id = R.id.control_overlay_status
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR,
                intArrayOf(surface, if (night) 0xFF293F35.toInt() else 0xFFEAF3EE.toInt())).apply {
                cornerRadius = dp(18).toFloat()
                setStroke(dp(1), accent)
            }
            setPadding(dp(12), dp(10), dp(10), dp(10))
            elevation = dp(6).toFloat()
        }
        val dot = View(service).apply { background = rounded(accent, 4) }
        pill.addView(dot, LinearLayout.LayoutParams(dp(7), dp(7)).apply { marginEnd = dp(10) })
        val copy = LinearLayout(service).apply { orientation = LinearLayout.VERTICAL }
        label = text(11f, secondary)
        title = text(13f, onSurface).apply { typeface = Typeface.DEFAULT_BOLD }
        copy.addView(label)
        copy.addView(title, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4) })
        pill.addView(copy, LinearLayout.LayoutParams(0, -2, 1f))
        stop = text(12f, buttonText).apply {
            gravity = Gravity.CENTER
            minHeight = dp(44)
            minWidth = dp(44)
            setPadding(dp(10), 0, dp(10), 0)
            background = rounded(buttonFill, 12)
            isClickable = true
            isFocusable = true
            setOnClickListener {
                val id = data?.sessionId.orEmpty()
                revoke(id)
                data = null
                closeWindows()
                ControlSignals.stopRequested()
            }
        }
        pill.addView(stop, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(10) })
        val statusParams = WindowManager.LayoutParams(
            min(service.resources.displayMetrics.widthPixels - dp(24), dp(360)),
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) setFitInsetsTypes(0)
            y = dp(16)
        }
        border.setOnApplyWindowInsetsListener { _, insets ->
            val bottom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime()).bottom
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetBottom
            }
            statusParams.y = bottom + dp(12)
            if (status === pill) {
                try { manager.updateViewLayout(pill, statusParams) } catch (_: Exception) { }
            }
            insets
        }
        manager.addView(pill, statusParams)
        status = pill
        pill.post { if (status === pill) statusWindowId = pill.overlayWindowId() }
        border.requestApplyInsets()
    }
}
