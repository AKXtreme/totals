package com.example.offline_gateway

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.abs
import kotlin.math.roundToInt

class BudgetWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val ACTION_TOGGLE_VISIBILITY =
            "com.example.offline_gateway.widget.BUDGET_TOGGLE_VISIBILITY"

        private const val PREF_KEY_HIDDEN_PREFIX = "budget_widget_hidden_"
        private const val MONTHLY_PERIOD = "monthly"
    }

    private data class WidgetMode(
        val widthDp: Int,
        val heightDp: Int,
        val compact: Boolean,
        val showGroups: Boolean,
        val showUpdated: Boolean
    )

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
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val prefs = HomeWidgetPlugin.getData(context)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), prefs)
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

            val hiddenKey = "$PREF_KEY_HIDDEN_PREFIX$widgetId"
            val isHidden = widgetData.getBoolean(hiddenKey, false)
            val periodPrefix = "budget_$MONTHLY_PERIOD"

            bindClickActions(context, views, widgetId)
            views.setImageViewResource(
                R.id.toggle_budget_visibility,
                if (isHidden) R.drawable.ic_visibility_off else R.drawable.ic_visibility_on
            )

            applyResponsiveLayout(context, views, mode)

            views.setTextViewText(R.id.budget_title, "Budget")
            val lastUpdated = widgetData.getString("${periodPrefix}_updated_at", "--") ?: "--"
            views.setTextViewText(R.id.budget_last_updated, lastUpdated)

            val isEmpty = widgetData.getString("${periodPrefix}_is_empty", "1") == "1"
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

            val assignedLabel =
                widgetData.getString("${periodPrefix}_assigned_label", "0 ETB") ?: "0 ETB"
            val activityLabel =
                widgetData.getString("${periodPrefix}_activity_label", "0 ETB") ?: "0 ETB"
            val availableLabel =
                widgetData.getString("${periodPrefix}_available_label", "0 ETB") ?: "0 ETB"
            val needsLabel = widgetData.getString(
                "${periodPrefix}_needs_available_label",
                "0 ETB"
            ) ?: "0 ETB"
            val wantsLabel = widgetData.getString(
                "${periodPrefix}_wants_available_label",
                "0 ETB"
            ) ?: "0 ETB"

            val availableRaw =
                widgetData.getString("${periodPrefix}_available_raw", "0")?.toDoubleOrNull() ?: 0.0
            val needsRaw = widgetData.getString("${periodPrefix}_needs_available_raw", "0")
                ?.toDoubleOrNull() ?: 0.0
            val wantsRaw = widgetData.getString("${periodPrefix}_wants_available_raw", "0")
                ?.toDoubleOrNull() ?: 0.0
            val assignedRaw =
                widgetData.getString("${periodPrefix}_assigned_raw", "0")?.toDoubleOrNull() ?: 0.0
            val activityRaw =
                widgetData.getString("${periodPrefix}_activity_raw", "0")?.toDoubleOrNull() ?: 0.0
            val percentUsed =
                widgetData.getString("${periodPrefix}_percent", "0")?.toDoubleOrNull() ?: 0.0

            val roundedPercent = percentUsed.roundToInt().coerceIn(0, 999)
            if (isHidden) {
                val groupMagnitude = abs(needsRaw) + abs(wantsRaw)

                views.setTextViewText(
                    R.id.budget_assigned_value,
                    if (assignedRaw > 0.0) "100%" else "--"
                )
                views.setTextViewText(
                    R.id.budget_activity_value,
                    asPercentString(
                        numerator = activityRaw,
                        denominator = assignedRaw,
                        clampMin = 0,
                        clampMax = 999
                    )
                )
                views.setTextViewText(
                    R.id.budget_available_value,
                    asPercentString(
                        numerator = availableRaw,
                        denominator = assignedRaw,
                        clampMin = -999,
                        clampMax = 999
                    )
                )
                views.setTextViewText(
                    R.id.budget_needs_value,
                    asPercentString(
                        numerator = abs(needsRaw),
                        denominator = groupMagnitude,
                        clampMin = 0,
                        clampMax = 100
                    )
                )
                views.setTextViewText(
                    R.id.budget_wants_value,
                    asPercentString(
                        numerator = abs(wantsRaw),
                        denominator = groupMagnitude,
                        clampMin = 0,
                        clampMax = 100
                    )
                )
                views.setTextViewText(R.id.budget_percent_value, "$roundedPercent%")
            } else {
                views.setTextViewText(R.id.budget_assigned_value, assignedLabel)
                views.setTextViewText(R.id.budget_activity_value, activityLabel)
                views.setTextViewText(R.id.budget_available_value, availableLabel)
                views.setTextViewText(R.id.budget_needs_value, needsLabel)
                views.setTextViewText(R.id.budget_wants_value, wantsLabel)
                views.setTextViewText(R.id.budget_percent_value, "$roundedPercent%")
            }

            views.setTextColor(
                R.id.budget_available_value,
                ContextCompat.getColor(context, R.color.budget_widget_value)
            )
            views.setTextColor(
                R.id.budget_needs_value,
                if (needsRaw < 0.0) {
                    ContextCompat.getColor(context, R.color.budget_widget_available_negative)
                } else {
                    ContextCompat.getColor(context, R.color.budget_widget_value)
                }
            )
            views.setTextColor(
                R.id.budget_wants_value,
                if (wantsRaw < 0.0) {
                    ContextCompat.getColor(context, R.color.budget_widget_available_negative)
                } else {
                    ContextCompat.getColor(context, R.color.budget_widget_value)
                }
            )

            val progressForView = percentUsed
            createProgressBarBitmap(context, mode.widthDp, progressForView)?.let { bitmap ->
                views.setImageViewBitmap(R.id.budget_progress_bar, bitmap)
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
            ?: 240
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            .takeIf { it > 0 }
            ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 }
            ?: 110

        val compact = widthDp < 220 || heightDp < 120
        val showGroups = widthDp >= 220 && heightDp >= 140
        val showUpdated = heightDp >= 102

        return WidgetMode(
            widthDp = widthDp,
            heightDp = heightDp,
            compact = compact,
            showGroups = showGroups,
            showUpdated = showUpdated
        )
    }

    private fun applyResponsiveLayout(context: Context, views: RemoteViews, mode: WidgetMode) {
        val density = context.resources.displayMetrics.density
        val horizontalPadding = if (mode.compact) 10 else 12
        val verticalPadding = if (mode.compact) 10 else 12
        views.setViewPadding(
            R.id.widget_budget_root,
            (horizontalPadding * density).roundToInt(),
            (verticalPadding * density).roundToInt(),
            (horizontalPadding * density).roundToInt(),
            (verticalPadding * density).roundToInt()
        )

        views.setViewVisibility(
            R.id.budget_group_row,
            if (mode.showGroups) View.VISIBLE else View.GONE
        )
        views.setViewVisibility(
            R.id.budget_last_updated,
            if (mode.showUpdated) View.VISIBLE else View.GONE
        )

        views.setTextViewTextSize(
            R.id.budget_title,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 12f else 13f
        )
        views.setTextViewTextSize(
            R.id.budget_assigned_value,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 11f else 13f
        )
        views.setTextViewTextSize(
            R.id.budget_activity_value,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 11f else 13f
        )
        views.setTextViewTextSize(
            R.id.budget_available_value,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 11f else 13f
        )
        views.setTextViewTextSize(
            R.id.budget_percent_value,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 9f else 10f
        )
        views.setTextViewTextSize(
            R.id.budget_needs_value,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 10f else 11f
        )
        views.setTextViewTextSize(
            R.id.budget_wants_value,
            TypedValue.COMPLEX_UNIT_SP,
            if (mode.compact) 10f else 11f
        )
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

        views.setOnClickPendingIntent(R.id.widget_budget_root, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.toggle_budget_visibility, toggleVisibilityPendingIntent)
    }

    private fun createProgressBarBitmap(
        context: Context,
        widthDp: Int,
        percentUsed: Double
    ): Bitmap? {
        val density = context.resources.displayMetrics.density
        val widthPx = ((widthDp - 44).coerceAtLeast(96) * density).toInt().coerceAtLeast(1)
        val heightPx = (8f * density).toInt().coerceAtLeast(1)

        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = ContextCompat.getColor(context, R.color.budget_widget_progress_track)
        }

        val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = when {
                percentUsed >= 100.0 -> ContextCompat.getColor(
                    context,
                    R.color.budget_widget_progress_danger
                )
                percentUsed >= 80.0 -> ContextCompat.getColor(
                    context,
                    R.color.budget_widget_progress_warn
                )
                else -> ContextCompat.getColor(context, R.color.budget_widget_progress_safe)
            }
        }

        val radius = heightPx / 2f
        val trackRect = RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat())
        canvas.drawRoundRect(trackRect, radius, radius, trackPaint)

        val progress = percentUsed.coerceIn(0.0, 100.0)
        val progressWidth = ((progress / 100.0) * widthPx).toFloat()
        if (progressWidth > 0f) {
            val progressRect = RectF(0f, 0f, progressWidth, heightPx.toFloat())
            canvas.drawRoundRect(progressRect, radius, radius, progressPaint)
        }

        return bitmap
    }

    private fun asPercentString(
        numerator: Double,
        denominator: Double,
        clampMin: Int,
        clampMax: Int
    ): String {
        if (denominator <= 0.0) return "--"
        val raw = ((numerator / denominator) * 100.0).roundToInt()
        val clamped = raw.coerceIn(clampMin, clampMax)
        return "$clamped%"
    }

}
