package tw.avianjay.tako

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The permission prompt shown over other apps while Tako is in the
 * background. It blocks touches to the app below until the user chooses, and
 * screen actions are refused while it is visible, so the model cannot answer
 * it. Texts come localized from Dart.
 */
internal class ApprovalOverlay(private val service: AccessibilityService) {
    private val main = Handler(Looper.getMainLooper())
    private var view: View? = null
    private var callback: ((String?) -> Unit)? = null

    @Volatile
    var visible = false
        private set

    private val windowManager get() = service.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    fun show(data: ApprovalOverlayData, done: (String?) -> Unit) {
        main.post {
            close(null)
            try {
                open(data, done)
            } catch (_: Exception) {
                done(null)
            }
        }
    }

    fun hide() {
        main.post { close(null) }
    }

    private fun close(choice: String?) {
        val current = view
        val done = callback
        view = null
        callback = null
        visible = false
        if (current != null) {
            try {
                windowManager.removeView(current)
            } catch (_: Exception) {
                // Already removed with the service.
            }
        }
        done?.invoke(choice)
    }

    @Suppress("DEPRECATION")
    private fun legacyInsets(insets: WindowInsets) = insets.systemWindowInsetTop to insets.systemWindowInsetBottom

    private class Palette(night: Boolean) {
        val scrim = if (night) 0xB3000000.toInt() else 0x99000000.toInt()
        val surface = if (night) 0xFF1E241F.toInt() else 0xFFFAFBF7.toInt()
        val onSurface = if (night) 0xFFE1E3DE.toInt() else 0xFF191C19.toInt()
        val variant = if (night) 0xFFC1C9BF.toInt() else 0xFF414941.toInt()
        val code = if (night) 0xFF2A312B.toInt() else 0xFFE8EBE5.toInt()
        val primary = if (night) 0xFFAED1B8.toInt() else 0xFF466953.toInt()
        val container = if (night) 0xFF2F513C.toInt() else 0xFFC8EBD3.toInt()
        val onContainer = if (night) 0xFFC9EDD4.toInt() else 0xFF022110.toInt()
        val error = if (night) 0xFFFFB4AB.toInt() else 0xFFBA1A1A.toInt()
        val outline = if (night) 0xFF8B9389.toInt() else 0xFF717970.toInt()
    }

    private fun open(data: ApprovalOverlayData, done: (String?) -> Unit) {
        val context: Context = service
        val night = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val colors = Palette(night)
        val density = context.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).roundToInt()
        fun text(value: CharSequence, size: Float, color: Int, bold: Boolean = false) = TextView(context).apply {
            this.text = value
            setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
            setTextColor(color)
            if (bold) typeface = Typeface.DEFAULT_BOLD
        }
        fun rounded(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }

        val highlight = listOf(data.left, data.top, data.right, data.bottom)
        val accent = if (data.highRisk) colors.error else colors.primary
        val root = object : FrameLayout(context) {
            private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp(3).toFloat()
                color = accent
            }
            private val location = IntArray(2)

            override fun dispatchDraw(canvas: Canvas) {
                canvas.drawColor(colors.scrim)
                // Outline the element the request is about, in screen coordinates.
                if (highlight.all { it != null }) {
                    getLocationOnScreen(location)
                    val box = RectF(
                        highlight[0]!!.toFloat() - location[0], highlight[1]!!.toFloat() - location[1],
                        highlight[2]!!.toFloat() - location[0], highlight[3]!!.toFloat() - location[1],
                    )
                    box.inset(-dp(4).toFloat(), -dp(4).toFloat())
                    canvas.drawRoundRect(box, dp(8).toFloat(), dp(8).toFloat(), paint)
                }
                super.dispatchDraw(canvas)
            }
        }
        root.setWillNotDraw(false)
        root.isClickable = true
        root.isFocusable = false

        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(colors.surface, 24)
            setPadding(dp(20), dp(18), dp(20), dp(16))
            elevation = dp(8).toFloat()
            isClickable = true
        }
        card.addView(text(data.title, 20f, if (data.highRisk) colors.error else colors.onSurface, bold = true))
        card.addView(text(data.subtitle, 14f, colors.variant).apply { setPadding(0, dp(6), 0, 0) })
        for (index in data.detailLabels.indices) {
            val label = data.detailLabels[index]
            val value = data.detailValues.getOrNull(index) ?: continue
            val line = SpannableStringBuilder("$label: $value")
            line.setSpan(StyleSpan(Typeface.BOLD), 0, label.length + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            card.addView(text(line, 15f, colors.onSurface).apply { setPadding(0, dp(6), 0, 0) })
        }
        card.addView(text(data.note, 12f, colors.variant).apply { setPadding(0, dp(10), 0, dp(8)) })
        val arguments = text(data.arguments, 12f, colors.onSurface).apply {
            typeface = Typeface.MONOSPACE
            setTextIsSelectable(false)
            setPadding(dp(10), dp(8), dp(10), dp(8))
        }
        val scroll = object : ScrollView(context) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(dp(130), MeasureSpec.AT_MOST))
            }
        }
        scroll.background = rounded(colors.code, 12)
        scroll.addView(arguments)
        card.addView(scroll)
        for (index in data.choiceIds.indices) {
            val id = data.choiceIds[index]
            val deny = id == data.denyId
            val button = text(data.choiceLabels.getOrNull(index) ?: id, 15f, if (deny) colors.onSurface else colors.onContainer, bold = !deny)
            button.gravity = Gravity.CENTER
            button.minHeight = dp(48)
            button.background = if (deny) rounded(Color.TRANSPARENT, 24, colors.outline) else rounded(colors.container, 24)
            button.isClickable = true
            button.isFocusable = true
            button.setOnClickListener { close(id) }
            card.addView(button, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(8)
            })
        }

        val width = min(context.resources.displayMetrics.widthPixels - dp(24), dp(560))
        root.addView(card, FrameLayout.LayoutParams(width, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(12) })
        root.setOnApplyWindowInsetsListener { view, insets ->
            val (top, bottom) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars())
                bars.top to bars.bottom
            } else {
                legacyInsets(insets)
            }
            view.setPadding(0, top, 0, bottom)
            insets
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            params.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        windowManager.addView(root, params)
        view = root
        callback = done
        visible = true
    }
}
