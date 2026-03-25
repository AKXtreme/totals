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
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

class BudgetWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val MAX_BUDGETS = 3
    }

    private data class BudgetWidgetItem(
        val name: String,
        val compactValue: String,
        val expandedValue: String,
        val ringPercent: Double,
        val color: Int
    )

    private data class WidgetMode(
        val widthDp: Int,
        val heightDp: Int,
        val legendVisible: Boolean,
        val expandedValuesVisible: Boolean,
        val namesVisible: Boolean
    )

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_budget_layout)
            val mode = resolveWidgetMode(appWidgetManager, widgetId)
            val items = loadItems(widgetData)
            val emptyMessage = widgetData.getString(
                "budget_widget_empty_message",
                "Choose up to 3 budgets in Totals."
            ) ?: "Choose up to 3 budgets in Totals."

            bindClickAction(context, views, widgetId)
            applyResponsiveLayout(context, views, mode)

            if (items.isEmpty()) {
                views.setViewVisibility(R.id.budget_content_group, View.GONE)
                views.setViewVisibility(R.id.budget_empty_group, View.VISIBLE)
                views.setTextViewText(R.id.budget_empty_message, emptyMessage)
                appWidgetManager.updateAppWidget(widgetId, views)
                return@forEach
            }

            views.setViewVisibility(R.id.budget_content_group, View.VISIBLE)
            views.setViewVisibility(R.id.budget_empty_group, View.GONE)

            bindLegendRows(context, views, items, mode)

            createRingBitmap(context, mode, items)?.let { bitmap ->
                views.setImageViewBitmap(R.id.budget_ring_image, bitmap)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun resolveWidgetMode(
        appWidgetManager: AppWidgetManager,
        widgetId: Int
    ): WidgetMode {
        val options = appWidgetManager.getAppWidgetOptions(widgetId)

        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            .takeIf { it > 0 }
            ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH).takeIf { it > 0 }
            ?: 140
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            .takeIf { it > 0 }
            ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 }
            ?: 72

        val legendVisible = widthDp >= 176 && heightDp >= 58
        val expandedValuesVisible = widthDp >= 248
        val namesVisible = widthDp >= 320

        return WidgetMode(
            widthDp = widthDp,
            heightDp = heightDp,
            legendVisible = legendVisible,
            expandedValuesVisible = expandedValuesVisible,
            namesVisible = namesVisible
        )
    }

    private fun loadItems(widgetData: SharedPreferences): List<BudgetWidgetItem> {
        val items = mutableListOf<BudgetWidgetItem>()

        for (index in 0 until MAX_BUDGETS) {
            val prefix = "budget_item_$index"
            val budgetId = widgetData.getString("${prefix}_budget_id", "")?.trim().orEmpty()
            if (budgetId.isEmpty()) continue

            val name = widgetData.getString("${prefix}_name", "Budget") ?: "Budget"
            val compactValue = widgetData.getString("${prefix}_compact_value", "0") ?: "0"
            val expandedValue = widgetData.getString("${prefix}_expanded_value", compactValue)
                ?: compactValue
            val ringPercent = widgetData.getString("${prefix}_ring_percent", "0")
                ?.toDoubleOrNull()
                ?.coerceIn(0.0, 100.0)
                ?: 0.0
            val color = parseColorHex(widgetData.getString("${prefix}_color", null))

            items += BudgetWidgetItem(
                name = name,
                compactValue = compactValue,
                expandedValue = expandedValue,
                ringPercent = ringPercent,
                color = color
            )
        }

        return items
    }

    private fun bindLegendRows(
        context: Context,
        views: RemoteViews,
        items: List<BudgetWidgetItem>,
        mode: WidgetMode
    ) {
        val rowIds = intArrayOf(
            R.id.budget_item_row_0,
            R.id.budget_item_row_1,
            R.id.budget_item_row_2
        )
        val dotIds = intArrayOf(
            R.id.budget_item_dot_0,
            R.id.budget_item_dot_1,
            R.id.budget_item_dot_2
        )
        val nameIds = intArrayOf(
            R.id.budget_item_name_0,
            R.id.budget_item_name_1,
            R.id.budget_item_name_2
        )
        val valueIds = intArrayOf(
            R.id.budget_item_value_0,
            R.id.budget_item_value_1,
            R.id.budget_item_value_2
        )

        views.setViewVisibility(
            R.id.budget_legend_group,
            if (mode.legendVisible) View.VISIBLE else View.GONE
        )
        val valueColor = ContextCompat.getColor(context, R.color.budget_widget_value)

        val valueTextSize = when {
            mode.namesVisible -> 15f
            mode.expandedValuesVisible -> 16f
            else -> 17f
        }

        for (index in 0 until MAX_BUDGETS) {
            val rowId = rowIds[index]
            val dotId = dotIds[index]
            val nameId = nameIds[index]
            val valueId = valueIds[index]

            if (!mode.legendVisible || index >= items.size) {
                views.setViewVisibility(rowId, View.GONE)
                continue
            }

            val item = items[index]
            views.setViewVisibility(rowId, View.VISIBLE)
            views.setTextViewText(nameId, item.name)
            views.setTextViewText(valueId, formatPercentText(item.ringPercent))
            views.setTextColor(dotId, item.color)
            views.setTextColor(nameId, valueColor)
            views.setTextColor(valueId, valueColor)
            views.setViewVisibility(nameId, View.VISIBLE)
            views.setViewVisibility(valueId, if (mode.namesVisible) View.VISIBLE else View.GONE)
            views.setTextViewTextSize(nameId, TypedValue.COMPLEX_UNIT_SP, valueTextSize)
            views.setTextViewTextSize(valueId, TypedValue.COMPLEX_UNIT_SP, valueTextSize)
        }
    }

    private fun applyResponsiveLayout(
        context: Context,
        views: RemoteViews,
        mode: WidgetMode
    ) {
        val density = context.resources.displayMetrics.density
        val horizontalPadding = if (mode.legendVisible) 9 else 7
        val verticalPadding = if (mode.legendVisible) 7 else 6

        views.setViewPadding(
            R.id.widget_budget_root,
            (horizontalPadding * density).roundToInt(),
            (verticalPadding * density).roundToInt(),
            (horizontalPadding * density).roundToInt(),
            (verticalPadding * density).roundToInt()
        )
    }

    private fun bindClickAction(
        context: Context,
        views: RemoteViews,
        widgetId: Int
    ) {
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
            widgetId + 9200,
            openAppIntent,
            pendingFlags
        )

        views.setOnClickPendingIntent(R.id.widget_budget_root, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.budget_empty_group, openAppPendingIntent)
    }

    private fun createRingBitmap(
        context: Context,
        mode: WidgetMode,
        items: List<BudgetWidgetItem>
    ): Bitmap? {
        if (items.isEmpty()) return null

        val sizeDp = when {
            !mode.legendVisible -> (min(mode.widthDp, mode.heightDp) - 6).coerceIn(72, 98)
            mode.namesVisible -> 82
            mode.expandedValuesVisible -> 80
            else -> 76
        }
        val density = context.resources.displayMetrics.density
        val sizePx = (sizeDp * density).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val center = sizePx / 2f
        val ringStrokeWidth = when (items.size) {
            1 -> sizePx * 0.16f
            2 -> sizePx * 0.12f
            else -> sizePx * 0.10f
        }
        val gap = ringStrokeWidth * 0.38f
        var radius = center - ringStrokeWidth / 2f - (sizePx * 0.03f)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeWidth = ringStrokeWidth
        }
        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeWidth = ringStrokeWidth
        }
        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

        items.forEach { item ->
            if (radius <= ringStrokeWidth / 2f) return@forEach

            val rect = RectF(
                center - radius,
                center - radius,
                center + radius,
                center + radius
            )
            trackPaint.color = applyAlpha(item.color, 0.22f)
            ringPaint.color = item.color

            canvas.drawArc(rect, -90f, 360f, false, trackPaint)

            val sweep = ((item.ringPercent.coerceIn(0.0, 100.0) / 100.0) * 360.0).toFloat()
            if (sweep > 0.5f) {
                canvas.drawArc(rect, -90f, sweep, false, ringPaint)
            }

            val dotAngle = Math.toRadians((-90f + sweep).toDouble())
            val dotRadius = ringStrokeWidth * 0.56f
            val dotX = center + (radius * cos(dotAngle)).toFloat()
            val dotY = center + (radius * sin(dotAngle)).toFloat()
            dotPaint.color = item.color
            canvas.drawCircle(dotX, dotY, dotRadius, dotPaint)

            radius -= ringStrokeWidth + gap
        }

        return bitmap
    }

    private fun parseColorHex(raw: String?): Int {
        if (raw.isNullOrBlank()) return Color.WHITE
        return try {
            Color.parseColor(raw)
        } catch (_: IllegalArgumentException) {
            Color.WHITE
        }
    }

    private fun applyAlpha(color: Int, factor: Float): Int {
        val alpha = (255 * factor).roundToInt().coerceIn(0, 255)
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
    }

    private fun formatPercentText(percent: Double): String {
        return "${percent.roundToInt()}%"
    }
}
