package com.example.offline_gateway

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Locale
import kotlin.math.roundToInt

class BudgetWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val ACTION_TOGGLE_VISIBILITY =
            "com.example.offline_gateway.widget.BUDGET_TOGGLE_VISIBILITY"
        private const val ACTION_TOGGLE_PERIOD =
            "com.example.offline_gateway.widget.BUDGET_TOGGLE_PERIOD"

        private const val PREF_KEY_HIDDEN_PREFIX = "budget_widget_hidden_"
        private const val PREF_KEY_PERIOD_PREFIX = "budget_widget_period_"

        private val PERIODS = arrayOf("daily", "monthly", "yearly")

        private val RANK_COLORS = intArrayOf(
            Color.parseColor("#5AC8FA"),
            Color.parseColor("#FFB347"),
            Color.parseColor("#FF5D73")
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TOGGLE_VISIBILITY -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID
                )
                if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

                val prefs = HomeWidgetPlugin.getData(context)
                val key = "$PREF_KEY_HIDDEN_PREFIX$widgetId"
                val isHidden = prefs.getBoolean(key, false)
                prefs.edit().putBoolean(key, !isHidden).apply()

                val appWidgetManager = AppWidgetManager.getInstance(context)
                onUpdate(context, appWidgetManager, intArrayOf(widgetId), prefs)
            }

            ACTION_TOGGLE_PERIOD -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID
                )
                if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

                val prefs = HomeWidgetPlugin.getData(context)
                val key = "$PREF_KEY_PERIOD_PREFIX$widgetId"
                val currentPeriod = normalizePeriod(
                    prefs.getString(key, "monthly") ?: "monthly"
                )
                prefs.edit().putString(key, nextPeriod(currentPeriod)).apply()

                val appWidgetManager = AppWidgetManager.getInstance(context)
                onUpdate(context, appWidgetManager, intArrayOf(widgetId), prefs)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_budget_layout)

            val hiddenKey = "$PREF_KEY_HIDDEN_PREFIX$widgetId"
            val isHidden = widgetData.getBoolean(hiddenKey, false)

            val periodKey = "$PREF_KEY_PERIOD_PREFIX$widgetId"
            val selectedPeriod = normalizePeriod(
                widgetData.getString(periodKey, "monthly") ?: "monthly"
            )
            val periodPrefix = "budget_${selectedPeriod}"

            bindClickActions(context, views, widgetId)
            views.setImageViewResource(
                R.id.toggle_budget_visibility,
                if (isHidden) R.drawable.ic_visibility_off else R.drawable.ic_visibility_on
            )

            val periodLabel = widgetData.getString(
                "${periodPrefix}_period_label",
                periodTitle(selectedPeriod)
            ) ?: periodTitle(selectedPeriod)

            val isEmpty = widgetData.getString("${periodPrefix}_is_empty", "1") == "1"
            val lastUpdated =
                widgetData.getString("${periodPrefix}_updated_at", "--") ?: "--"

            views.setTextViewText(R.id.budget_title, "Budget • $periodLabel")
            views.setTextViewText(R.id.budget_period_chip, periodLabel)
            views.setTextViewText(R.id.budget_last_updated, lastUpdated)

            if (isEmpty) {
                val emptyMessage = widgetData.getString(
                    "${periodPrefix}_empty_message",
                    "You currently don't have any budgets."
                ) ?: "You currently don't have any budgets."

                views.setViewVisibility(R.id.budget_content_group, View.GONE)
                views.setViewVisibility(R.id.budget_empty_group, View.VISIBLE)
                views.setTextViewText(R.id.budget_empty_message, emptyMessage)

                appWidgetManager.updateAppWidget(widgetId, views)
                return@forEach
            }

            views.setViewVisibility(R.id.budget_content_group, View.VISIBLE)
            views.setViewVisibility(R.id.budget_empty_group, View.GONE)

            val spentLabel =
                widgetData.getString("${periodPrefix}_spent_label", "0 ETB") ?: "0 ETB"
            val budgetLabel =
                widgetData.getString("${periodPrefix}_budget_label", "0 ETB") ?: "0 ETB"
            val spentRaw =
                widgetData.getString("${periodPrefix}_spent_raw", "0")?.toDoubleOrNull() ?: 0.0
            val budgetRaw =
                widgetData.getString("${periodPrefix}_budget_raw", "0")?.toDoubleOrNull() ?: 0.0
            val percentUsed =
                widgetData.getString("${periodPrefix}_percent", "0")?.toDoubleOrNull() ?: 0.0

            if (isHidden) {
                views.setTextViewText(R.id.budget_spent_value, "***")
                views.setTextViewText(R.id.budget_limit_value, "***")
            } else {
                views.setTextViewText(R.id.budget_spent_value, spentLabel)
                views.setTextViewText(R.id.budget_limit_value, budgetLabel)
            }

            val roundedPercent = percentUsed.roundToInt().coerceIn(0, 999)
            views.setTextViewText(R.id.budget_percent_value, "$roundedPercent%")

            createProgressRingBitmap(context, percentUsed)?.let { bitmap ->
                views.setImageViewBitmap(R.id.budget_ring, bitmap)
            }

            val categoryRowIds = listOf(
                R.id.budget_category_row_0,
                R.id.budget_category_row_1,
                R.id.budget_category_row_2
            )
            val categoryNameIds = listOf(
                R.id.budget_category_name_0,
                R.id.budget_category_name_1,
                R.id.budget_category_name_2
            )
            val categoryAmountIds = listOf(
                R.id.budget_category_amount_0,
                R.id.budget_category_amount_1,
                R.id.budget_category_amount_2
            )
            val categoryDotIds = listOf(
                R.id.budget_category_dot_0,
                R.id.budget_category_dot_1,
                R.id.budget_category_dot_2
            )

            val categorySpent = DoubleArray(3) { index ->
                widgetData.getString("${periodPrefix}_category_${index}_spent_raw", "0")
                    ?.toDoubleOrNull() ?: 0.0
            }

            val base = when {
                spentRaw > 0.0 -> spentRaw
                categorySpent.sum() > 0.0 -> categorySpent.sum()
                else -> budgetRaw
            }

            createCategoryBarBitmap(
                context = context,
                appWidgetManager = appWidgetManager,
                widgetId = widgetId,
                values = categorySpent,
                base = base
            )?.let { bitmap ->
                views.setImageViewBitmap(R.id.budget_category_bar, bitmap)
            }

            for (i in 0..2) {
                val name = widgetData.getString("${periodPrefix}_category_${i}_name", "") ?: ""
                val colorHex =
                    widgetData.getString("${periodPrefix}_category_${i}_color", "") ?: ""
                val spentValue = categorySpent[i]
                val spentValueLabel =
                    widgetData.getString("${periodPrefix}_category_${i}_spent_label", "") ?: ""

                if (name.isBlank()) {
                    views.setViewVisibility(categoryRowIds[i], View.GONE)
                    continue
                }

                views.setViewVisibility(categoryRowIds[i], View.VISIBLE)
                views.setTextViewText(categoryNameIds[i], name)

                val displayValue = if (isHidden) {
                    if (base <= 0.0) {
                        "0%"
                    } else {
                        val ratio = ((spentValue / base) * 100).roundToInt().coerceAtLeast(0)
                        "$ratio%"
                    }
                } else {
                    spentValueLabel
                }

                views.setTextViewText(categoryAmountIds[i], displayValue)
                views.setInt(
                    categoryDotIds[i],
                    "setColorFilter",
                    parseColorOrDefault(colorHex, RANK_COLORS[i])
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindClickActions(context: Context, views: RemoteViews, widgetId: Int) {
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_LAUNCH_TARGET, MainActivity.TARGET_BUDGET)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            widgetId + 9000,
            openAppIntent,
            pendingFlags
        )

        val toggleVisibilityIntent = Intent(context, BudgetWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_VISIBILITY
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val toggleVisibilityPendingIntent = PendingIntent.getBroadcast(
            context,
            widgetId + 9100,
            toggleVisibilityIntent,
            pendingFlags
        )

        val togglePeriodIntent = Intent(context, BudgetWidgetProvider::class.java).apply {
            action = ACTION_TOGGLE_PERIOD
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val togglePeriodPendingIntent = PendingIntent.getBroadcast(
            context,
            widgetId + 9200,
            togglePeriodIntent,
            pendingFlags
        )

        views.setOnClickPendingIntent(R.id.widget_budget_root, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.toggle_budget_visibility, toggleVisibilityPendingIntent)
        views.setOnClickPendingIntent(R.id.budget_period_chip, togglePeriodPendingIntent)
    }

    private fun normalizePeriod(raw: String): String {
        val value = raw.lowercase(Locale.US)
        return if (PERIODS.contains(value)) value else "monthly"
    }

    private fun nextPeriod(current: String): String {
        val index = PERIODS.indexOf(current)
        if (index == -1) return "monthly"
        return PERIODS[(index + 1) % PERIODS.size]
    }

    private fun periodTitle(period: String): String {
        return when (period) {
            "daily" -> "Daily"
            "yearly" -> "Yearly"
            else -> "Monthly"
        }
    }

    private fun parseColorOrDefault(colorHex: String, fallback: Int): Int {
        if (colorHex.isBlank()) return fallback
        return try {
            Color.parseColor(colorHex)
        } catch (_: IllegalArgumentException) {
            fallback
        }
    }

    private fun createProgressRingBitmap(context: Context, percentUsed: Double): Bitmap? {
        val density = context.resources.displayMetrics.density
        val sizePx = (52f * density).toInt().coerceAtLeast(1)
        val strokeWidth = 6f * density

        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.parseColor("#2A2F3E")
            this.strokeWidth = strokeWidth
            strokeCap = Paint.Cap.ROUND
        }

        val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = when {
                percentUsed >= 100.0 -> Color.parseColor("#FF5D73")
                percentUsed >= 80.0 -> Color.parseColor("#FFB347")
                else -> Color.parseColor("#5AC8FA")
            }
            this.strokeWidth = strokeWidth
            strokeCap = Paint.Cap.ROUND
        }

        val padding = strokeWidth / 2f
        val arcRect = RectF(
            padding,
            padding,
            sizePx.toFloat() - padding,
            sizePx.toFloat() - padding
        )

        canvas.drawArc(arcRect, 0f, 360f, false, trackPaint)

        val sweep = ((percentUsed.coerceIn(0.0, 100.0) / 100.0) * 360f).toFloat()
        canvas.drawArc(arcRect, -90f, sweep, false, progressPaint)

        return bitmap
    }

    private fun createCategoryBarBitmap(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        values: DoubleArray,
        base: Double
    ): Bitmap? {
        val options = appWidgetManager.getAppWidgetOptions(widgetId)
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            .takeIf { it > 0 }
            ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
        val density = context.resources.displayMetrics.density
        val widthPx = (widthDp * density).toInt().coerceAtLeast(1)
        val heightPx = (10f * density).toInt().coerceAtLeast(1)

        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        if (base <= 0.0) return bitmap

        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = heightPx / 2f
        val clipPath = Path().apply {
            addRoundRect(
                RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()),
                radius,
                radius,
                Path.Direction.CW
            )
        }
        canvas.clipPath(clipPath)

        var startX = 0f
        for (index in values.indices) {
            val fraction = (values[index] / base).coerceIn(0.0, 1.0)
            val segmentWidth = (fraction * widthPx).toFloat()
            if (segmentWidth <= 0f) continue

            paint.color = RANK_COLORS[index % RANK_COLORS.size]
            val endX = (startX + segmentWidth).coerceAtMost(widthPx.toFloat())
            canvas.drawRect(startX, 0f, endX, heightPx.toFloat(), paint)
            startX = endX
        }

        return bitmap
    }
}
